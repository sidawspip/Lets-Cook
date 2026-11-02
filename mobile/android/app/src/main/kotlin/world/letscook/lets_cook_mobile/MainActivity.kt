package world.letscook.lets_cook_mobile

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Rational
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "letscook.world/device"
    private val notificationChannel = "room_events"
    private var channel: MethodChannel? = null
    private var pendingPayload: Map<String, String>? = null
    private var pipAutoEnabled = false
    private var pipEntryPending = false
    private var microphonePermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannel()
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).also { bridge ->
            bridge.setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestNotifications" -> { requestNotifications(); result.success(notificationsGranted()) }
                    "requestMicrophone" -> {
                        if (microphoneGranted()) {
                            result.success(true)
                        } else if (microphonePermissionResult != null) {
                            result.error("permission_in_progress", "A microphone permission request is already open.", null)
                        } else {
                            microphonePermissionResult = result
                            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 902)
                        }
                    }
                    "notificationStatus" -> result.success(notificationsGranted())
                    "microphoneStatus" -> result.success(microphoneGranted())
                    "showNotification" -> { showNotification(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()); result.success(null) }
                    "vibrateMention" -> { vibrateMention(); result.success(null) }
                    "enterPip" -> result.success(enterPip())
                    "setPipAutoEnabled" -> {
                        pipAutoEnabled = call.argument<Boolean>("enabled") == true
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            setPictureInPictureParams(
                                PictureInPictureParams.Builder()
                                    .setAspectRatio(Rational(16, 9))
                                    .setAutoEnterEnabled(pipAutoEnabled)
                                    .build()
                            )
                        }
                        result.success(null)
                    }
                    "isPipSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE))
                    "isInPip" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isInPictureInPictureMode)
                    "getLaunchPayload" -> { result.success(pendingPayload); pendingPayload = null }
                    else -> result.notImplemented()
                }
            }
        }
        deliverIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliverIntent(intent)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 902) {
            microphonePermissionResult?.success(microphoneGranted())
            microphonePermissionResult = null
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Android 12+ auto-enter gives Flutter time to render its video-only
        // inactive-state frame as the Home transition begins.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return
        if (!pipAutoEnabled || isInPictureInPictureMode || pipEntryPending) return
        pipEntryPending = true
        val bridge = channel
        if (bridge == null) {
            enterPip()
            return
        }
        bridge.invokeMethod("pipWillEnter", null, object : MethodChannel.Result {
            override fun success(result: Any?) = enterPipAfterFlutterFrame()
            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = enterPipAfterFlutterFrame()
            override fun notImplemented() = enterPipAfterFlutterFrame()
        })
    }

    private fun enterPipAfterFlutterFrame() {
        runOnUiThread {
            if (pipAutoEnabled && !isInPictureInPictureMode) enterPip()
            else pipEntryPending = false
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("pipModeChanged", isInPictureInPictureMode)
    }

    private fun requestNotifications() {
        if (Build.VERSION.SDK_INT >= 33 && !notificationsGranted()) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 901)
    }
    private fun notificationsGranted() = Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    private fun microphoneGranted() = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    private fun enterPip(): Boolean {
        pipEntryPending = false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) return false
        return enterPictureInPictureMode(
            PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .apply {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        setAutoEnterEnabled(pipAutoEnabled)
                    }
                }
                .build()
        )
    }
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= 26) (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(
            NotificationChannel(notificationChannel, "Room invites and messages", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Transient room invitations, mentions, and direct messages"
                enableVibration(true)
            }
        )
    }
    private fun vibrateMention() {
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        if (!vibrator.hasVibrator()) return
        val pattern = longArrayOf(0, 45, 55, 80)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, -1)
        }
    }
    private fun showNotification(arguments: Map<*, *>) {
        if (!notificationsGranted()) return
        val type = arguments["type"]?.toString() ?: "EVENT"
        val senderId = arguments["senderId"]?.toString() ?: ""
        val roomId = arguments["roomId"]?.toString() ?: ""
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("pushType", type); putExtra("senderId", senderId); putExtra("roomId", roomId)
        }
        val pending = PendingIntent.getActivity(this, (type + senderId + roomId).hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, notificationChannel)
            .setSmallIcon(applicationInfo.icon).setContentTitle(arguments["title"]?.toString() ?: "Let's Cook")
            .setContentText(arguments["body"]?.toString() ?: "").setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true).setContentIntent(pending).build()
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify((type + senderId + roomId).hashCode(), notification)
    }
    private fun deliverIntent(intent: Intent?) {
        val type = intent?.getStringExtra("pushType") ?: return
        val payload = mapOf("type" to type, "senderId" to (intent.getStringExtra("senderId") ?: ""), "roomId" to (intent.getStringExtra("roomId") ?: ""))
        pendingPayload = payload
        channel?.invokeMethod("notificationTap", payload)
        intent.removeExtra("pushType")
    }
}
