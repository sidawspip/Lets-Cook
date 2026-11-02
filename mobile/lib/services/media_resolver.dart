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
Map<String, String> directMediaHttpHeaders(Uri uri) {
  final host = uri.host.toLowerCase();
  if (!host.endsWith('.xhpingcdn.com') && !host.endsWith('.xhcdn.com')) {
    return const {};
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
/// offered to the room. A small range request avoids downloading the video.
Future<bool> probeDirectMedia(Uri uri, {required String sourceType}) async {
  if (uri.scheme != 'https' || hasUnresolvedMediaTemplate(uri)) return false;
  final client = http.Client();
  try {
    final request = http.Request('GET', uri)
      ..headers.addAll(directMediaHttpHeaders(uri))
      ..headers['Range'] = 'bytes=0-4095'
      ..headers['Accept'] = sourceType == 'DIRECT_HLS'
          ? 'application/vnd.apple.mpegurl,application/x-mpegURL,*/*'
          : 'video/mp4,application/octet-stream,*/*';
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
        return _resolveHls(uri, quality);
      }
      return ResolvedMedia(uri, httpHeaders: directMediaHttpHeaders(uri));
    }
    final titleFuture = _youtubeTitle(state.mediaId);
    final captionsFuture = _youtubeCaptionLanguages(state.mediaId);
    final manifest = await _youtube.videos.streamsClient
        .getManifest(state.mediaId)
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TimeoutException(
            'YouTube took too long to provide a playable stream.',
          ),
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
        ? streams.last
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

  Future<ResolvedMedia> _resolveHls(Uri masterUri, String quality) async {
    final headers = directMediaHttpHeaders(masterUri);
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
