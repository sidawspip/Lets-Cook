import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:lets_cook_mobile/models/models.dart';
import 'package:lets_cook_mobile/services/media_resolver.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: PlayerSmokeApp()));
}

class PlayerSmokeApp extends StatefulWidget {
  const PlayerSmokeApp({super.key});

  @override
  State<PlayerSmokeApp> createState() => _PlayerSmokeAppState();
}

class _PlayerSmokeAppState extends State<PlayerSmokeApp> {
  final SplitMediaResolver _resolver = SplitMediaResolver();
  final List<String> _results = [];
  VideoPlayerController? _player;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await _testYoutube();
    await _testDirectMp4();
    _record('SMOKE COMPLETE');
  }

  Future<void> _testYoutube() async {
    try {
      final media = await _resolver.resolve(
        const RoomWatchState(
          mediaId: 'aqz-KE-bpKQ',
          title: 'Big Buck Bunny',
          playing: true,
          positionSeconds: 0,
        ),
      );
      _record('YOUTUBE RESOLVED ${media.qualities.join(',')}');
      await _playFor('YOUTUBE', media.uri);
    } catch (error) {
      _record('YOUTUBE FAILED $error');
    }
  }

  Future<void> _testDirectMp4() async {
    try {
      final media = await _resolver.resolve(
        const RoomWatchState(
          provider: 'DIRECT_MP4',
          sourceType: 'DIRECT_MP4',
          sourceUrl:
              'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
          mediaId:
              'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
          title: 'Bee MP4',
          playing: true,
          positionSeconds: 0,
        ),
      );
      await _playFor('DIRECT_MP4', media.uri);
    } catch (error) {
      _record('DIRECT_MP4 FAILED $error');
    }
  }

  Future<void> _playFor(String label, Uri uri) async {
    final previous = _player;
    final player = VideoPlayerController.networkUrl(uri);
    _player = player;
    await previous?.dispose();
    await player.initialize();
    await player.play();
    if (mounted) setState(() {});
    await Future<void>.delayed(const Duration(seconds: 5));
    final position = player.value.position;
    if (!player.value.isInitialized || position <= Duration.zero) {
      throw StateError('$label did not advance');
    }
    _record('$label PLAYED ${position.inMilliseconds}ms');
    await player.pause();
  }

  void _record(String message) {
    debugPrint('PLAYER_SMOKE: $message');
    if (mounted) setState(() => _results.add(message));
  }

  @override
  void dispose() {
    _player?.dispose();
    _resolver.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Player smoke test')),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: player?.value.isInitialized == true
                ? player!.value.aspectRatio
                : 16 / 9,
            child: player?.value.isInitialized == true
                ? VideoPlayer(player!)
                : const Center(child: CircularProgressIndicator()),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: _results.map(Text.new).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
