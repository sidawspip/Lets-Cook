import 'dart:io';

import 'package:lets_cook_windows/models/models.dart';
import 'package:lets_cook_windows/services/media_resolver.dart';

Future<void> main(List<String> arguments) async {
  final videoId = arguments.isEmpty ? 'M7lc1UVf-VE' : arguments.first;
  final resolver = SplitMediaResolver();
  try {
    final started = DateTime.now();
    final media = await resolver.resolve(
      RoomWatchState(
        provider: 'YOUTUBE',
        sourceType: 'YOUTUBE',
        mediaId: videoId,
        title: 'YouTube smoke test',
        playing: true,
        positionSeconds: 0,
      ),
    );
    final elapsed = DateTime.now().difference(started);
    stdout.writeln('resolved=$videoId');
    stdout.writeln('host=${media.uri.host}');
    stdout.writeln('qualityCount=${media.qualities.length}');
    stdout.writeln('elapsedMs=${elapsed.inMilliseconds}');
  } finally {
    await resolver.close();
  }
}
