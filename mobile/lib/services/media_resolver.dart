import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/models.dart';

abstract interface class MediaResolver {
  Future<ResolvedMedia> resolve(
    RoomWatchState state, {
    String quality = 'auto',
  });
  Future<List<CaptionCue>> captions(String mediaId, String languageCode);
  Future<void> close();
}

class ResolvedMedia {
  const ResolvedMedia(
    this.uri, {
    this.title,
    this.qualities = const [],
    this.captionLanguages = const {},
    this.httpHeaders = const {},
    this.fallbackSources = const [],
  });

  final Uri uri;
  final String? title;
  final List<String> qualities;
  final Map<String, String> captionLanguages;
  final Map<String, String> httpHeaders;
  final List<ResolvedMediaSource> fallbackSources;

  /// Player-ready sources in preference order. The primary URI always wins;
  /// duplicate fallback URIs are removed without losing per-source headers.
  List<ResolvedMediaSource> get orderedSources {
    final seen = <String>{};
    final result = <ResolvedMediaSource>[];
    for (final source in [
      ResolvedMediaSource(uri, httpHeaders: httpHeaders),
      ...fallbackSources,
    ]) {
      if (seen.add(source.uri.toString())) result.add(source);
    }
    return result;
  }

  ResolvedMedia withFallbackSources(Iterable<ResolvedMediaSource> sources) =>
      ResolvedMedia(
        uri,
        title: title,
        qualities: qualities,
        captionLanguages: captionLanguages,
        httpHeaders: httpHeaders,
        fallbackSources: [...sources, ...fallbackSources],
      );
}

class ResolvedMediaSource {
  const ResolvedMediaSource(this.uri, {this.httpHeaders = const {}});

  final Uri uri;
  final Map<String, String> httpHeaders;
}

List<ResolvedMediaSource> resolvedMediaSourcesFromResponse(
  Iterable<Map<String, dynamic>> sources, {
  Uri? sourcePage,
}) {
  const allowedHeaders = {'user-agent', 'referer', 'origin', 'accept'};
  final result = <ResolvedMediaSource>[];
  for (final source in sources) {
    final uri = Uri.tryParse((source['url'] ?? '').toString().trim());
    final type = (source['sourceType'] ?? '').toString().trim().toUpperCase();
    if (uri?.scheme != 'https' ||
        uri?.host.isEmpty != false ||
        hasUnresolvedMediaTemplate(uri!) ||
        !const {'DIRECT_MP4', 'DIRECT_HLS'}.contains(type)) {
      continue;
    }
    final supplied = source['httpHeaders'];
    final headers = <String, String>{
      ...directMediaHttpHeaders(uri, sourcePage: sourcePage),
    };
    if (supplied is Map) {
      for (final entry in supplied.entries) {
        final name = entry.key.toString().trim();
        final value = entry.value?.toString().trim() ?? '';
        if (allowedHeaders.contains(name.toLowerCase()) && value.isNotEmpty) {
          headers[name] = value;
        }
      }
    }
    result.add(ResolvedMediaSource(uri, httpHeaders: headers));
  }
  return result;
}

/// Streams observed by the embedded browser from a provider-owned media host
/// have already succeeded inside that page. Re-probing them through Dart's
/// separate HTTP stack can fail on networks where WebView/ExoPlayer can still
/// reach the CDN, and it needlessly consumes short-lived signed URLs.
bool isProviderOwnedBrowserMedia(Uri uri, {Uri? sourcePage}) {
  final mediaHost = uri.host.toLowerCase();
  final pageHost = sourcePage?.host.toLowerCase() ?? '';
  return pageHost.contains('xhamster') &&
      (mediaHost == 'xhmediacdn.com' || mediaHost.endsWith('.xhmediacdn.com'));
}

/// Browser-backed CDNs commonly require the same Referer/User-Agent that was
/// used to discover the stream. Keep the rule narrowly scoped: ordinary
/// public media URLs receive no synthetic headers.
Map<String, String> directMediaHttpHeaders(Uri uri, {Uri? sourcePage}) {
  final host = uri.host.toLowerCase();
  final isXhMediaHost =
      host.endsWith('.xhpingcdn.com') ||
      host.endsWith('.xhcdn.com') ||
      host.endsWith('.xhmediacdn.com');
  if (!isXhMediaHost) {
    if (sourcePage == null || sourcePage.scheme != 'https') return const {};
    final origin = '${sourcePage.scheme}://${sourcePage.authority}';
    return {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 15; Mobile) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36',
      'Referer': sourcePage == uri ? '$origin/' : sourcePage.toString(),
      'Origin': origin,
    };
  }

  String? refererHost;
  for (final segment in uri.pathSegments) {
    if (!segment.startsWith('referer=force,')) continue;
    final allowed = segment.substring('referer=force,'.length).split(',');
    for (final candidate in allowed.reversed) {
      final normalized = candidate.trim().replaceFirst(RegExp(r'^\.+'), '');
      if (normalized.isNotEmpty && !normalized.endsWith('xhcdn.com')) {
        refererHost = normalized;
        break;
      }
    }
  }
  final sourceHost = sourcePage?.host.toLowerCase();
  refererHost ??= sourceHost != null && sourceHost.contains('xhamster')
      ? sourceHost
      : 'xhamster.com';
  return {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
    'Referer': 'https://$refererHost/',
    'Origin': 'https://$refererHost',
  };
}

