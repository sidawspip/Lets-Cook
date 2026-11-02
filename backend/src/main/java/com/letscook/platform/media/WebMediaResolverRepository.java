package com.letscook.platform.media;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Repository;
import org.springframework.web.server.ResponseStatusException;

import java.io.InputStream;
import java.net.InetAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * External-media gateway that safely fetches public HTTPS pages and extracts MP4/HLS metadata.
 * Rejects private-network addresses, nonstandard ports, excessive redirects, and oversized HTML.
 */
@Repository
class WebMediaResolverRepository {
    private static final int MAX_HTML_BYTES = 2_000_000;
    private static final Pattern TITLE = Pattern.compile("(?is)<title[^>]*>(.*?)</title>");
    private static final Pattern OG_TITLE = Pattern.compile("(?is)<meta[^>]+(?:property|name)=[\"']og:title[\"'][^>]+content=[\"']([^\"']+)");
    private static final Pattern OG_SITE = Pattern.compile("(?is)<meta[^>]+(?:property|name)=[\"']og:site_name[\"'][^>]+content=[\"']([^\"']+)");
    private static final List<Pattern> MEDIA_PATTERNS = List.of(
            Pattern.compile("(?is)<meta[^>]+(?:property|name)=[\"'](?:og:video(?::url)?|twitter:player:stream)[\"'][^>]+content=[\"']([^\"']+)"),
            Pattern.compile("(?is)<(?:video|source)[^>]+src=[\"']([^\"']+)"),
            Pattern.compile("(?is)video_(?:alt_)?url[0-9]*\\s*[:=]\\s*[\"']([^\"']+)"),
            Pattern.compile("(?is)[\"'](?:contentUrl|streamUrl|file|hls|src)[\"']\s*:\s*[\"']([^\"']+)"),
            Pattern.compile("(?is)[\"'][^\"']{0,80}[\"']\\s*:\\s*[\"'](https:[^\"']+?\\.(?:m3u8|mp4)(?:\\?[^\"']*)?)[\"']"),
            Pattern.compile("(?is)(https:\\/\\/[^\"'<>\\s]+?\\.(?:m3u8|mp4)(?:\\?[^\"'<>\\s]*)?)")
    );

