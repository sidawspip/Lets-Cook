import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Android's provider-authenticated Media3 player. Credentials stay on device.
class CrunchyrollRoomPlayer {
  static const _channel = MethodChannel('xynk.in/crunchyroll-player');

  static bool get supported => defaultTargetPlatform == TargetPlatform.android;

  static String? videoId(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !(uri.host == 'crunchyroll.com' ||
            uri.host.endsWith('.crunchyroll.com'))) {
      return null;
    }
    final parts = uri.pathSegments;
    if (parts.length < 2 || parts[0] != 'watch') return null;
    final id = parts[1];
    return RegExp(r'^[A-Za-z0-9]+$').hasMatch(id) ? id : null;
  }

  static Future<void> open(String videoId) async {
    for (var attempt = 0; attempt < 15; attempt++) {
      try {
        await _channel.invokeMethod<void>('open', {'videoId': videoId});
        return;
      } on PlatformException catch (error) {
        if (error.code != 'not_ready' || attempt == 14) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  static Future<void> play() => _channel.invokeMethod<void>('play');
  static Future<void> pause() => _channel.invokeMethod<void>('pause');
  static Future<void> seek(double seconds) => _channel.invokeMethod<void>(
    'seek',
    {'positionMs': (seconds * 1000).round()},
  );
  static Future<void> volume(double volume) =>
      _channel.invokeMethod<void>('volume', {'volume': volume});
  static Future<void> speed(double speed) =>
      _channel.invokeMethod<void>('speed', {'speed': speed});
  static Future<void> close() => _channel.invokeMethod<void>('close');

  static Future<CrunchyrollSnapshot> snapshot() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('snapshot');
    return CrunchyrollSnapshot(
      position: ((raw?['positionMs'] as num?) ?? 0).toDouble() / 1000,
      duration: ((raw?['durationMs'] as num?) ?? 0).toDouble() / 1000,
      playing: raw?['playing'] == true,
      ready: raw?['ready'] == true,
      ended: raw?['ended'] == true,
      buffering: raw?['buffering'] == true,
      error: raw?['error'] as String?,
    );
  }
}

class CrunchyrollSnapshot {
  const CrunchyrollSnapshot({
    required this.position,
    required this.duration,
    required this.playing,
    required this.ready,
    required this.ended,
    required this.buffering,
    this.error,
  });

  final double position;
  final double duration;
  final bool playing;
  final bool ready;
  final bool ended;
  final bool buffering;
  final String? error;
}

class CrunchyrollRoomSurface extends StatelessWidget {
  const CrunchyrollRoomSurface({super.key});

  @override
  Widget build(BuildContext context) =>
      const AndroidView(viewType: 'xynk.in/crunchyroll-player');
}