/// Browser players can publish a signed URL with an unresolved `_TPL_`
/// filename plus an inline rendition map. Resolve it before handing the URL
/// to ExoPlayer, which otherwise receives a non-media template response.
Uri resolveDirectMediaTemplate(Uri uri) {
  final value = uri.toString();
  if (!value.contains('_TPL_')) return uri;
  final available = RegExp(r'(?:^|,)\d+x\d+:(\d+p):')
      .allMatches(value)
      .map((match) => match.group(1))
      .whereType<String>()
      .toSet();
  for (final preferred in const ['360p', '240p', '144p', '480p']) {
    if (available.contains(preferred)) {
      return Uri.parse(value.replaceFirst('_TPL_', preferred));
    }
  }
  return uri;
}

bool hasUnresolvedMediaTemplate(Uri uri) {
  final value = uri.toString().toUpperCase();
  return value.contains('_TPL_') ||
      value.contains('{QUALITY}') ||
      value.contains('%7BQUALITY%7D');
}

/// Checks that a browser-discovered URL is a real media response before it is
/// offered to the room. Match Rave's inexpensive validation order: HEAD first,
/// then a small ranged GET when HEAD is explicitly unsupported.
Future<bool> probeDirectMedia(
  Uri uri, {
  required String sourceType,
  Uri? sourcePage,
}) async {
  if (uri.scheme != 'https' || hasUnresolvedMediaTemplate(uri)) return false;
  final client = http.Client();
  try {
    final headers = <String, String>{
      ...directMediaHttpHeaders(uri, sourcePage: sourcePage),
      'Accept': sourceType == 'DIRECT_HLS'
          ? 'application/vnd.apple.mpegurl,application/x-mpegURL,*/*'
          : 'video/mp4,application/octet-stream,*/*',
    };
    final head = http.Request('HEAD', uri)..headers.addAll(headers);
    final headResponse = await client
        .send(head)
        .timeout(const Duration(seconds: 10));
    final headType = headResponse.headers['content-type']?.toLowerCase() ?? '';
    if (headResponse.statusCode >= 200 && headResponse.statusCode < 300) {
      if (sourceType == 'DIRECT_HLS' && headType.contains('mpegurl')) {
        return true;
      }
      if (sourceType == 'DIRECT_MP4' &&
          (headType.startsWith('video/') ||
              (headType.contains('application/octet-stream') &&
                  uri.path.toLowerCase().contains('.mp4')))) {
        return true;
      }
    }
    // Browser media CDNs commonly reject HEAD even though the same signed URL
    // accepts a tiny ranged GET with the page's Referer/Origin. Validate that
    // response without downloading the media body.
    final request = http.Request('GET', uri)
      ..headers.addAll(headers)
      ..headers['Range'] = 'bytes=0-4095';
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 && response.statusCode != 206) {
      return false;
    }
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    final firstChunk = await response.stream
        .timeout(const Duration(seconds: 5))
        .first;
    if (sourceType == 'DIRECT_HLS') {
      return contentType.contains('mpegurl') ||
          utf8
              .decode(firstChunk, allowMalformed: true)
              .trimLeft()
              .startsWith('#EXTM3U');
    }
    final signature = ascii.decode(
      firstChunk.take(16).toList(),
      allowInvalid: true,
    );
    return contentType.startsWith('video/') || signature.contains('ftyp');
  } catch (_) {
    return false;
  } finally {
    client.close();
  }
}

class CaptionCue {
  const CaptionCue(this.text, this.start, this.end);
  final String text;
  final Duration start;
  final Duration end;
}

class SplitMediaResolver implements MediaResolver {
  final YoutubeExplode _youtube = YoutubeExplode();

