import 'dart:convert';
import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main(List<String> arguments) async {
  final id = arguments.isEmpty ? '' : arguments.first;
  final quality = arguments.length > 1 ? arguments[1] : 'auto';
  if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
    stderr.writeln('Invalid YouTube video ID');
    exitCode = 2;
    return;
  }
  final youtube = YoutubeExplode();
  try {
    Future<StreamManifest> getManifest() => youtube.videos.streamsClient.getManifest(id);
    StreamManifest manifest;
    try {
      manifest = await getManifest().timeout(const Duration(seconds: 12));
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      manifest = await getManifest().timeout(const Duration(seconds: 15));
    }
    final streams = manifest.muxed.sortByVideoQuality();
    if (streams.isEmpty) throw StateError('No playable YouTube stream is available');
    int height(String label) => int.tryParse(RegExp(r'\d+').firstMatch(label)?.group(0) ?? '') ?? 0;
    final selected = quality == 'auto'
        ? streams.lastWhere((stream) => height(stream.qualityLabel) <= 360, orElse: () => streams.first)
        : streams.lastWhere((stream) => stream.qualityLabel == quality, orElse: () => streams.last);
    stdout.writeln(jsonEncode({
      'url': selected.url.toString(),
      'quality': selected.qualityLabel,
      'qualities': streams.map((stream) => stream.qualityLabel).toSet().toList(),
    }));
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } finally {
    youtube.close();
  }
}
