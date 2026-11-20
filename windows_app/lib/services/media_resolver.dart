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
  });

  final Uri uri;
  final String? title;
  final List<String> qualities;
  final Map<String, String> captionLanguages;
  final Map<String, String> httpHeaders;
}

/// Browser-backed CDNs commonly require the same Referer/User-Agent that was
/// used to discover the stream. Keep the rule narrowly scoped: ordinary
/// public media URLs receive no synthetic headers.
Map<String, String> directMediaHttpHeaders(Uri uri, {Uri? sourcePage}) {
  final host = uri.host.toLowerCase();
  if ((host == 'xhmediacdn.com' || host.endsWith('.xhmediacdn.com')) &&
      sourcePage != null &&
      sourcePage.scheme == 'https') {
    final origin = '${sourcePage.scheme}://${sourcePage.authority}';
    return {
      'Referer': '$origin/',
      'Origin': origin,
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/141.0 Mobile Safari/537.36',
    };
  }
  if (!host.endsWith('.xhpingcdn.com') && !host.endsWith('.xhcdn.com')) {
    if (sourcePage == null || sourcePage.scheme != 'https') return const {};
    final origin = '${sourcePage.scheme}://${sourcePage.authority}';
    return {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 '
          'Safari/537.36',
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
  refererHost ??= 'xhamster.com';
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
    // Match Rave's ordering: a ranged request is a compatibility fallback
    // for servers that reject HEAD, not a download attempt for every bad URL.
    if (headResponse.statusCode != 405) return false;

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

typedef DirectMediaProbe =
    Future<bool> Function(
      Uri uri, {
      required String sourceType,
      Uri? sourcePage,
    });

class SplitMediaResolver implements MediaResolver {
  SplitMediaResolver({DirectMediaProbe mediaProbe = probeDirectMedia})
    : _mediaProbe = mediaProbe;

  final YoutubeExplode _youtube = YoutubeExplode();
  final DirectMediaProbe _mediaProbe;

  @override
  Future<ResolvedMedia> resolve(
    RoomWatchState state, {
    String quality = 'auto',
  }) async {
    final provider = state.provider.toUpperCase();
    if (provider != 'YOUTUBE') {
      final parsedUri = Uri.tryParse(state.sourceUrl ?? state.mediaId);
      final uri = parsedUri;
      final sourcePage = Uri.tryParse(state.mediaId);
      if (uri == null || uri.scheme != 'https') {
        throw const FormatException(
          'This provider did not return a playable HTTPS media URL.',
        );
      }
      if (hasUnresolvedMediaTemplate(uri)) {
        throw const FormatException(
          'The provider returned an unresolved media template. Play the '
          'video in the web browser again to capture its real stream.',
        );
      }
      final hls =
          provider == 'DIRECT_HLS' || uri.path.toLowerCase().endsWith('.m3u8');
      final sourceType = hls ? 'DIRECT_HLS' : 'DIRECT_MP4';
      if (!await _mediaProbe(
        uri,
        sourceType: sourceType,
        sourcePage: sourcePage,
      )) {
        throw const FormatException(
          'The selected address returned a webpage instead of playable video. '
          'Start the video in Web and select it again so its real stream can '
          'be captured.',
        );
      }
      if (hls) {
        return _resolveHls(uri, quality, sourcePage: sourcePage);
      }
      return ResolvedMedia(
        uri,
        httpHeaders: directMediaHttpHeaders(uri, sourcePage: sourcePage),
      );
    }
    final titleFuture = _youtubeTitle(state.mediaId);
    final captionsFuture = _youtubeCaptionLanguages(state.mediaId);
    var manifest = await _youtube.videos.streamsClient
        .getManifest(state.mediaId)
        .timeout(
          const Duration(seconds: 12),
          onTimeout: () async {
            await Future<void>.delayed(const Duration(milliseconds: 350));
            return _youtube.videos.streamsClient
                .getManifest(state.mediaId)
                .timeout(
                  const Duration(seconds: 15),
                  onTimeout: () => throw TimeoutException(
                    'YouTube took too long to provide a playable stream.',
                  ),
                );
          },
        );
    final title = await titleFuture;
    final captionLanguages = await captionsFuture;
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
      return ResolvedMedia(
        selected ?? masterUri,
        qualities: qualities,
        httpHeaders: headers,
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