  @override
  Future<ResolvedMedia> resolve(
    RoomWatchState state, {
    String quality = 'auto',
  }) async {
    final provider = state.provider.toUpperCase();
    final sourceType = state.sourceType.toUpperCase();
    if (provider != 'YOUTUBE') {
      final parsedUri = Uri.tryParse(state.sourceUrl ?? state.mediaId);
      final uri = parsedUri;
      final sourcePage = Uri.tryParse(state.mediaId);
      if (uri == null || uri.scheme != 'https') {
        throw const FormatException('Provider media requires an HTTPS URL.');
      }
      if (hasUnresolvedMediaTemplate(uri)) {
        throw const FormatException(
          'The provider returned an unresolved media template. Play the '
          'video in the web browser again to capture its real stream.',
        );
      }
      final hls =
          provider == 'DIRECT_HLS' ||
          sourceType == 'DIRECT_HLS' ||
          uri.path.toLowerCase().endsWith('.m3u8');
      if (hls) {
        return _resolveHls(uri, quality, sourcePage: sourcePage);
      }
      return ResolvedMedia(
        uri,
        httpHeaders: directMediaHttpHeaders(uri, sourcePage: sourcePage),
      );
    }
    // Resolve the stream before making optional metadata requests. On Android,
    // three simultaneous Innertube requests can starve the manifest lookup.
    final manifest = await _youtube.videos.streamsClient
        .getManifest(state.mediaId)
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () async {
            return _youtube.videos.streamsClient
                .getManifest(
                  state.mediaId,
                  ytClients: [YoutubeApiClient.androidSdkless],
                  requireWatchPage: false,
                )
                .timeout(
                  const Duration(seconds: 15),
                  onTimeout: () => throw TimeoutException(
                    'YouTube took too long to provide a playable stream.',
                  ),
                );
          },
        );
    final title = await _youtubeTitle(state.mediaId);
    final captionLanguages = await _youtubeCaptionLanguages(state.mediaId);
    final streams = manifest.muxed.sortByVideoQuality();
    if (streams.isEmpty) {
      throw StateError('No playable YouTube stream is available.');
    }
    final qualities =
        streams.map((stream) => stream.qualityLabel).toSet().toList()
          ..sort((a, b) => _height(a).compareTo(_height(b)));
    final selected = quality == 'auto'
        ? streams.lastWhere(
            (stream) => _height(stream.qualityLabel) <= 360,
            orElse: () => streams.first,
          )
        : streams.lastWhere(
            (stream) => stream.qualityLabel == quality,
            orElse: () => streams.last,
          );
    return ResolvedMedia(
      selected.url,
      title: title,
      qualities: qualities.reversed.toList(),
      captionLanguages: captionLanguages,
    );
  }

  int _height(String label) =>
      int.tryParse(RegExp(r'\d+').firstMatch(label)?.group(0) ?? '') ?? 0;

  Future<String?> _youtubeTitle(String mediaId) async {
    try {
      final title =
          (await _youtube.videos
                  .get(mediaId)
                  .timeout(const Duration(seconds: 4)))
              .title
              .trim();
      return title.isEmpty ? null : title;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> _youtubeCaptionLanguages(String mediaId) async {
    try {
      final captions = await _youtube.videos.closedCaptions
          .getManifest(mediaId)
          .timeout(const Duration(seconds: 4));
      return {
        for (final track in captions.tracks)
          track.language.code: track.language.name,
      };
    } catch (_) {
      return const {};
    }
  }

  Future<ResolvedMedia> _resolveHls(
    Uri masterUri,
    String quality, {
    Uri? sourcePage,
  }) async {
    final headers = directMediaHttpHeaders(masterUri, sourcePage: sourcePage);
    try {
      final response = await http
          .get(masterUri, headers: headers)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ResolvedMedia(masterUri, httpHeaders: headers);
      }
      final lines = response.body.split(RegExp(r'\r?\n'));
      final variants = <String, Uri>{};
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index].trim();
        if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
        final resolution = RegExp(
          r'RESOLUTION=\d+x(\d+)',
          caseSensitive: false,
        ).firstMatch(line);
        final height = resolution?.group(1);
        if (height == null) continue;
        var next = index + 1;
        while (next < lines.length &&
            (lines[next].trim().isEmpty || lines[next].startsWith('#'))) {
          next++;
        }
        if (next >= lines.length) continue;
        final variant = Uri.tryParse(lines[next].trim());
        if (variant == null) continue;
        variants['${height}p'] = masterUri.resolveUri(variant);
      }
      final qualities = variants.keys.toList()
        ..sort((a, b) => _height(b).compareTo(_height(a)));
      final selected = quality == 'auto' ? null : variants[quality];
      final primary = selected ?? masterUri;
      final fallbackUris = <Uri>[
        // If adaptive playback fails, try concrete renditions from lower
        // decoder/network cost to higher, then the master as a final option.
        ...qualities.reversed
            .map((label) => variants[label]!)
            .where((uri) => uri != primary),
        if (masterUri != primary) masterUri,
      ];
      return ResolvedMedia(
        primary,
        qualities: qualities,
        httpHeaders: headers,
        fallbackSources: [
          for (final uri in fallbackUris)
            ResolvedMediaSource(
              uri,
              httpHeaders: directMediaHttpHeaders(uri, sourcePage: sourcePage),
            ),
        ],
      );
    } catch (_) {
      // A media playlist or a server that rejects manifest probing is still
      // playable by ExoPlayer; it simply remains source-controlled Auto.
      return ResolvedMedia(masterUri, httpHeaders: headers);
    }
  }

  @override
  Future<List<CaptionCue>> captions(String mediaId, String languageCode) async {
    final manifest = await _youtube.videos.closedCaptions.getManifest(mediaId);
    final matches = manifest.getByLanguage(languageCode, autoGenerated: true);
    if (matches.isEmpty) return const [];
    final track = await _youtube.videos.closedCaptions.get(matches.first);
    return track.captions
        .map((cue) => CaptionCue(cue.text, cue.offset, cue.end))
        .toList();
  }

  @override
  Future<void> close() async => _youtube.close();
}
