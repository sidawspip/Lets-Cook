package world.letscook.lets_cook_mobile

import android.app.Activity
import android.net.Uri
import android.util.Log
import android.view.View
import android.view.SurfaceView
import android.widget.FrameLayout
import android.webkit.CookieManager
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.DrmSessionManager
import androidx.media3.exoplayer.drm.HttpMediaDrmCallback
import androidx.media3.exoplayer.drm.MediaDrmCallback
import androidx.media3.common.util.UnstableApi
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.UUID
import java.util.concurrent.Executors
import org.json.JSONObject

/** Device-local protected playback. The room transports episode identity and state only. */
@OptIn(UnstableApi::class)
internal class CrunchyrollRoomPlayer private constructor(private val activity: Activity) : PlatformView {
    private val surface = SurfaceView(activity)
    private val view = FrameLayout(activity).apply {
        addView(surface, FrameLayout.LayoutParams(-1, -1))
    }
    private val io = Executors.newSingleThreadExecutor()
    private var player: ExoPlayer? = null
    private var session: Session? = null
    private var generation = 0
    private var playerError: String? = null
    private var basicToken: String? = null
    private var access: Access? = null

    private data class Session(val videoId: String, val playbackToken: String)
    private data class Access(val token: String, val accountId: String?, val validUntil: Long)
    private data class Stream(val url: String, val token: String)

    override fun getView(): View = view

    override fun dispose() {
        generation++
        player?.release()
        player = null
        surface.holder.setKeepScreenOn(false)
        session = null
        io.shutdownNow()
        if (active === this) active = null
    }

    private fun cookies(): String = CookieManager.getInstance()
        .getCookie("https://www.crunchyroll.com").orEmpty()

