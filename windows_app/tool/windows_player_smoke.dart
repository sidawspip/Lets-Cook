import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:video_player/video_player.dart';

import 'package:lets_cook_windows/models/models.dart';
import 'package:lets_cook_windows/services/media_resolver.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  fvp.registerWith(
    options: {
      'platforms': ['windows'],
    },
  );
  runApp(const MaterialApp(home: _SmokePlayer()));
}

class _SmokePlayer extends StatefulWidget {
  const _SmokePlayer();

  @override
  State<_SmokePlayer> createState() => _SmokePlayerState();
}

class _SmokePlayerState extends State<_SmokePlayer> {
  final _resolver = SplitMediaResolver();
  VideoPlayerController? _player;
  String _status = 'Resolving YouTube…';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      const directUrl = String.fromEnvironment('SMOKE_URL');
      final media = directUrl.isEmpty
          ? await _resolver.resolve(
              const RoomWatchState(
                provider: 'YOUTUBE',
                sourceType: 'YOUTUBE',
                mediaId: 'M7lc1UVf-VE',
                title: 'YouTube Windows smoke test',
                playing: true,
                positionSeconds: 0,
              ),
            )
          : ResolvedMedia(
              Uri.parse(directUrl),
              httpHeaders: directMediaHttpHeaders(Uri.parse(directUrl)),
            );
      final player = VideoPlayerController.networkUrl(
        media.uri,
        httpHeaders: media.httpHeaders,
      );
      await player.initialize();
      player.addListener(() {
        if (!mounted) return;
        final value = player.value;
        setState(() {
          _status = value.hasError
              ? value.errorDescription ?? 'Playback error'
              : 'Playing ${value.position.inSeconds}s / '
                    '${value.duration.inSeconds}s';
        });
      });
      await player.play();
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() => _player = player);
    } catch (error) {
      if (mounted) setState(() => _status = error.toString());
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    _resolver.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 800,
            height: 450,
            child: _player == null
                ? const Center(child: CircularProgressIndicator())
                : VideoPlayer(_player!),
          ),
          const SizedBox(height: 18),
          Text(_status, style: const TextStyle(color: Colors.white)),
        ],
      ),
    ),
  );
}