    private final HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(8))
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();

    public ResolvedWebMedia resolve(@Valid ResolveWebMediaRequest request) {
        try {
            URI page = validatePublicHttps(URI.create(request.pageUrl().trim()));
            HttpResponse<InputStream> response = fetch(page);
            for (int redirects = 0; redirects < 3 && response.statusCode() / 100 == 3; redirects++) {
                String location = response.headers().firstValue("location")
                        .orElseThrow(() -> unsupported("The page redirected without a destination."));
                page = validatePublicHttps(page.resolve(location));
                response = fetch(page);
            }
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                throw unsupported("The selected page could not be opened.");
            }
            String contentType = response.headers().firstValue("content-type").orElse("").toLowerCase(Locale.ROOT);
            if (isHls(page.toString(), contentType) || isMp4(page.toString(), contentType)) {
                return result(page, page, filename(page), page.getHost(), contentType);
            }
            if (!contentType.contains("text/html") && !contentType.contains("application/xhtml")) {
                throw unsupported("The selected URL is not a supported webpage, MP4, or HLS stream.");
            }
            byte[] bytes = response.body().readNBytes(MAX_HTML_BYTES + 1);
            if (bytes.length > MAX_HTML_BYTES) throw unsupported("The selected page is too large to inspect safely.");
            String html = new String(bytes, StandardCharsets.UTF_8);
            URI media = findMedia(page, html);
            if (media == null) {
                throw unsupported("This page does not expose a public MP4 or HLS stream. DRM and login-bound video need a provider integration.");
            }
            String title = first(html, OG_TITLE, TITLE);
            String site = first(html, OG_SITE);
            return result(page, media, clean(title, filename(media)), clean(site, page.getHost()), "");
        } catch (ResponseStatusException exception) {
            throw exception;
        } catch (Exception exception) {
            throw unsupported("This page could not be resolved into a playable public video.");
        }
    }

    private HttpResponse<InputStream> fetch(URI uri) throws Exception {
        HttpRequest request = HttpRequest.newBuilder(uri)
                .timeout(Duration.ofSeconds(15))
                .header("Accept", "text/html,application/xhtml+xml,video/mp4,application/vnd.apple.mpegurl")
                .header("Accept-Language", "en-US,en;q=0.9")
                .header("User-Agent", "Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 Mobile Safari/537.36")
                .GET().build();
        return http.send(request, HttpResponse.BodyHandlers.ofInputStream());
    }

    private URI findMedia(URI page, String html) {
        var candidates = new LinkedHashSet<URI>();
        for (Pattern pattern : MEDIA_PATTERNS) {
            Matcher matcher = pattern.matcher(html);
            while (matcher.find()) {
                String value = decode(matcher.group(1)).replace("\\/", "/");
                try {
                    URI candidate = validatePublicHttps(page.resolve(value));
                    if (isHls(candidate.toString(), "") || isMp4(candidate.toString(), "")) {
                        // A template is player configuration, not a media
                        // response. The concrete request is captured by the
                        // mobile browser when playback actually starts.
                        if (!isUnresolvedTemplate(candidate)) candidates.add(candidate);
                    }
                } catch (Exception ignored) { }
            }
        }
        // Prefer a mobile-safe rendition instead of blindly accepting the
        // first URL in page JSON. Some sites list a 480p High-profile 60fps
        // stream first; that can overwhelm Android emulators and lower-end
        // phones even though a compatible 360p/240p rendition is available.
        return new ArrayList<>(candidates).stream()
                .min(Comparator.comparingInt(this::mobilePlaybackRank))
                .orElse(null);
    }

    int mobilePlaybackRank(URI candidate) {
        String value = candidate.toString().toLowerCase(Locale.ROOT);
        if (isUnresolvedTemplate(candidate)) return 100;
        // A multi-rendition endpoint contains labels such as 240p and 480p,
        // but it is not itself the 240p file. Prefer an explicit rendition
        // whenever the page exposes one; otherwise the CDN may still choose
        // the decoder-heavy 480p/60fps stream from this adaptive URL.
        int rank;
        if (value.contains("/multi=") || value.contains("multi=")) rank = 6;
        else if (value.contains("360p") || value.contains("_360.")) rank = 0;
        else if (value.contains("240p") || value.contains("_240.")) rank = 1;
        else if (isHls(value, "")) rank = 2;
        else if (value.contains("480p") || value.contains("_480.")) rank = 3;
        else if (value.contains("720p") || value.contains("1080p")) rank = 5;
        else rank = 4;
        if (value.contains("av1") || value.contains("h265") || value.contains("hevc")) rank += 10;
        if (value.contains("h264") || value.contains("avc1")) rank -= 1;
        return rank;
    }

    URI expandMobileTemplate(URI candidate) {
        String value = candidate.toString();
        if (!value.contains("_TPL_")) return candidate;

        var available = new LinkedHashSet<String>();
        Matcher matcher = Pattern.compile("(?:^|,)\\d+x\\d+:(\\d+p):").matcher(value);
        while (matcher.find()) available.add(matcher.group(1));
        for (String preferred : List.of("360p", "240p", "144p", "480p")) {
            if (available.contains(preferred)) {
                return URI.create(value.replace("_TPL_", preferred));
            }
        }
        return candidate;
    }

    boolean isUnresolvedTemplate(URI candidate) {
        String value = candidate.toString().toLowerCase(Locale.ROOT);
        return value.contains("_tpl_") || value.contains("{quality}") || value.contains("%7bquality%7d");
    }

    private URI validatePublicHttps(URI uri) throws Exception {
        if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost() == null || uri.getUserInfo() != null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Only public HTTPS URLs are supported.");
        }
        if (uri.getPort() != -1 && uri.getPort() != 443) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Only the standard HTTPS port is supported.");
        }
        for (InetAddress address : InetAddress.getAllByName(uri.getHost())) {
            if (address.isAnyLocalAddress() || address.isLoopbackAddress() || address.isLinkLocalAddress()
                    || address.isSiteLocalAddress() || address.isMulticastAddress()) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Private network URLs are not supported.");
            }
        }
        return uri;
    }

    private ResolvedWebMedia result(URI page, URI media, String title, String site, String contentType) {
        String provider = isHls(media.toString(), contentType) ? "DIRECT_HLS" : "DIRECT_MP4";
        return new ResolvedWebMedia(page.toString(), media.toString(), provider, title, site);
    }

    private static boolean isHls(String url, String type) {
        String value = url.toLowerCase(Locale.ROOT);
        return value.contains(".m3u8") || type.contains("mpegurl");
    }

    private static boolean isMp4(String url, String type) {
        String value = url.toLowerCase(Locale.ROOT);
        return value.contains(".mp4") || type.contains("video/mp4");
    }

    private static String first(String html, Pattern... patterns) {
        for (Pattern pattern : patterns) {
            Matcher matcher = pattern.matcher(html);
            if (matcher.find()) return decode(matcher.group(1));
        }
        return "";
    }

    private static String filename(URI uri) {
        String path = uri.getPath();
        int slash = path.lastIndexOf('/');
        String name = slash >= 0 ? path.substring(slash + 1) : path;
        return name.isBlank() ? "Web video" : name;
    }

    private static String clean(String value, String fallback) {
        String cleaned = decode(value).replaceAll("(?is)<[^>]+>", " ").replaceAll("\\s+", " ").trim();
        return cleaned.isBlank() ? fallback : cleaned.substring(0, Math.min(300, cleaned.length()));
    }

    private static String decode(String value) {
        return value == null ? "" : value.replace("&amp;", "&").replace("&quot;", "\"")
                .replace("&#39;", "'").replace("&lt;", "<").replace("&gt;", ">");
    }

    private static ResponseStatusException unsupported(String message) {
        return new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, message);
    }

    public record ResolveWebMediaRequest(@NotBlank String pageUrl) { }
    public record ResolvedWebMedia(String pageUrl, String sourceUrl, String sourceType, String title, String siteName) { }
}