    private fun execute(url: String, method: String = "GET", headers: Map<String, String> = emptyMap(), body: ByteArray? = null): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 15_000
            connection.readTimeout = 25_000
            connection.requestMethod = method
            headers.forEach { (name, value) -> connection.setRequestProperty(name, value) }
            if (body != null) {
                connection.doOutput = true
                connection.outputStream.use { it.write(body) }
            }
            val bytes = (if (connection.responseCode in 200..299) connection.inputStream else connection.errorStream)
                ?.use { it.readBytes() } ?: ByteArray(0)
            if (connection.responseCode !in 200..299) throw IOException("Crunchyroll HTTP ${connection.responseCode}")
            return bytes.toString(Charsets.UTF_8)
        } finally { connection.disconnect() }
    }

    private fun basicAuth(): String {
        basicToken?.let { return it }
        val page = execute("https://www.crunchyroll.com/", headers = mapOf("Cookie" to cookies()))
        val appConfig = Regex("window\\.__APP_CONFIG__\\s*=\\s*(\\{[^<]+\\})", RegexOption.DOT_MATCHES_ALL)
            .find(page)?.groupValues?.get(1)
        val etpConfig = if (appConfig == null) Regex("window\\.etp\\s*=\\s*(\\{.+?\\})(?:;|\\s*<)", RegexOption.DOT_MATCHES_ALL)
            .find(page)?.groupValues?.get(1) else null
        val params = when {
            appConfig != null -> JSONObject(appConfig).getJSONObject("cxApiParams")
            etpConfig != null -> JSONObject(etpConfig).getJSONObject("config").getJSONObject("cxApiParams")
            else -> throw IOException("Crunchyroll configuration was unavailable")
        }
        val id = params.optString("accountAuthClientId").ifBlank { params.getString("anonClientId") }
        return "Basic " + android.util.Base64.encodeToString("$id:".toByteArray(), android.util.Base64.NO_WRAP)
            .also { basicToken = "Basic $it" }
    }

    private fun cookieValue(name: String): String? = cookies().split(';')
        .map { it.trim() }.firstOrNull { it.startsWith("$name=") }?.substringAfter('=')

    @Synchronized private fun auth(): Access {
        access?.let { if (System.currentTimeMillis() < it.validUntil - 60_000) return it }
        val etp = cookieValue("etp_rt")
        val device = cookieValue("device_id")?.uppercase() ?: UUID.randomUUID().toString().uppercase()
        val form = mutableListOf<Pair<String, String>>()
        if (etp == null) {
            form += "scope" to "offline_access"
        } else form += "etp_rt_cookie" to etp
        form += "grant_type" to (if (etp == null) "client_id" else "etp_rt_cookie")
        form += "device_id" to device
        form += "device_type" to "Chrome on Android"
        val formBytes = form.joinToString("&") { (key, value) ->
            "${URLEncoder.encode(key, "UTF-8")}=${URLEncoder.encode(value, "UTF-8")}" }.toByteArray()
        val headers = mutableMapOf("Cookie" to cookies(), "Authorization" to basicAuth(),
            "Content-Type" to "application/x-www-form-urlencoded")
        if (etp == null) headers["ETP-Anonymous-ID"] = UUID.randomUUID().toString()
        val json = JSONObject(execute("https://www.crunchyroll.com/auth/v1/token", "POST", headers, formBytes))
        return Access(json.getString("access_token"), json.optString("account_id").ifBlank { null },
            System.currentTimeMillis() + json.optLong("expires_in", 300) * 1000).also { access = it }
    }

    private fun streams(videoId: String, credential: Access): Stream {
        val json = JSONObject(execute("https://www.crunchyroll.com/playback/v2/$videoId/web/chrome/play",
            headers = mapOf("Authorization" to "Bearer ${credential.token}",
                "Cookie" to cookies(), "User-Agent" to USER_AGENT)))
        return Stream(json.getString("url"), json.getString("token"))
    }

    private fun drmCallback(session: Session): MediaDrmCallback {
        val provision = HttpMediaDrmCallback("", false, DefaultHttpDataSource.Factory())
        return object : MediaDrmCallback {
            override fun executeProvisionRequest(uuid: UUID, request: androidx.media3.exoplayer.drm.ExoMediaDrm.ProvisionRequest): MediaDrmCallback.Response =
                provision.executeProvisionRequest(uuid, request)

            override fun executeKeyRequest(uuid: UUID, request: androidx.media3.exoplayer.drm.ExoMediaDrm.KeyRequest): MediaDrmCallback.Response {
                val credential = auth()
                val json = JSONObject(execute("https://www.crunchyroll.com/license/v1/license/widevine", "POST",
                    mapOf("Authorization" to "Bearer ${credential.token}",
                        "X-Cr-Content-Id" to session.videoId,
                        "X-Cr-Video-Token" to session.playbackToken,
                        "Content-Type" to "application/octet-stream"), request.data))
                return MediaDrmCallback.Response(android.util.Base64.decode(json.getString("license"), android.util.Base64.DEFAULT))
            }
        }
    }

    private fun open(videoId: String, result: MethodChannel.Result) {
        Log.i("XynkCrunchyroll", "Opening episode $videoId")
        val ticket = ++generation
        player?.release()
        player = null
        surface.holder.setKeepScreenOn(false)
        session = null
        playerError = null
        io.execute {
            try {
                val credential = auth()
                Log.i("XynkCrunchyroll", "Provider authentication ready; account=${credential.accountId != null}; sessionCookie=${cookieValue("etp_rt") != null}")
                val stream = streams(videoId, credential)
                Log.i("XynkCrunchyroll", "Provider playback session ready")
                if (stream.token.isBlank()) throw IOException("Crunchyroll returned no playback token")
                val current = Session(videoId, stream.token)
                val url = if (credential.accountId != null) {
                    Uri.parse(stream.url).buildUpon()
                        .appendQueryParameter("playbackGuid", stream.token)
                        .apply { credential.accountId?.let { appendQueryParameter("account_id", it) } }
                        .build().toString()
                } else stream.url
                activity.runOnUiThread {
                    if (ticket != generation) { result.error("cancelled", "Playback changed", null); return@runOnUiThread }
                    try {
                        session = current
                        val drm = DefaultDrmSessionManager.Builder().setMultiSession(true).build(drmCallback(current))
                        val dataSource = DefaultDataSource.Factory(activity,
                            DefaultHttpDataSource.Factory().setUserAgent(USER_AGENT)
                                .setDefaultRequestProperties(mapOf(
                                    "Cookie" to cookies(),
                                    "Authorization" to "Bearer ${credential.token}"
                                )))
                        val source = DashMediaSource.Factory(dataSource)
                            .setDrmSessionManagerProvider { drm }
                            .createMediaSource(MediaItem.Builder().setUri(url)
                                .setMimeType(MimeTypes.APPLICATION_MPD).build())
                        val created = ExoPlayer.Builder(activity).build()
                        created.addListener(object : Player.Listener {
                            override fun onPlaybackStateChanged(playbackState: Int) {
                                Log.i("XynkCrunchyroll", "Playback state $playbackState")
                            }
                            override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                                playerError = error.message ?: "Crunchyroll playback failed"
                                Log.e("XynkCrunchyroll", "Playback failed", error)
                            }
                        })
                        player = created
                        created.setVideoSurfaceView(surface)
                        surface.holder.setKeepScreenOn(true)
                        created.setMediaSource(source)
                        created.prepare()
                        result.success(null)
                    } catch (error: Exception) { playerError = error.message; Log.e("XynkCrunchyroll", "Player setup failed", error); result.error("player", error.message, null) }
                }
            } catch (error: Exception) {
                Log.e("XynkCrunchyroll", "Provider setup failed", error)
                activity.runOnUiThread { playerError = error.message; result.error("provider", error.message, null) }
            }
        }
    }

    private fun handle(method: String, args: Map<*, *>?, result: MethodChannel.Result) {
        when (method) {
            "open" -> {
                val id = args?.get("videoId") as? String
                if (id.isNullOrBlank() || !Regex("^[A-Za-z0-9]+$").matches(id))
                    result.error("video_id", "Invalid Crunchyroll episode ID", null)
                else open(id, result)
            }
            "play" -> { player?.play(); result.success(null) }
            "pause" -> { player?.pause(); result.success(null) }
            "seek" -> { player?.seekTo((args?.get("positionMs") as? Number)?.toLong() ?: 0); result.success(null) }
            "speed" -> { player?.setPlaybackSpeed(((args?.get("speed") as? Number)?.toFloat() ?: 1f).coerceIn(0.25f, 2f)); result.success(null) }
            "volume" -> { player?.volume = ((args?.get("volume") as? Number)?.toFloat() ?: 1f).coerceIn(0f, 1f); result.success(null) }
            "snapshot" -> result.success(mapOf(
                "positionMs" to (player?.currentPosition ?: 0L),
                "durationMs" to (player?.duration ?: 0L),
                "playing" to (player?.isPlaying == true),
                "buffering" to (player?.playbackState == Player.STATE_BUFFERING),
                "ready" to (player?.playbackState == Player.STATE_READY),
                "ended" to (player?.playbackState == Player.STATE_ENDED),
                "error" to playerError))
            "close" -> { generation++; player?.release(); player = null; surface.holder.setKeepScreenOn(false); session = null; result.success(null) }
            else -> result.notImplemented()
        }
    }

    companion object {
        private const val USER_AGENT = "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36"
        private var active: CrunchyrollRoomPlayer? = null

        fun register(activity: Activity, engine: FlutterEngine) {
            engine.platformViewsController.registry.registerViewFactory("xynk.in/crunchyroll-player",
                object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                    override fun create(context: android.content.Context, viewId: Int, args: Any?): PlatformView =
                        CrunchyrollRoomPlayer(activity).also { active = it }
                })
            MethodChannel(engine.dartExecutor.binaryMessenger, "xynk.in/crunchyroll-player")
                .setMethodCallHandler { call, result ->
                    val current = active
                    if (current == null) result.error("not_ready", "Player view is not ready", null)
                    else current.handle(call.method, call.arguments as? Map<*, *>, result)
                }
        }
    }
}
