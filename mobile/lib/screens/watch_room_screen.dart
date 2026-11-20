import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart'
    show VideoTrackRenderer, VideoViewFit;
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/models.dart';
import '../services/media_resolver.dart';
import '../services/crunchyroll_room_player.dart';
import '../services/room_voice_service.dart' show VoiceMember;
import '../state/watch_party_controller.dart';
import 'media_discovery_screen.dart';
import '../theme/app_theme.dart';
import '../services/device_features.dart';
import '../widgets/media_preview.dart';
import '../widgets/screen_share_confirmation.dart';
import '../widgets/wave_loader.dart';
import 'home_screen.dart';
import 'user_profile_screen.dart';

const _providerPageFallbackProviders = <String>{
  'WEB',
  'GOOGLE_DRIVE',
  'DROPBOX',
  'ONEDRIVE',
  'BOX',
  'NEXTCLOUD',
  'INTERNET_ARCHIVE',
  'X',
  'TWITCH',
  'VIMEO',
  'NETFLIX',
  'PRIME_VIDEO',
  'CRUNCHYROLL',
};

String _mediaTitle(RoomWatchState? state) {
  if (state == null) return 'Search YouTube to begin';
  final storedTitle = state.title.trim();
  final separator = storedTitle.lastIndexOf(' · ');
  final title = separator > 0
      ? storedTitle.substring(0, separator).trim()
      : storedTitle;
  if (title.isEmpty ||
      title.toLowerCase() == 'synced for everyone in the room') {
    return state.provider == 'YOUTUBE' ? 'YouTube video' : 'Video';
  }
  return title;
}

String _sourceLabel(RoomWatchState? state) {
  if (state == null) return 'Search YouTube to begin';
  final provider = state.provider.trim().toUpperCase();
  if (provider != 'WEB') return _providerName(provider);
  final storedTitle = state.title.trim();
  final separator = storedTitle.lastIndexOf(' · ');
  if (separator > 0 && separator + 3 < storedTitle.length) {
    return storedTitle.substring(separator + 3).trim();
  }
  final host = Uri.tryParse(state.sourceUrl ?? '')?.host.toLowerCase() ?? '';
  return host.startsWith('www.')
      ? host.substring(4)
      : (host.isEmpty ? 'Web video' : host);
}

String _providerName(String value) {
  final provider = value.trim().toUpperCase();
  return switch (provider) {
    'YOUTUBE' => 'YouTube',
    'VIMEO' => 'Vimeo',
    'TWITCH' => 'Twitch',
    'X' => 'X',
    'GOOGLE_DRIVE' || 'DRIVE' => 'Google Drive',
    'DROPBOX' => 'Dropbox',
    'ONEDRIVE' => 'OneDrive',
    'BOX' => 'Box',
    'NEXTCLOUD' => 'Nextcloud',
    'INTERNET_ARCHIVE' => 'Internet Archive',
    'CRUNCHYROLL' => 'Crunchyroll',
    'NETFLIX' => 'Netflix',
    'PRIME_VIDEO' => 'Prime Video',
    'DIRECT_MP4' || 'DIRECT_HLS' || 'WEB' => 'Web',
    _ =>
      provider
          .toLowerCase()
          .split('_')
          .map(
            (word) => word.isEmpty
                ? word
                : '${word[0].toUpperCase()}${word.substring(1)}',
          )
          .join(' '),
  };
}

class WatchRoomScreen extends StatefulWidget {
  const WatchRoomScreen({super.key, required this.controller});

  final WatchPartyController controller;

  @override
  State<WatchRoomScreen> createState() => _WatchRoomScreenState();
}

class _WatchRoomScreenState extends State<WatchRoomScreen>
    with WidgetsBindingObserver {
  final MediaResolver _resolver = SplitMediaResolver();
  VideoPlayerController? _player;
  WebViewController? _providerBrowser;
  bool _nativeCrunchyroll = false;
  String? _providerBrowserMediaKey;
  Timer? _telemetry;
  Timer? _controlsTimer;
  String? _loadedMediaKey;
  String? _durationReportedMediaKey;
  double _position = 0;
  double _duration = 0;
  bool _sampling = false;
  bool _controlsVisible = true;
  bool _loading = false;
  bool _playbackReady = false;
  String? _playerError;
  String? _resolvedTitle;
  bool _wakeLockEnabled = false;
  bool? _nativeAutoPipEnabled;
  bool _inPip = false;
  bool _peopleDrawerOpen = false;
  bool _showCurrentInQueue = true;
  List<String> _qualities = const [];
  Map<String, String> _captionLanguages = const {};
  List<CaptionCue> _captionCues = const [];
  String _captionText = '';
  String? _endedMediaKey;
  DateTime _lastProgressAt = DateTime.now();
  DateTime _lastHardSyncAt = DateTime.fromMillisecondsSinceEpoch(0);
  double _lastObservedPosition = -1;
  bool _stallReported = false;
  int _stallRecoveryAttempts = 0;
  bool _recoveringStall = false;
  final _playerRevision = ValueNotifier<int>(0);
  final _videoSurfaceKey = GlobalKey(debugLabel: 'room-video-surface');
  Offset? _videoGestureStart;
  Offset _videoGestureDelta = Offset.zero;
  bool _viewerLoginConfirmed = false;
  final Set<String> _seenShareRequests = {};
  bool _shareDialogOpen = false;

  void _checkShareRequests() {
    unawaited(_restoreLocalAudio());
    if (widget.controller.screenShareApproved && mounted) {
      widget.controller.screenShareApproved = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Host approved screen sharing. Tap Share screen to start.',
              ),
            ),
          );
      });
    }
    if (widget.controller.unmuteRequested && mounted) {
      widget.controller.unmuteRequested = false;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final accept = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('The host asked you to unmute'),
            content: const Text(
              'Your microphone will turn on only if you accept.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep muted'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Turn on microphone'),
              ),
            ],
          ),
        );
        if (accept == true &&
            widget.controller.activeRoom != null &&
            !widget.controller.voice.microphoneEnabled)
          await widget.controller.voice.toggleMicrophone(
            widget.controller.activeRoom!.id,
          );
      });
    }
    final room = widget.controller.activeRoom;
    final me = widget.controller.activeParticipants
        .where(
          (person) =>
              person['userId']?.toString() == widget.controller.profile?.id,
        )
        .firstOrNull;
    if (room?.role != 'HOST' &&
        widget.controller.voice.screenShareEnabled &&
        me?['canShareScreen'] != true &&
        room != null)
      unawaited(widget.controller.voice.toggleScreenShare(room.id));
    if (!mounted || room?.role != 'HOST' || _shareDialogOpen) return;
    final pending = widget.controller.activeParticipants
        .where(
          (person) =>
              person['screenShareRequested'] == true &&
              !_seenShareRequests.contains(person['userId']?.toString()),
        )
        .firstOrNull;
    if (pending == null) return;
    final userId = pending['userId']?.toString();
    if (userId == null) return;
    _seenShareRequests.add(userId);
    _shareDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final allow = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Screen share request'),
          content: Text(
            '${pending['displayName'] ?? 'A member'} wants to share a screen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Decline'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Allow'),
            ),
          ],
        ),
      );
      _shareDialogOpen = false;
      if (allow != null)
        await widget.controller.api.setScreenPermission(
          room!.id,
          userId,
          allow,
        );
    });
  }

  bool _canFallbackToProviderBrowser(RoomWatchState state) =>
      _providerPageFallbackProviders.contains(state.provider.toUpperCase()) &&
      !(CrunchyrollRoomPlayer.supported &&
          state.provider.toUpperCase() == 'CRUNCHYROLL');

  bool _usesProviderBrowser(RoomWatchState? state) =>
      state != null &&
      _providerBrowser != null &&
      _providerBrowserMediaKey ==
          '${state.provider}:${state.mediaId}:${state.sourceUrl ?? ''}';

  bool get _videoAccessReady =>
      widget.controller.canControlWatch ||
      (widget.controller.canViewVideo &&
          (!const {'NETFLIX', 'PRIME_VIDEO', 'CRUNCHYROLL'}.contains(
                widget.controller.watchState?.provider.toUpperCase(),
              ) ||
              _viewerLoginConfirmed));

  Future<({ResolvedMedia media, VideoPlayerController player})>
  _initializeResolvedMedia(RoomWatchState state) async {
    var media = await _resolver.resolve(
      state,
      quality: widget.controller.selectedQuality,
    );
    final sourcePage = Uri.tryParse(state.mediaId);
    final refreshedSources = resolvedMediaSourcesFromResponse(
      widget.controller.resolvedWebSourcesFor(state.mediaId),
      sourcePage: sourcePage,
    );
    if (refreshedSources.isNotEmpty) {
      media = media.withFallbackSources(refreshedSources);
    }
    Object? lastError;
    for (final source in media.orderedSources) {
      final player = VideoPlayerController.networkUrl(
        source.uri,
        httpHeaders: source.httpHeaders,
        viewType: defaultTargetPlatform == TargetPlatform.android
            ? VideoViewType.platformView
            : VideoViewType.textureView,
        videoPlayerOptions: VideoPlayerOptions(
          allowBackgroundPlayback: true,
          mixWithOthers: !widget.controller.muteOtherAudio,
        ),
      );
      try {
        await player.initialize();
        return (media: media, player: player);
      } catch (error) {
        lastError = error;
        await player.dispose();
      }
    }
    if (lastError != null) throw lastError;
    throw StateError('The provider did not return a playable video source.');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DeviceFeatures.onPipModeChanged(_handlePipModeChanged);
    _syncAutoPip();
    widget.controller.addListener(_checkShareRequests);
    _ensureVideo();
    _telemetry = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _samplePlayer(),
    );
  }

  @override
  void didUpdateWidget(covariant WatchRoomScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureVideo();
  }

  Future<void> _ensureVideo() async {
    if (!_videoAccessReady) return;
    var state = widget.controller.watchState;
    final key = state == null
        ? null
        : '${state.provider}:${state.mediaId}:${state.sourceUrl ?? ''}';
    if (state == null || key == _loadedMediaKey || _loading) return;
    _providerBrowser = null;
    _providerBrowserMediaKey = null;
    if (_nativeCrunchyroll) {
      _nativeCrunchyroll = false;
      unawaited(CrunchyrollRoomPlayer.close());
    }
    _loadedMediaKey = key;
    _showCurrentInQueue = true;
    _resolvedTitle = null;
    _position = state.positionSeconds;
    setState(() {
      _loading = true;
      _playbackReady = false;
      _playerError = null;
    });
    VideoPlayerController? candidate;
    try {
      if (state.provider.toUpperCase() == 'CRUNCHYROLL' &&
          CrunchyrollRoomPlayer.supported) {
        await _openCrunchyroll(state);
        return;
      }
      final pageUri = Uri.tryParse(state.mediaId);
      final streamUri = Uri.tryParse(state.sourceUrl ?? '');
      final pagePath = pageUri?.path.toLowerCase() ?? '';
      final pageIsDirectMedia =
          pagePath.endsWith('.mp4') || pagePath.endsWith('.m3u8');
      final isDirectWeb =
          state.provider.toUpperCase().startsWith('DIRECT_') &&
          pageUri?.scheme == 'https' &&
          pageUri?.host.isNotEmpty == true;
      final streamIsOnlyPageIdentity =
          streamUri?.scheme != 'https' || state.sourceUrl == state.mediaId;
      final needsInitialWebResolve =
          isDirectWeb && streamIsOnlyPageIdentity && !pageIsDirectMedia;
      final hasRefreshableStream =
          isDirectWeb &&
          streamUri?.scheme == 'https' &&
          state.mediaId != state.sourceUrl;
      if (needsInitialWebResolve) {
        final refreshed = await widget.controller.refreshExpiredWebMedia();
        if (!refreshed) {
          throw StateError(
            'This Web page did not resolve to a playable video. Open the video page in Web and try again.',
          );
        }
        state = widget.controller.watchState ?? state;
        _loadedMediaKey =
            '${state.provider}:${state.mediaId}:${state.sourceUrl ?? ''}';
      }
      late ({ResolvedMedia media, VideoPlayerController player}) opened;
      try {
        opened = await _initializeResolvedMedia(state);
      } catch (_) {
        // Try the normalized source list before asking the stable page for a
        // fresh signed URL. This avoids consuming the stream with a separate
        // probe before the real player receives its first connection.
        if (!hasRefreshableStream ||
            !await widget.controller.refreshExpiredWebMedia()) {
          rethrow;
        }
        state = widget.controller.watchState ?? state;
        _loadedMediaKey =
            '${state.provider}:${state.mediaId}:${state.sourceUrl ?? ''}';
        opened = await _initializeResolvedMedia(state);
      }
      final media = opened.media;
      candidate = opened.player;
      _qualities = media.qualities;
      _resolvedTitle = media.title;
      widget.controller.rememberResolvedMediaTitle(state.mediaId, media.title);
      _captionLanguages = media.captionLanguages;
      if (widget.controller.selectedCaption != 'off' &&
          !_captionLanguages.containsKey(widget.controller.selectedCaption)) {
        widget.controller.setCaption('off');
        _captionCues = const [];
        _captionText = '';
      }
      // Release the old HTTP connection before opening a replacement. Some
      // signed web streams allow only a few concurrent connections and the
      // previous create-before-dispose order could exhaust that allowance.
      final previous = _player;
      _player = null;
      await previous?.dispose();
      final mediaDurationSeconds =
          candidate.value.duration.inMilliseconds /
          Duration.millisecondsPerSecond;
      final requestedPosition = state.positionSeconds;
      final startPosition = mediaDurationSeconds > 0
          ? requestedPosition.clamp(0.0, mediaDurationSeconds)
          : requestedPosition.clamp(0.0, double.infinity);
      await candidate.seekTo(
        Duration(milliseconds: (startPosition * 1000).round()),
      );
      _position = startPosition;
      if (startPosition != requestedPosition) {
        widget.controller.updatePlayerPosition(startPosition);
        if (widget.controller.canControlWatch) {
          unawaited(widget.controller.seek(startPosition));
        }
      }
      await candidate.setPlaybackSpeed(state.playbackRate);
      await _player?.dispose();
      _player = candidate;
      candidate = null;
      _lastObservedPosition = startPosition;
      _lastProgressAt = DateTime.now();
      _stallReported = false;
      await _restoreLocalAudio();
      if (state.playing &&
          (mediaDurationSeconds <= 0 ||
              startPosition < mediaDurationSeconds - .5)) {
        await _player!.play().timeout(
          const Duration(seconds: 10),
          onTimeout: () => debugPrint('Player start is still buffering'),
        );
      } else {
        _playbackReady = true;
      }
      _syncAutoPip();
      await _syncWakeLock();
    } catch (error) {
      await candidate?.dispose();
      if (_canFallbackToProviderBrowser(state!)) {
        await _ensureProviderBrowser(state, key!);
        return;
      }
      // Keep the failed key marked as loaded. Controller updates rebuild this
      // widget frequently; clearing it here caused an unbounded automatic
      // initialize/error loop. Retry clears the key for one explicit attempt.
      _playerError = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCrunchyroll(RoomWatchState state) async {
    final id = CrunchyrollRoomPlayer.videoId(state.mediaId);
    if (id == null) throw StateError('Select a Crunchyroll episode first.');
    final old = _player;
    _player = null;
    await old?.dispose();
    _nativeCrunchyroll = true;
    if (mounted) setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    await CrunchyrollRoomPlayer.open(id);
    await CrunchyrollRoomPlayer.seek(state.positionSeconds);
    await CrunchyrollRoomPlayer.speed(state.playbackRate);
    await _restoreLocalAudio();
    if (state.playing) await CrunchyrollRoomPlayer.play();
    _resolvedTitle = _mediaTitle(state);
    _playbackReady = true;
  }

  Future<void> _ensureProviderBrowser(RoomWatchState state, String key) async {
    final page = Uri.tryParse(state.sourceUrl ?? state.mediaId);
    if (page == null || page.scheme != 'https' || page.host.isEmpty) {
      setState(() {
        _loadedMediaKey = key;
        _playerError = 'This provider did not supply a valid HTTPS video page.';
      });
      return;
    }
    final previous = _player;
    _player = null;
    await previous?.dispose();
    _loadedMediaKey = key;
    _providerBrowserMediaKey = key;
    _position = state.positionSeconds;
    setState(() {
      _loading = true;
      _playerError = null;
    });
    late final WebViewController controller;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            if (!mounted || _providerBrowser != controller) return;
            setState(() => _loading = false);
            await _synchronizeProviderBrowser(state);
          },
          onWebResourceError: (error) {
            if (!mounted ||
                _providerBrowser != controller ||
                error.isForMainFrame != true) {
              return;
            }
            setState(() {
              _loading = false;
              _playerError =
                  'The provider blocked its in-app page. Sign in again or use Screen sharing.';
            });
          },
        ),
      );
    _providerBrowser = controller;
    await controller.loadRequest(page);
    if (mounted) setState(() {});
  }

  Future<Map<String, dynamic>?> _providerVideoSnapshot(
    RoomWatchState desired,
  ) async {
    final controller = _providerBrowser;
    if (controller == null) return null;
    final playing = desired.playing ? 'true' : 'false';
    final target = widget.controller.synchronizedPosition;
    final rate = desired.playbackRate.clamp(.25, 2.0);
    try {
      final raw = await controller.runJavaScriptReturningResult('''
        (() => {
          const videos = Array.from(document.querySelectorAll('video'));
          const video = videos.find(v => v.offsetWidth >= 160 && v.offsetHeight >= 90) || videos[0];
          if (!video) return JSON.stringify({found:false});
          const target = $target;
          if (Number.isFinite(target) && Math.abs((video.currentTime || 0) - target) > 2) {
            try { video.currentTime = Math.max(0, target); } catch (_) {}
          }
          try { video.playbackRate = $rate; } catch (_) {}
          if ($playing) {
            if (video.paused) video.play().catch(() => {});
          } else if (!video.paused) {
            video.pause();
          }
          return JSON.stringify({
            found:true,
            position:Number(video.currentTime || 0),
            duration:Number.isFinite(video.duration) ? Number(video.duration) : 0,
            paused:Boolean(video.paused)
          });
        })();
      ''');
      var encoded = raw.toString();
      if (encoded.startsWith('"')) encoded = jsonDecode(encoded) as String;
      return jsonDecode(encoded) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _synchronizeProviderBrowser(RoomWatchState desired) async {
    final snapshot = await _providerVideoSnapshot(desired);
    if (!mounted || snapshot == null) return;
    if (snapshot['found'] != true) {
      setState(() {
        _playerError =
            'Open and start the video on this provider page. Xynk will synchronize it when the player appears.';
      });
      return;
    }
    setState(() {
      _playerError = null;
      _position = (snapshot['position'] as num?)?.toDouble() ?? _position;
      _duration = (snapshot['duration'] as num?)?.toDouble() ?? _duration;
    });
  }

  Future<void> _restoreLocalAudio() async {
    if (_nativeCrunchyroll) {
      final speaking = widget.controller.voice.members.any(
        (member) =>
            member.speaking &&
            member.identity != widget.controller.voice.localIdentity,
      );
      await CrunchyrollRoomPlayer.volume(
        widget.controller.muted
            ? 0
            : widget.controller.volume * (speaking ? .65 : 1),
      );
      return;
    }
    final player = _player;
    if (player == null) return;
    final speaking = widget.controller.voice.members.any(
      (member) =>
          member.speaking &&
          member.identity != widget.controller.voice.localIdentity,
    );
    await player.setVolume(
      widget.controller.muted
          ? 0
          : widget.controller.volume * (speaking ? .65 : 1),
    );
  }

  Future<void> _samplePlayer() async {
    final desired = widget.controller.watchState;
    if (_nativeCrunchyroll && desired != null) {
      if (_sampling) return;
      _sampling = true;
      try {
        final snap = await CrunchyrollRoomPlayer.snapshot();
        if (!mounted) return;
        setState(() {
          _position = snap.position;
          _duration = snap.duration > 0 ? snap.duration : 0;
          _playbackReady = snap.ready;
          _playerError = snap.error;
        });
        if (snap.error != null) return;
        if (snap.ready &&
            snap.duration > 0 &&
            widget.controller.canControlWatch &&
            desired.durationSeconds == null &&
            _durationReportedMediaKey != _loadedMediaKey) {
          _durationReportedMediaKey = _loadedMediaKey;
          unawaited(
            widget.controller.reportMediaDuration(
              desired.mediaId,
              snap.duration,
            ),
          );
        }
        if (snap.ready) {
          final target = widget.controller.synchronizedPosition;
          if ((snap.position - target).abs() > 5) {
            await CrunchyrollRoomPlayer.seek(target);
          }
          if (desired.playing && !snap.playing)
            await CrunchyrollRoomPlayer.play();
          if (!desired.playing && snap.playing)
            await CrunchyrollRoomPlayer.pause();
          if (snap.ended &&
              _endedMediaKey != _loadedMediaKey &&
              widget.controller.canControlWatch) {
            _endedMediaKey = _loadedMediaKey;
            final advanced = await widget.controller.playHighestVoted();
            if (!advanced) await widget.controller.stopPlayback();
          }
        }
      } catch (error) {
        if (mounted) setState(() => _playerError = error.toString());
      } finally {
        _sampling = false;
      }
      return;
    }
    if (_usesProviderBrowser(desired)) {
      if (desired != null && !_sampling) {
        _sampling = true;
        try {
          await _synchronizeProviderBrowser(desired);
        } finally {
          _sampling = false;
        }
      }
      return;
    }
    final player = _player;
    if (player == null || desired == null || _sampling) return;
    _sampling = true;
    try {
      if (player.value.hasError) {
        final description = player.value.errorDescription;
        if (mounted && _playerError == null) {
          setState(() {
            _playerError = description?.isNotEmpty == true
                ? description
                : 'The video decoder stopped. Tap Retry video.';
          });
        }
        return;
      }
      final current = player.value.position.inMilliseconds / 1000;
      final duration = player.value.duration.inMilliseconds / 1000;
      if (duration > 0 &&
          widget.controller.canControlWatch &&
          desired.durationSeconds == null &&
          _durationReportedMediaKey != _loadedMediaKey) {
        _durationReportedMediaKey = _loadedMediaKey;
        unawaited(
          widget.controller
              .reportMediaDuration(desired.mediaId, duration)
              .catchError((Object error) {
                _durationReportedMediaKey = null;
                debugPrint('Duration sync failed: $error');
              }),
        );
      }
      final now = DateTime.now();
      if ((current - _lastObservedPosition).abs() >= .15) {
        _lastObservedPosition = current;
        _lastProgressAt = now;
        _playbackReady = true;
        _stallRecoveryAttempts = 0;
        _stallReported = false;
      }
      if (mounted) {
        setState(() {
          _position = current;
          _duration = duration > 0 ? duration : 0;
          _captionText = _captionAt(player.value.position);
        });
        _playerRevision.value++;
      }
      final rawTarget = widget.controller.synchronizedPosition;
      final target = duration > 0
          ? rawTarget.clamp(0.0, duration)
          : rawTarget.clamp(0.0, double.infinity);
      final drift = (current - target).abs();
      if (!desired.playing && player.value.isPlaying) await player.pause();
      if (drift > 5 &&
          _playbackReady &&
          (drift > 15 ||
              now.difference(_lastHardSyncAt) >= const Duration(seconds: 10)) &&
          !player.value.isBuffering &&
          !player.value.isCompleted &&
          (duration <= 0 || target < duration - .5)) {
        await player.seekTo(Duration(milliseconds: (target * 1000).round()));
        _lastHardSyncAt = now;
        _lastProgressAt = now;
      }
      if (desired.playing &&
          !player.value.isPlaying &&
          !player.value.isCompleted &&
          (duration <= 0 || target < duration - .5)) {
        await player.play();
      }
      _syncAutoPip();
      await _syncWakeLock();
      if (player.value.duration > Duration.zero &&
          (player.value.isCompleted ||
              player.value.position >= player.value.duration)) {
        if (_endedMediaKey != _loadedMediaKey) {
          _endedMediaKey = _loadedMediaKey;
          await player.pause();
          final advanced = await widget.controller.playHighestVoted();
          if (!advanced) await widget.controller.stopPlayback();
          if (mounted) {
            setState(() => _showCurrentInQueue = advanced);
          }
          // playHighestVoted refreshes the queue and removes the selected item.
          // Open it after that refresh so the completed item never flashes in
          // the list and the next synchronized player is shown immediately.
          widget.controller.openPostPlaybackShelf();
        }
      } else if (desired.playing &&
          !_recoveringStall &&
          !_stallReported &&
          now.difference(_lastProgressAt) >=
              (player.value.isBuffering
                  ? const Duration(seconds: 25)
                  : const Duration(seconds: 15))) {
        _stallReported = true;
        if (_stallRecoveryAttempts < 2) {
          _stallRecoveryAttempts++;
          _recoveringStall = true;
          unawaited(_retryVideo().whenComplete(() => _recoveringStall = false));
        } else if (mounted) {
          setState(() {
            _playerError =
                'The stream stopped advancing. Tap Retry video to reconnect.';
          });
        }
      }
    } catch (_) {
      // A slow player must not accumulate pending telemetry requests.
    } finally {
      _sampling = false;
    }
  }

  Future<void> _retryVideo() async {
    if (_loading) return;
    await widget.controller.refreshExpiredWebMedia();
    final failed = _player;
    _player = null;
    _providerBrowser = null;
    if (_nativeCrunchyroll) {
      _nativeCrunchyroll = false;
      await CrunchyrollRoomPlayer.close();
    }
    _providerBrowserMediaKey = null;
    _loadedMediaKey = null;
    _playerError = null;
    _stallReported = false;
    _lastProgressAt = DateTime.now();
    if (mounted) {
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
    }
    await failed?.dispose();
    if (mounted) await _ensureVideo();
  }

  Future<void> _lockPlayer() async {
    if (_nativeCrunchyroll) {
      _nativeCrunchyroll = false;
      await CrunchyrollRoomPlayer.close();
    }
    final player = _player;
    if (player == null && _providerBrowser == null && _loadedMediaKey == null) {
      return;
    }
    _player = null;
    _providerBrowser = null;
    _providerBrowserMediaKey = null;
    _loadedMediaKey = null;
    _position = 0;
    _duration = 0;
    await player?.pause();
    await player?.dispose();
    await _syncWakeLock();
    if (mounted) setState(() {});
  }

  Future<void> _openViewerLogin() async {
    final state = widget.controller.watchState;
    final signedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MediaDiscoveryScreen(
          controller: widget.controller,
          targetRoomId: widget.controller.activeRoom?.id,
          initialProvider: state?.provider ?? _sourceLabel(state),
          initialMediaId: state?.mediaId,
          initialSourceUrl: state?.sourceUrl,
          initialQuery: _mediaTitle(state),
          viewerLoginMode: true,
        ),
      ),
    );
    if (!mounted || signedIn != true || !widget.controller.canViewVideo) {
      return;
    }
    setState(() => _viewerLoginConfirmed = true);
    await _ensureVideo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_checkShareRequests);
    DeviceFeatures.onPipModeChanged(null);
    _nativeAutoPipEnabled = false;
    unawaited(DeviceFeatures.setPipAutoEnabled(false));
    _telemetry?.cancel();
    _controlsTimer?.cancel();
    _player?.dispose();
    if (_nativeCrunchyroll) unawaited(CrunchyrollRoomPlayer.close());
    _resolver.close();
    _playerRevision.dispose();
    if (_wakeLockEnabled) unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android reports inactive/paused for ordinary task minimization too.
    // Only the native pipWillEnter/pipModeChanged callbacks may switch the
    // room into its video-only layout; guessing here made a restored room
    // briefly occupy the whole screen and hide chat.
    if (state == AppLifecycleState.resumed) unawaited(_restoreAfterResume());
  }

  Future<void> _restoreAfterResume() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final inPip = await DeviceFeatures.isInPip();
    if (!mounted) return;
    if (_inPip != inPip) setState(() => _inPip = inPip);
    if (inPip) return;

    final desired = widget.controller.watchState;
    if (desired == null) return;
    if (_nativeCrunchyroll) {
      await _samplePlayer();
      return;
    }
    if (_usesProviderBrowser(desired)) {
      await _synchronizeProviderBrowser(desired);
      return;
    }
    final player = _player;
    if (player?.value.isInitialized != true) {
      _loadedMediaKey = null;
      await _ensureVideo();
      return;
    }
    final target = widget.controller.synchronizedPosition;
    final local = player!.value.position.inMilliseconds / 1000;
    if ((local - target).abs() > 1.5) {
      await player.seekTo(Duration(milliseconds: (target * 1000).round()));
    }
    await player.setPlaybackSpeed(desired.playbackRate);
    if (desired.playing && !player.value.isPlaying) {
      await player.play();
    } else if (!desired.playing && player.value.isPlaying) {
      await player.pause();
    }
    await _restoreLocalAudio();
    await _syncWakeLock();
  }

  Future<void> _handlePipModeChanged(bool inPip) async {
    if (!mounted || _inPip == inPip) return;
    setState(() => _inPip = inPip);
    if (inPip) {
      await WidgetsBinding.instance.endOfFrame;
      // Android captures the last submitted surface for PiP. Give the raster
      // thread one beat to commit the video-only frame before shrinking it.
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
  }

  Future<void> _enterVideoPip() async {
    // Explicit PiP is useful for both playing and paused video. Requiring the
    // room event to have propagated first made this button look unresponsive.
    if (_usesProviderBrowser(widget.controller.watchState)) return;
    if (_player?.value.isInitialized != true && !_nativeCrunchyroll) return;
    await _handlePipModeChanged(true);
    final entered = await DeviceFeatures.enterPip();
    if (!entered) await _handlePipModeChanged(false);
  }

  Future<void> _syncWakeLock() async {
    final shouldEnable =
        widget.controller.watchState?.playing == true &&
        (_player?.value.isInitialized == true || _nativeCrunchyroll);
    if (shouldEnable == _wakeLockEnabled) return;
    _wakeLockEnabled = shouldEnable;
    await WakelockPlus.toggle(enable: shouldEnable);
  }

  void _syncAutoPip() {
    final enabled = widget.controller.floatingVideo && _videoIsPlaying;
    if (_nativeAutoPipEnabled == enabled) return;
    _nativeAutoPipEnabled = enabled;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _nativeAutoPipEnabled != enabled) return;
      try {
        await DeviceFeatures.setPipAutoEnabled(enabled);
      } catch (error) {
        debugPrint('Could not synchronize automatic PiP: $error');
      }
    });
  }

  bool get _videoIsPlaying =>
      widget.controller.watchState?.playing == true ||
      _player?.value.isPlaying == true;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      widget.controller,
      widget.controller.voice,
      _playerRevision,
    ]),
    builder: (context, _) {
      if (!_videoAccessReady && _player != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _lockPlayer());
      }
      final state = widget.controller.watchState;
      final key = state == null
          ? null
          : '${state.provider}:${state.mediaId}:${state.sourceUrl ?? ''}';
      if (_videoAccessReady &&
          key != null &&
          key != _loadedMediaKey &&
          !_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVideo());
      }
      _syncAutoPip();
      final screenTrack = widget.controller.voice.screenTrack;
      final player = screenTrack != null
          ? VideoTrackRenderer(
              screenTrack,
              key: ObjectKey(screenTrack),
              fit: VideoViewFit.contain,
            )
          : _player?.value.isInitialized == true
          ? VideoPlayer(_player!, key: _videoSurfaceKey)
          : _nativeCrunchyroll
          ? const CrunchyrollRoomSurface()
          : _providerBrowser != null && _usesProviderBrowser(state)
          ? WebViewWidget(controller: _providerBrowser!)
          : null;
      if (_inPip) {
        return ColoredBox(
          color: Colors.black,
          child: SizedBox.expand(
            child: player ?? const Center(child: CircularProgressIndicator()),
          ),
        );
      }
      return _buildScaffold(player);
    },
  );

  Widget _buildScaffold(Widget? player) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _handleBack();
    },
    child: Scaffold(
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final drawerWidth = math.min(380.0, constraints.maxWidth * .86);
          final roomShift = math.min(112.0, drawerWidth * .32);
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: _peopleDrawerOpen ? -roomShift : 0,
                right: _peopleDrawerOpen ? roomShift : 0,
                top: 0,
                bottom: 0,
                child: _roomSurface(player),
              ),
              if (_peopleDrawerOpen)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  right: drawerWidth,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _peopleDrawerOpen = false),
                    child: const ColoredBox(color: Color(0x55000000)),
                  ),
                ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                top: 0,
                bottom: 0,
                right: _peopleDrawerOpen ? 0 : -drawerWidth,
                width: drawerWidth,
                child: Material(
                  color: const Color(0xFA10121A),
                  elevation: 24,
                  child: SafeArea(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Room people',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Close participants',
                                onPressed: () =>
                                    setState(() => _peopleDrawerOpen = false),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _PeoplePanel(controller: widget.controller),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _roomSurface(Widget? player) => Stack(
    children: [
      Positioned.fill(
        child: _AmbientBackdrop(
          imageUrl: widget.controller.currentThumbnail,
          // Android's native platform-view video surface must have exactly one
          // place in the tree. Reusing it here and in the foreground could
          // promote the surface above the room layout after resize/resume.
          // The ambient layer therefore uses the synchronized thumbnail.
          video: null,
        ),
      ),
      Positioned.fill(
        child: SafeArea(
          child: Column(
            children: [
              _RoomHeader(
                controller: widget.controller,
                onAddSource: _openRoomSources,
                onSettings: _openRoomControls,
                onPeople: () => setState(() => _peopleDrawerOpen = true),
              ),
              Expanded(
                child: widget.controller.checkingVideoAccess
                    ? const Center(child: WaveLoader(label: 'Joining room'))
                    : !_videoAccessReady
                    ? _VideoAccessGate(
                        controller: widget.controller,
                        providerLabel: _sourceLabel(
                          widget.controller.watchState,
                        ),
                        onSignIn: _openViewerLogin,
                      )
                    : _WatchMode(
                        controller: widget.controller,
                        resolvedTitle: _resolvedTitle,
                        showLoading:
                            (_loading && !_playbackReady) ||
                            (_player != null &&
                                (!_playbackReady &&
                                        widget.controller.watchState?.playing ==
                                            true ||
                                    (_player!.value.isBuffering &&
                                        widget.controller.watchState?.playing ==
                                            true &&
                                        DateTime.now().difference(
                                              _lastProgressAt,
                                            ) >=
                                            const Duration(seconds: 3)))),
                        playerAspectRatio: _player?.value.isInitialized == true
                            ? _player!.value.aspectRatio
                            : 16 / 9,
                        isScreenShare:
                            widget.controller.voice.screenTrack != null,
                        isLocalScreenShare:
                            widget.controller.voice.screenShareEnabled,
                        showPicker: widget.controller.shelfOpen,
                        onToggleControls: _toggleControls,
                        player: widget.controller.shelfOpen
                            ? _InlineQueuePicker(
                                controller: widget.controller,
                                livePlayer: player,
                                playerAspectRatio:
                                    _player?.value.isInitialized == true
                                    ? _player!.value.aspectRatio
                                    : 16 / 9,
                                showCurrent: _showCurrentInQueue,
                              )
                            : Stack(
                                fit: StackFit.expand,
                                children: [
                                  player ?? const SizedBox.expand(),
                                  Positioned.fill(
                                    child: GestureDetector(
                                      onTap: _toggleControls,
                                      onPanStart: (details) {
                                        _videoGestureStart =
                                            details.localPosition;
                                        _videoGestureDelta = Offset.zero;
                                      },
                                      onPanUpdate: (details) {
                                        _videoGestureDelta += details.delta;
                                      },
                                      onPanEnd: (_) => _finishVideoGesture(),
                                      behavior: HitTestBehavior.opaque,
                                      child: const ColoredBox(
                                        color: Colors.transparent,
                                      ),
                                    ),
                                  ),
                                  if (_playerError != null)
                                    Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.error_outline,
                                              size: 40,
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              _playerError!,
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 12),
                                            FilledButton.icon(
                                              onPressed: _retryVideo,
                                              icon: const Icon(Icons.refresh),
                                              label: const Text('Retry video'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (_captionText.isNotEmpty)
                                    Align(
                                      alignment: Alignment.bottomCenter,
                                      child: Padding(
                                        padding: const EdgeInsets.all(18),
                                        child: DecoratedBox(
                                          decoration: const BoxDecoration(
                                            color: Color(0xCC000000),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            child: Text(
                                              _captionText,
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                        showControls:
                            !widget.controller.shelfOpen && _controlsVisible,
                        position: _position,
                        duration: _duration,
                        onPlayPause: _togglePlayback,
                        onSeek: _seek,
                        onMute: _toggleMute,
                        onSettings: _showSettings,
                        onPip: _enterVideoPip,
                        onFullscreen: _openFullscreen,
                      ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Future<void> _handleBack() async {
    if (_peopleDrawerOpen) {
      setState(() => _peopleDrawerOpen = false);
    } else if (widget.controller.shelfOpen) {
      widget.controller.setShelfOpen(false);
    } else if (widget.controller.panel != RoomPanel.chat) {
      widget.controller.setPanel(RoomPanel.chat);
    } else {
      await widget.controller.leaveRoom();
    }
  }

  Future<void> _openRoomSources() async {
    final roomId = widget.controller.activeRoom?.id;
    if (roomId == null) return;
    widget.controller.takeLastRoomSelection();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MediaDiscoveryScreen(
          controller: widget.controller,
          targetRoomId: roomId,
        ),
      ),
    );
    // Playback is the confirmation. The server publishes one video timeline
    // card only when this item actually starts; queued items stay queue-only.
    widget.controller.takeLastRoomSelection();
  }

  Future<void> _openRoomControls() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RoomControlsSheet(controller: widget.controller),
  );

  void _showControls() {
    _controlsTimer?.cancel();
    if (mounted) setState(() => _controlsVisible = true);
    if (widget.controller.watchState?.playing == true) {
      _controlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _controlsVisible = false);
      });
    }
  }

  void _toggleControls() {
    _controlsTimer?.cancel();
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible && widget.controller.watchState?.playing == true) {
      _controlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _controlsVisible = false);
      });
    }
  }

  void _finishVideoGesture() {
    final start = _videoGestureStart;
    final delta = _videoGestureDelta;
    _videoGestureStart = null;
    _videoGestureDelta = Offset.zero;
    if (start == null) return;
    // A deliberate ↖ gesture must travel meaningfully in both axes. This
    // avoids opening the queue during ordinary seeks or vertical scrolling.
    if (delta.dx < -70 && delta.dy < -70 && (delta.dx - delta.dy).abs() < 150) {
      _controlsTimer?.cancel();
      setState(() => _controlsVisible = false);
      widget.controller.setShelfOpen(true);
      HapticFeedback.selectionClick();
    }
  }

  Future<void> _togglePlayback() async {
    final state = widget.controller.watchState;
    if (state == null) return;
    if (_usesProviderBrowser(state)) {
      await widget.controller.togglePlayback(_position);
      await _synchronizeProviderBrowser(widget.controller.watchState ?? state);
      _showControls();
      return;
    }
    if (_nativeCrunchyroll) {
      if (state.playing) {
        await CrunchyrollRoomPlayer.pause();
      } else {
        await CrunchyrollRoomPlayer.play();
      }
      await widget.controller.togglePlayback(_position);
      _showControls();
      return;
    }
    if (_player == null) return;
    if (state.playing) {
      await _player!.pause();
    } else {
      await _player!.play();
      await _restoreLocalAudio();
    }
    await widget.controller.togglePlayback(_position);
    _showControls();
  }

  Future<void> _seek(double value) async {
    setState(() => _position = value);
    final state = widget.controller.watchState;
    if (_nativeCrunchyroll) {
      await CrunchyrollRoomPlayer.seek(value);
    } else if (_usesProviderBrowser(state)) {
      try {
        await _providerBrowser?.runJavaScript('''
          (() => {
            const video = document.querySelector('video');
            if (video) video.currentTime = ${value.clamp(0, double.infinity)};
          })();
        ''');
      } catch (_) {}
    } else {
      await _player?.seekTo(Duration(milliseconds: (value * 1000).round()));
    }
    await widget.controller.seek(value);
  }

  Future<void> _toggleMute() async {
    final next = !widget.controller.muted;
    widget.controller.setMuted(next);
    await _restoreLocalAudio();
    try {
      await _providerBrowser?.runJavaScript(
        "document.querySelectorAll('video').forEach(v => v.muted = ${next ? 'true' : 'false'});",
      );
    } catch (_) {}
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => _PlaybackSettings(
        controller: widget.controller,
        qualities: _qualities,
        onQuality: _changeQuality,
        captionLanguages: _captionLanguages,
        onCaption: _changeCaption,
      ),
    );
  }

  Future<void> _changeQuality(String quality) async {
    if (quality == widget.controller.selectedQuality) return;
    widget.controller.setQuality(quality);
    _loadedMediaKey = null;
    await _ensureVideo();
  }

  Future<void> _changeCaption(String languageCode) async {
    widget.controller.setCaption(languageCode);
    if (languageCode == 'off' || widget.controller.watchState == null) {
      setState(() {
        _captionCues = const [];
        _captionText = '';
      });
      return;
    }
    final cues = await _resolver.captions(
      widget.controller.watchState!.mediaId,
      languageCode,
    );
    if (mounted) setState(() => _captionCues = cues);
  }

  String _captionAt(Duration position) {
    for (final cue in _captionCues) {
      if (position >= cue.start && position <= cue.end) return cue.text;
    }
    return '';
  }

  Future<void> _openFullscreen() async {
    if (_usesProviderBrowser(widget.controller.watchState)) {
      return;
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: _player?.value.aspectRatio ?? 16 / 9,
                    child: _player == null
                        ? const SizedBox()
                        : VideoPlayer(_player!),
                  ),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.fullscreen_exit_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({
    required this.controller,
    required this.onAddSource,
    required this.onSettings,
    required this.onPeople,
  });

  final WatchPartyController controller;
  final VoidCallback onAddSource;
  final VoidCallback onSettings;
  final VoidCallback onPeople;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
    child: Column(
      children: [
        Row(
          children: [
            IconButton(
              onPressed: controller.leaveRoom,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
              style: IconButton.styleFrom(backgroundColor: Colors.transparent),
            ),
            IconButton(
              tooltip: 'Room controls',
              onPressed: onSettings,
              icon: const Icon(Icons.tune_rounded),
              style: IconButton.styleFrom(backgroundColor: Colors.transparent),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([controller, controller.voice]),
                builder: (context, _) {
                  final liveMembers = controller.voice.members
                      .where((member) => member.microphoneOn)
                      .toList();
                  final myId = controller.profile?.id;
                  final localIdentity = controller.voice.localIdentity;
                  final members = [
                    if (controller.voice.localMicrophoneActive)
                      VoiceMember(
                        localIdentity ?? myId ?? 'local',
                        controller.displayName,
                        true,
                        controller.voice.localSpeaking,
                      ),
                    ...liveMembers.where(
                      (member) =>
                          member.identity != localIdentity &&
                          member.identity != myId,
                    ),
                  ];
                  if (members.isEmpty) {
                    return const Text(
                      'XYNK',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.2,
                      ),
                    );
                  }
                  return Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final member in members.take(6))
                            Builder(
                              builder: (context) {
                                final isMe =
                                    member.identity == localIdentity ||
                                    member.identity == myId ||
                                    member.identity == 'local';
                                final person = controller.activeParticipants
                                    .cast<Map<String, dynamic>?>()
                                    .firstWhere(
                                      (item) =>
                                          item?['userId']?.toString() ==
                                          member.identity,
                                      orElse: () => null,
                                    );
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: Tooltip(
                                    message:
                                        '${person?['displayName'] ?? member.name} · Mic on',
                                    child: _HeaderVoiceAvatar(
                                      name:
                                          (person?['displayName'] ??
                                                  member.name)
                                              .toString(),
                                      avatarUrl:
                                          person?['avatarUrl']?.toString() ??
                                          (isMe
                                              ? controller.profile?.avatarUrl
                                              : null),
                                      isHost: person?['role'] == 'HOST',
                                      speaking: member.speaking,
                                    ),
                                  ),
                                );
                              },
                            ),
                          if (members.length > 6)
                            Text(
                              '+${members.length - 6}',
                              style: const TextStyle(fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            IconButton(
              tooltip: 'Choose a source',
              onPressed: controller.canAddToQueue ? onAddSource : null,
              icon: const Icon(Icons.add_circle_outline_rounded),
              style: IconButton.styleFrom(backgroundColor: Colors.transparent),
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  onPressed: onPeople,
                  icon: const Icon(Icons.group_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                  ),
                ),
                Positioned(
                  right: 1,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF4E7A),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${controller.activeRoom?.viewerCount ?? 1}',
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

class _HeaderVoiceAvatar extends StatefulWidget {
  const _HeaderVoiceAvatar({
    required this.name,
    required this.avatarUrl,
    required this.isHost,
    required this.speaking,
  });

  final String name;
  final String? avatarUrl;
  final bool isHost;
  final bool speaking;

  @override
  State<_HeaderVoiceAvatar> createState() => _HeaderVoiceAvatarState();
}

class _HeaderVoiceAvatarState extends State<_HeaderVoiceAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );

  @override
  void initState() {
    super.initState();
    if (widget.speaking) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _HeaderVoiceAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.speaking == oldWidget.speaking) return;
    if (widget.speaking) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.name.trim().isEmpty
        ? '?'
        : widget.name.trim()[0].toUpperCase();
    final url = widget.avatarUrl?.trim() ?? '';
    final resolvedUrl = url.startsWith('/') ? 'https://xynk.in$url' : url;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36,
            height: 36,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF261B36),
              border: Border.all(
                color: widget.speaking
                    ? const Color(0xFF67F5B4)
                    : const Color(0xFF80638F),
                width: widget.speaking ? 2 + _pulse.value : 1,
              ),
              boxShadow: widget.speaking
                  ? [
                      BoxShadow(
                        color: const Color(
                          0xFF67F5B4,
                        ).withValues(alpha: .2 + _pulse.value * .4),
                        blurRadius: 5 + _pulse.value * 9,
                      ),
                    ]
                  : null,
            ),
            child: ClipOval(
              child: resolvedUrl.isEmpty
                  ? ColoredBox(
                      color: const Color(0xFF895DA8),
                      child: Center(
                        child: Text(
                          initial,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                  : Image.network(
                      resolvedUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Center(child: Text(initial)),
                    ),
            ),
          ),
          if (widget.speaking)
            Positioned(
              left: -9,
              bottom: 5,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (final scale in [0.55, 1.0, 0.7])
                    Container(
                      width: 2.5,
                      height: 5 + 10 * scale * (0.35 + _pulse.value * 0.65),
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF67F5B4),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
          if (widget.isHost)
            const Positioned(
              right: -1,
              bottom: -1,
              child: Icon(
                Icons.star_rounded,
                size: 14,
                color: Color(0xFFFFD36D),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoomControlsSheet extends StatelessWidget {
  const _RoomControlsSheet({required this.controller});

  final WatchPartyController controller;

  @override
  Widget build(BuildContext context) {
    final host = controller.canControlWatch;
    final privacy = controller.activeRoom?.accessPolicy == 'INVITE_ONLY'
        ? 'INVITE'
        : controller.activeRoom?.visibility ?? 'PUBLIC';
    return SafeArea(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 620),
        decoration: const BoxDecoration(
          color: Color(0xF21A1717),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: ListView(
          shrinkWrap: true,
          children: [
            Center(
              child: Container(
                width: 52,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white54,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              host
                  ? 'Room controls'
                  : 'Only the host can change room settings.',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            const Text(
              'WHO CAN SET VIDEO',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            RadioGroup<String>(
              groupValue: controller.queueMode,
              onChanged: (value) {
                if (host && value != null) controller.setRoomQueueMode(value);
              },
              child: Column(
                children: [
                  RadioListTile<String>(
                    value: 'HOSTS_ONLY',
                    enabled: host,
                    title: const Text('Host only'),
                    subtitle: const Text(
                      'Only the host or co-host chooses videos',
                    ),
                    secondary: const Icon(Icons.workspace_premium_rounded),
                  ),
                  RadioListTile<String>(
                    value: 'PERMISSION',
                    enabled: host,
                    title: const Text('Selected people'),
                    subtitle: const Text(
                      'Grant video access from the participants list',
                    ),
                    secondary: const Icon(Icons.person_add_alt_1_rounded),
                  ),
                  RadioListTile<String>(
                    value: 'VOTE',
                    enabled: host,
                    title: const Text("Let's vote"),
                    subtitle: const Text(
                      'Everyone can add; the highest vote plays next',
                    ),
                    secondary: const Icon(Icons.how_to_vote_rounded),
                  ),
                ],
              ),
            ),
            const Divider(),
            const Text(
              'WHO CAN JOIN',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            RadioGroup<String>(
              groupValue: privacy,
              onChanged: (value) {
                if (host && value != null) {
                  controller.setRoomAudience(
                    value == 'INVITE' ? 'PRIVATE' : value,
                  );
                }
              },
              child: Column(
                children: [
                  for (final option in const [
                    ('PUBLIC', 'Everyone', Icons.public_rounded),
                    ('FRIENDS', 'Friends', Icons.people_alt_rounded),
                    ('INVITE', 'Invite only', Icons.lock_rounded),
                  ])
                    RadioListTile<String>(
                      value: option.$1,
                      enabled: host,
                      title: Text(option.$2),
                      secondary: Icon(option.$3),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Legacy picker retained temporarily for visual comparison during the rollout.
// ignore: unused_element
class _RoomSourcePicker extends StatelessWidget {
  const _RoomSourcePicker();

  @override
  Widget build(BuildContext context) {
    const sources = [
      ('YouTube', Icons.play_circle_fill_rounded, true, 'youtube'),
      ('Twitch', Icons.live_tv_rounded, false, 'twitch'),
      ('Web', Icons.language_rounded, false, 'web'),
      ('Drive', Icons.cloud_rounded, false, 'drive'),
      ('Photos', Icons.photo_library_rounded, false, 'photos'),
      ('History', Icons.history_rounded, false, 'history'),
    ];
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xF08F376F), Color(0xEE365786), Color(0xF00B1526)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Back to video',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const Expanded(
                      child: Text(
                        "XYNK",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Choose a source',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Your room stays open while you choose what plays next.',
                  style: TextStyle(color: Color(0xCCFFFFFF)),
                ),
                const SizedBox(height: 22),
                Expanded(
                  child: GridView.builder(
                    itemCount: sources.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 1.05,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemBuilder: (context, index) {
                      final source = sources[index];
                      return Opacity(
                        opacity: source.$3 ? 1 : .42,
                        child: Material(
                          color: const Color(0x2EFFFFFF),
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: source.$3
                                ? () => Navigator.pop(context, source.$4)
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(source.$2, size: 40),
                                  const SizedBox(height: 10),
                                  Text(
                                    source.$1,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    source.$3
                                        ? 'Available now'
                                        : 'Coming later',
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoAccessGate extends StatefulWidget {
  const _VideoAccessGate({
    required this.controller,
    required this.providerLabel,
    required this.onSignIn,
  });

  final WatchPartyController controller;
  final String providerLabel;
  final Future<void> Function() onSignIn;

  @override
  State<_VideoAccessGate> createState() => _VideoAccessGateState();
}

class _VideoAccessGateState extends State<_VideoAccessGate> {
  bool sending = false;

  Future<void> _request() async {
    if (sending) return;
    setState(() => sending = true);
    try {
      await widget.controller.requestCurrentVideoAccess();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final approved = widget.controller.canViewVideo;
    final requested = widget.controller.videoAccessRequested;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xED151722),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0x33FFFFFF)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 32,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 74,
                    height: 74,
                    decoration: const BoxDecoration(
                      color: Color(0x22FF4E7A),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      approved
                          ? Icons.person_rounded
                          : Icons.lock_person_rounded,
                      color: const Color(0xFFFF6B91),
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    approved ? 'Use your own account' : 'Video is private',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    approved
                        ? 'The owner approved you. Sign in to ${widget.providerLabel} with your own account to continue.'
                        : 'The video and player controls stay hidden until the room owner approves access.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.muted,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: approved
                          ? widget.onSignIn
                          : (requested || sending ? null : _request),
                      icon: sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              approved
                                  ? Icons.login_rounded
                                  : requested
                                  ? Icons.schedule_rounded
                                  : Icons.vpn_key_rounded,
                            ),
                      label: Text(
                        approved
                            ? 'Sign in with my account'
                            : requested
                            ? 'Waiting for owner approval'
                            : 'Ask owner for access',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: AppColors.muted,
                      ),
                      SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          'Owner cookies and passwords are never shared.',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WatchMode extends StatelessWidget {
  const _WatchMode({
    required this.controller,
    required this.resolvedTitle,
    required this.showLoading,
    required this.playerAspectRatio,
    required this.isScreenShare,
    required this.isLocalScreenShare,
    required this.player,
    required this.showControls,
    required this.position,
    required this.duration,
    required this.onPlayPause,
    required this.onSeek,
    required this.onMute,
    required this.onSettings,
    required this.onPip,
    required this.onFullscreen,
    required this.showPicker,
    required this.onToggleControls,
  });

  final WatchPartyController controller;
  final String? resolvedTitle;
  final bool showLoading;
  final double playerAspectRatio;
  final bool isScreenShare;
  final bool isLocalScreenShare;
  final Widget? player;
  final bool showControls;
  final double position;
  final double duration;
  final VoidCallback onPlayPause;
  final ValueChanged<double> onSeek;
  final VoidCallback onMute;
  final VoidCallback onSettings;
  final VoidCallback onPip;
  final VoidCallback onFullscreen;
  final bool showPicker;
  final VoidCallback onToggleControls;

  @override
  Widget build(BuildContext context) {
    final playerCard = _PlayerCard(
      compact: true,
      aspectRatio: playerAspectRatio,
      expand: isScreenShare,
      player: Stack(
        fit: StackFit.expand,
        children: [
          player ??
              const Center(
                child: Icon(
                  Icons.ondemand_video_rounded,
                  size: 42,
                  color: AppColors.muted,
                ),
              ),
          if (showLoading) const _PulsingVideoLoader(),
          if (isLocalScreenShare)
            const Positioned(
              left: 10,
              top: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xCC131922),
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  child: Text(
                    'Sharing · chat below',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ),
          if (controller.watchState != null && !showPicker)
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: onToggleControls,
              child: _RavePlayerOverlay(
                controller: controller,
                title: resolvedTitle?.trim().isNotEmpty == true
                    ? resolvedTitle!.trim()
                    : _mediaTitle(controller.watchState),
                source: _sourceLabel(controller.watchState),
                visible: showControls,
                position: position,
                duration: duration,
                onPlayPause: onPlayPause,
                onSeek: onSeek,
                onMute: onMute,
                onSettings: onSettings,
                onPip: onPip,
                onFullscreen: onFullscreen,
              ),
            ),
        ],
      ),
    );
    final emptyPlayer =
        controller.watchState == null && !showPicker && !isScreenShare
        ? _EmptyPlayer(onFindVideo: () => controller.setShelfOpen(true))
        : const SizedBox.shrink();
    final orientation = MediaQuery.orientationOf(context);
    if (orientation == Orientation.landscape) {
      return Row(
        children: [
          Expanded(
            flex: 3,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final safeAspectRatio =
                    playerAspectRatio.isFinite && playerAspectRatio >= 1.2
                    ? playerAspectRatio.clamp(1.2, 2.5)
                    : 16 / 9;
                final maxWidth = math.max(0.0, constraints.maxWidth - 24);
                final maxHeight = math.max(0.0, constraints.maxHeight - 24);
                final width = isLocalScreenShare
                    ? math.min(maxWidth * .58, 480.0)
                    : isScreenShare
                    ? maxWidth
                    : math.min(maxWidth, maxHeight * safeAspectRatio);
                return Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: SizedBox(
                          width: width,
                          height: isLocalScreenShare
                              ? math.min(maxHeight * .5, 270.0)
                              : isScreenShare
                              ? maxHeight
                              : width / safeAspectRatio,
                          child: playerCard,
                        ),
                      ),
                    ),
                    emptyPlayer,
                  ],
                );
              },
            ),
          ),
          const VerticalDivider(width: 1, color: AppColors.line),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                _PanelTabs(controller: controller),
                Expanded(child: _PanelBody(controller: controller)),
              ],
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep the portrait player Rave-sized instead of letting it consume
        // most of the room. The remaining vertical space belongs to the
        // conversation and queue; fullscreen and PiP are explicit actions.
        final availableWidth = math.max(0.0, constraints.maxWidth - 20);
        final safeAspectRatio =
            playerAspectRatio.isFinite && playerAspectRatio >= 1.2
            ? playerAspectRatio.clamp(1.2, 2.5)
            : 16 / 9;
        final playerHeight = isLocalScreenShare
            ? math.min(constraints.maxHeight * .24, availableWidth / 2.2)
            : isScreenShare
            ? math.min(constraints.maxHeight * .5, availableWidth * 1.25)
            : math.min(
                availableWidth / safeAspectRatio,
                constraints.maxHeight * .28,
              );
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Center(
                child: SizedBox(
                  width: isScreenShare
                      ? availableWidth
                      : playerHeight * safeAspectRatio,
                  height: playerHeight,
                  child: playerCard,
                ),
              ),
            ),
            emptyPlayer,
            _PanelTabs(controller: controller),
            Expanded(child: _PanelBody(controller: controller)),
          ],
        );
      },
    );
  }
}

class _RavePlayerOverlay extends StatelessWidget {
  const _RavePlayerOverlay({
    required this.controller,
    required this.title,
    required this.source,
    required this.visible,
    required this.position,
    required this.duration,
    required this.onPlayPause,
    required this.onSeek,
    required this.onMute,
    required this.onSettings,
    required this.onPip,
    required this.onFullscreen,
  });

  final WatchPartyController controller;
  final String title;
  final String source;
  final bool visible;
  final double position;
  final double duration;
  final VoidCallback onPlayPause;
  final ValueChanged<double> onSeek;
  final VoidCallback onMute;
  final VoidCallback onSettings;
  final VoidCallback onPip;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66000000),
                  Colors.transparent,
                  Color(0xDD000000),
                ],
                stops: [0, .38, 1],
              ),
            ),
          ),
          Positioned(
            left: 11,
            right: 8,
            top: 7,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          shadows: [Shadow(blurRadius: 5, color: Colors.black)],
                        ),
                      ),
                      Text(
                        source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                _OverlayIconButton(
                  tooltip: 'Queue',
                  icon: Icons.queue_music_rounded,
                  label: '${controller.queue.length}',
                  onPressed: () => controller.setShelfOpen(true),
                ),
              ],
            ),
          ),
          Positioned(
            left: 6,
            right: 6,
            bottom: 3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 22,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 11,
                      ),
                    ),
                    child: Slider(
                      value: position.clamp(0, duration),
                      max: duration,
                      onChanged: duration > 0 && controller.canControlWatch
                          ? onSeek
                          : null,
                    ),
                  ),
                ),
                Row(
                  children: [
                    _OverlayIconButton(
                      tooltip: 'Play or pause',
                      icon: controller.watchState?.playing == true
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      onPressed: controller.canControlWatch
                          ? onPlayPause
                          : null,
                    ),
                    _OverlayIconButton(
                      tooltip: 'Mute',
                      icon: controller.muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      onPressed: onMute,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${_time(position)} / ${duration > 0 ? _time(duration) : '--:--'}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    _OverlayIconButton(
                      tooltip: 'Playback settings',
                      icon: Icons.tune_rounded,
                      onPressed: onSettings,
                    ),
                    _OverlayIconButton(
                      tooltip: 'Picture in picture',
                      icon: Icons.picture_in_picture_alt_rounded,
                      onPressed: onPip,
                    ),
                    _OverlayIconButton(
                      tooltip: 'Fullscreen',
                      icon: Icons.fullscreen_rounded,
                      onPressed: onFullscreen,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.label,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: label == null ? 31 : 43,
    height: 31,
    child: IconButton(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: label == null
          ? Icon(icon, size: 20)
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17),
                const SizedBox(width: 2),
                Text(label!, style: const TextStyle(fontSize: 9)),
              ],
            ),
    ),
  );
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.player,
    this.compact = false,
    this.aspectRatio = 16 / 9,
    this.expand = false,
  });

  final Widget? player;
  final bool compact;
  final double aspectRatio;
  final bool expand;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.black,
      borderRadius: BorderRadius.circular(compact ? 14 : 0),
      border: Border.all(color: const Color(0x33FFFFFF)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x99000000),
          blurRadius: 28,
          offset: Offset(0, 12),
        ),
      ],
    ),
    child: expand
        ? SizedBox.expand(child: player)
        : AspectRatio(
            aspectRatio: aspectRatio,
            child:
                player ??
                const Center(
                  child: Icon(
                    Icons.ondemand_video_rounded,
                    size: 42,
                    color: AppColors.muted,
                  ),
                ),
          ),
  );
}

class _PulsingVideoLoader extends StatelessWidget {
  const _PulsingVideoLoader();

  @override
  Widget build(BuildContext context) =>
      const WaveLoader(label: 'Starting video', showScrim: true, size: 58);
}

class _RailLabel extends StatelessWidget {
  const _RailLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xD90B0D12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0x552BD9A5)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.lime,
        fontSize: 7,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _QueuePickerAvatars extends StatelessWidget {
  const _QueuePickerAvatars({
    required this.pickers,
    required this.controller,
    this.size = 22,
    this.maxVisible = 4,
  });

  final List<QueuePicker> pickers;
  final WatchPartyController controller;
  final double size;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    if (pickers.isEmpty) return const SizedBox.shrink();
    final visible = pickers.take(maxVisible).toList(growable: false);
    final overlap = size * .62;
    return Semantics(
      label: pickers.map((picker) => picker.displayName).join(', '),
      child: SizedBox(
        width: size + (visible.length - 1) * overlap,
        height: size,
        child: Stack(
          children: [
            for (var index = 0; index < visible.length; index++)
              Positioned(
                left: index * overlap,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => UserProfileScreen(
                        controller: controller,
                        userId: visible[index].userId,
                        summary: {
                          'id': visible[index].userId,
                          'displayName': visible[index].displayName,
                          'avatarUrl': visible[index].avatarUrl,
                        },
                      ),
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0B0D12),
                        width: 1.5,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: (size - 3) / 2,
                      backgroundColor: const Color(0xFF49334F),
                      foregroundImage:
                          visible[index].avatarUrl?.trim().isNotEmpty == true
                          ? NetworkImage(visible[index].avatarUrl!.trim())
                          : null,
                      child: Text(
                        visible[index].displayName.trim().isEmpty
                            ? '?'
                            : visible[index].displayName.characters.first
                                  .toUpperCase(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: size * .38,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InlineQueuePicker extends StatelessWidget {
  const _InlineQueuePicker({
    required this.controller,
    required this.livePlayer,
    required this.playerAspectRatio,
    required this.showCurrent,
  });

  final WatchPartyController controller;
  final Widget? livePlayer;
  final double playerAspectRatio;
  final bool showCurrent;

  @override
  Widget build(BuildContext context) {
    final current = controller.watchState;
    final currentMediaId = current?.mediaId ?? controller.activeRoom?.mediaId;
    final currentTitle = current?.title ?? controller.activeRoom?.mediaTitle;
    final cards = <Widget>[
      if (showCurrent && currentMediaId != null && currentMediaId.isNotEmpty)
        _LiveQueuePlayerCard(
          player: livePlayer,
          aspectRatio: playerAspectRatio,
          title: currentTitle?.isNotEmpty == true
              ? currentTitle!
              : 'Current video',
          onTap: () => controller.setShelfOpen(false),
        ),
      for (final item in controller.roomQueue)
        _RoomPickCard(
          controller: controller,
          mediaId: item.mediaId,
          provider: item.provider,
          title: item.title,
          subtitle: '${item.voteCount} picks · ${item.addedByName}',
          thumbnailUrl: item.thumbnailUrl,
          label: item.votedByMe ? 'YOUR PICK' : 'QUEUE',
          selected: item.votedByMe,
          pickers: item.pickers,
          onTap: () => controller.selectQueueItem(item),
        ),
      for (final video in controller.suggestions)
        _RoomPickCard(
          controller: controller,
          mediaId: video.videoId,
          provider: video.provider,
          title: video.title,
          subtitle: video.channelTitle,
          thumbnailUrl: video.thumbnailUrl,
          label: controller.suggestionItemLabel,
          onTap: () => controller.addSuggestion(video),
        ),
    ];
    return ColoredBox(
      color: const Color(0xFF090B10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'PLAYING · QUEUE · ${controller.suggestionSectionTitle}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Back to video',
                    onPressed: () => controller.setShelfOpen(false),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: cards.isEmpty
                ? const Center(
                    child: Text(
                      'Search and add a video from Queue.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) => GridView.builder(
                      padding: EdgeInsets.zero,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio:
                            (constraints.maxWidth / 2) /
                            (constraints.maxHeight / 2),
                        mainAxisSpacing: 0,
                        crossAxisSpacing: 0,
                      ),
                      itemCount: cards.length,
                      itemBuilder: (_, index) => cards[index],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LiveQueuePlayerCard extends StatelessWidget {
  const _LiveQueuePlayerCard({
    required this.player,
    required this.aspectRatio,
    required this.title,
    required this.onTap,
  });

  final Widget? player;
  final double aspectRatio;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final safeAspectRatio = aspectRatio.isFinite && aspectRatio > 0
        ? aspectRatio
        : 16 / 9;
    return Material(
      color: Colors.black,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: safeAspectRatio,
                child:
                    player ??
                    const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC000000)],
                  stops: [.55, 1],
                ),
              ),
            ),
            const Positioned(
              left: 7,
              top: 6,
              child: _RailLabel(text: 'NOW PLAYING · LIVE'),
            ),
            Positioned(
              left: 7,
              right: 7,
              bottom: 6,
              child: Row(
                children: [
                  const Icon(
                    Icons.graphic_eq_rounded,
                    size: 14,
                    color: AppColors.lime,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.fromBorderSide(
                      BorderSide(color: AppColors.lime, width: 2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomPickCard extends StatelessWidget {
  const _RoomPickCard({
    required this.controller,
    required this.mediaId,
    required this.provider,
    required this.title,
    required this.subtitle,
    required this.label,
    required this.onTap,
    this.thumbnailUrl,
    this.selected = false,
    this.pickers = const [],
  });

  final WatchPartyController controller;
  final String mediaId;
  final String provider;
  final String title;
  final String subtitle;
  final String label;
  final String? thumbnailUrl;
  final bool selected;
  final List<QueuePicker> pickers;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF11151C),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MediaPreview(
            mediaId: mediaId,
            provider: provider,
            thumbnailUrl: thumbnailUrl,
            contentLabel: title,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xE5000000)],
                stops: [.38, 1],
              ),
            ),
          ),
          if (selected)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.fromBorderSide(
                      BorderSide(color: AppColors.lime, width: 2),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(left: 7, top: 6, child: _RailLabel(text: label)),
          Positioned(
            left: 7,
            right: 7,
            bottom: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xCCFFFFFF),
                          fontSize: 8,
                        ),
                      ),
                    ),
                    if (pickers.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      _QueuePickerAvatars(
                        pickers: pickers,
                        controller: controller,
                        size: 19,
                        maxVisible: 3,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _EmptyPlayer extends StatelessWidget {
  const _EmptyPlayer({required this.onFindVideo});

  final VoidCallback onFindVideo;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onFindVideo,
        icon: const Icon(Icons.search_rounded),
        label: const Text('Find the first video'),
      ),
    ),
  );
}

class _PanelTabs extends StatelessWidget {
  const _PanelTabs({required this.controller});

  final WatchPartyController controller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0x99090A12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Row(
        children: [
          _Tab(
            label: 'Chat',
            icon: Icons.forum_rounded,
            selected: controller.panel == RoomPanel.chat,
            onTap: () => controller.setPanel(RoomPanel.chat),
          ),
          _Tab(
            label: 'Queue',
            icon: Icons.queue_music_rounded,
            selected: controller.panel == RoomPanel.queue,
            badge: controller.queue.length,
            onTap: () => controller.setPanel(RoomPanel.queue),
          ),
        ],
      ),
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0x557B4DFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : Colors.white60,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: selected ? Colors.white : Colors.white60,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 5),
              Text(
                '$badge',
                style: const TextStyle(fontSize: 10, color: Color(0xFFFF75C3)),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _PanelBody extends StatelessWidget {
  const _PanelBody({required this.controller});

  final WatchPartyController controller;

  @override
  Widget build(BuildContext context) => switch (controller.panel) {
    RoomPanel.chat => _ChatPanel(controller: controller),
    RoomPanel.queue => _QueuePanel(controller: controller),
    RoomPanel.people => _PeoplePanel(controller: controller),
  };
}

class _ChatPanel extends StatefulWidget {
  const _ChatPanel({required this.controller});

  final WatchPartyController controller;

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  final field = TextEditingController();
  static const reactions = ['❤️', '🔥', '😂', '😍', '👏', '😮', '😢', '👍'];

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          reverse: true,
          itemCount:
              widget.controller.messages.length +
              (widget.controller.watchState == null ? 1 : 2),
          itemBuilder: (context, index) {
            final messageCount = widget.controller.messages.length;
            if (index < messageCount) {
              final message = widget.controller.messages.reversed.elementAt(
                index,
              );
              if (message.isSystem) {
                return _TimelineEventMessage(
                  message: message,
                  controller: widget.controller,
                );
              }
              return _MessageBubble(
                message: message,
                onReply: () => _reply(message),
                onReact: (reaction) =>
                    widget.controller.reactToMessage(message, reaction),
                onMore: () => _showMessageActions(message),
              );
            }
            if (widget.controller.watchState != null && index == messageCount) {
              return _NowPlayingMessage(controller: widget.controller);
            }
            if (index >= messageCount) {
              return _RoomConversationSetupCard(controller: widget.controller);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.controller.replyToMessage case final reply?)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(12, 7, 5, 7),
                decoration: BoxDecoration(
                  color: const Color(0x55261B35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x446F63FF)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.reply_rounded,
                      size: 17,
                      color: AppColors.mint,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Replying to ${reply.senderName} · ${reply.body}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.controller.cancelReply,
                      icon: const Icon(Icons.close_rounded, size: 17),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  onPressed: () async {
                    final room = widget.controller.activeRoom;
                    if (room == null) return;
                    try {
                      final granted = await DeviceFeatures.requestMicrophone();
                      if (!context.mounted) return;
                      if (!granted) {
                        throw Exception(
                          'Microphone permission is required for room voice.',
                        );
                      }
                      await widget.controller.voice.toggleMicrophone(room.id);
                    } catch (exception) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            widget.controller.voice.error ??
                                exception.toString().replaceFirst(
                                  'Exception: ',
                                  '',
                                ),
                          ),
                        ),
                      );
                    }
                  },
                  icon: Icon(
                    widget.controller.voice.microphoneEnabled
                        ? Icons.mic_rounded
                        : Icons.mic_off_rounded,
                  ),
                  color: widget.controller.voice.microphoneEnabled
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  tooltip: widget.controller.voice.microphoneEnabled
                      ? 'Mute room microphone'
                      : 'Join voice and enable microphone',
                ),
                IconButton(
                  onPressed: widget.controller.voice.busy
                      ? null
                      : () async {
                          final room = widget.controller.activeRoom;
                          if (room == null) return;
                          try {
                            await widget.controller.voice.toggleSpeakerphone(
                              room.id,
                            );
                          } catch (_) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  widget.controller.voice.error ??
                                      'Could not change the voice output.',
                                ),
                              ),
                            );
                          }
                        },
                  icon: Icon(
                    widget.controller.voice.speakerphoneEnabled
                        ? Icons.volume_up_rounded
                        : Icons.hearing_rounded,
                  ),
                  tooltip: widget.controller.voice.speakerphoneEnabled
                      ? 'Use phone earpiece'
                      : 'Use speakerphone',
                ),
                IconButton(
                  onPressed: widget.controller.voice.busy
                      ? null
                      : () async {
                          final room = widget.controller.activeRoom;
                          if (room == null) return;
                          try {
                            final me = widget.controller.activeParticipants
                                .where(
                                  (person) =>
                                      person['userId']?.toString() ==
                                      widget.controller.profile?.id,
                                )
                                .firstOrNull;
                            if (!widget.controller.voice.screenShareEnabled &&
                                room.role != 'HOST' &&
                                me?['canShareScreen'] != true) {
                              if (me?['screenShareRequested'] != true)
                                await widget.controller.api.requestScreenShare(
                                  room.id,
                                );
                              if (context.mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Screen share request sent to the host.',
                                    ),
                                  ),
                                );
                              return;
                            }
                            if (!widget.controller.voice.screenShareEnabled &&
                                !await confirmScreenShare(context)) {
                              return;
                            }
                            if (!widget.controller.voice.screenShareEnabled &&
                                room.role != 'HOST')
                              await widget.controller.voice.refreshPermissions(
                                room.id,
                              );
                            await widget.controller.startScreenSharing(
                              targetRoomId: room.id,
                            );
                          } catch (exception) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  widget.controller.voice.error ??
                                      exception.toString().replaceFirst(
                                        'Exception: ',
                                        '',
                                      ),
                                ),
                              ),
                            );
                          }
                        },
                  icon: Icon(
                    widget.controller.voice.screenShareEnabled
                        ? Icons.stop_screen_share_rounded
                        : Icons.screen_share_rounded,
                  ),
                  color: widget.controller.voice.screenShareEnabled
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  tooltip: widget.controller.voice.screenShareEnabled
                      ? 'Stop screen sharing'
                      : 'Share phone screen',
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _openPeoplePicker,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  tooltip: 'Invite, chat, and manage people',
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: field,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Say something…',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _send,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.lime,
                    foregroundColor: AppColors.ink,
                  ),
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );

  void _send() {
    final body = field.text;
    field.clear();
    widget.controller.sendMessage(body);
  }

  void _reply(ChatMessage message, {bool tag = false}) {
    widget.controller.beginReply(message);
    if (tag && message.senderUsername.isNotEmpty) {
      final mention = '@${message.senderUsername} ';
      if (!field.text.contains(mention)) field.text = '$mention${field.text}';
      field.selection = TextSelection.collapsed(offset: field.text.length);
    }
    setState(() {});
  }

  Future<void> _showMessageActions(ChatMessage message) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF171923),
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceAround,
                  children: [
                    for (final reaction in reactions)
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.controller.reactToMessage(message, reaction);
                        },
                        child: Text(
                          reaction,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                  ],
                ),
                ListTile(
                  leading: const Icon(Icons.reply_rounded),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.pop(context);
                    _reply(message);
                  },
                ),
                if (!message.isMine)
                  ListTile(
                    leading: const Icon(Icons.alternate_email_rounded),
                    title: Text('Reply and tag @${message.senderUsername}'),
                    onTap: () {
                      Navigator.pop(context);
                      _reply(message, tag: true);
                    },
                  ),
              ],
            ),
          ),
        ),
      );

  Future<void> _openPeoplePicker() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF12141D),
    builder: (context) => FractionallySizedBox(
      heightFactor: .9,
      child: _RoomPeoplePicker(controller: widget.controller),
    ),
  );
}

class _NowPlayingMessage extends StatelessWidget {
  const _NowPlayingMessage({required this.controller});

  final WatchPartyController controller;

  Future<void> _open(BuildContext context, RoomWatchState state) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => MediaDiscoveryScreen(
            controller: controller,
            targetRoomId: controller.activeRoom?.id,
            initialProvider: state.provider,
            initialMediaId: state.mediaId,
            initialSourceUrl: state.sourceUrl,
            initialQuery: _mediaTitle(state),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final state = controller.watchState;
    if (state == null) return const SizedBox.shrink();
    final provider = _sourceLabel(state);
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: () => _open(context, state),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: const Color(0xC21A1521),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x44FFFFFF)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 76,
                  height: 52,
                  child: MediaPreview(
                    mediaId: state.mediaId,
                    provider: state.provider,
                    thumbnailUrl:
                        state.thumbnailUrl ?? controller.currentThumbnail,
                    contentLabel: state.title,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Now playing on $provider',
                      style: const TextStyle(
                        color: AppColors.mint,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _mediaTitle(state),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomPeoplePicker extends StatefulWidget {
  const _RoomPeoplePicker({required this.controller});

  final WatchPartyController controller;

  @override
  State<_RoomPeoplePicker> createState() => _RoomPeoplePickerState();
}

class _RoomPeoplePickerState extends State<_RoomPeoplePicker> {
  int section = 0;
  bool loading = true;
  bool sending = false;
  String? error;
  List<Map<String, dynamic>> friends = const [];
  List<Map<String, dynamic>> recent = const [];
  List<Map<String, dynamic>> requests = const [];
  List<Map<String, dynamic>> blocked = const [];
  final Set<String> selected = <String>{};
  final Set<String> sent = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final roomId = widget.controller.activeRoom?.id;
    if (roomId == null) return;
    if (mounted) setState(() => loading = true);
    try {
      final data = await Future.wait([
        widget.controller.api.friends(),
        widget.controller.api.recentRoomPeople(roomId),
        widget.controller.api.friendRequests(),
        widget.controller.api.blockedPeople(),
      ]);
      if (!mounted) return;
      setState(() {
        friends = data[0];
        recent = data[1];
        requests = data[2];
        blocked = data[3];
        loading = false;
        error = null;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = exception.toString();
      });
    }
  }

  String _id(Map<String, dynamic> person) =>
      (person['id'] ?? person['userId'] ?? '').toString();

  String _name(Map<String, dynamic> person) =>
      (person['displayName'] ?? person['username'] ?? 'Member').toString();

  Widget _avatar(Map<String, dynamic> person) {
    final name = _name(person);
    final url = person['avatarUrl']?.toString();
    return CircleAvatar(
      backgroundColor: const Color(0xFF34263D),
      foregroundImage: url != null && url.isNotEmpty ? NetworkImage(url) : null,
      child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase()),
    );
  }

  Future<void> _inviteSelected() async {
    final roomId = widget.controller.activeRoom?.id;
    if (roomId == null || selected.isEmpty || sending) return;
    setState(() => sending = true);
    var count = 0;
    try {
      for (final userId in selected.toList()) {
        await widget.controller.api.inviteUserToRoom(roomId, userId);
        sent.add(userId);
        count++;
      }
      selected.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sent $count room invite${count == 1 ? '' : 's'}'),
        ),
      );
      setState(() {});
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(exception.toString())));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _openChat(Map<String, dynamic> person) async {
    final friend = {...person, 'id': _id(person)};
    await Navigator.of(
      context,
    ).push<void>(directChatRoute(widget.controller, friend));
  }

  Future<void> _decide(Map<String, dynamic> request, bool accept) async {
    await widget.controller.api.decideFriendRequest(
      request['id'].toString(),
      accept,
    );
    await _load();
  }

  Future<void> _requestFriend(Map<String, dynamic> person) async {
    try {
      await widget.controller.api.sendFriendRequest(_id(person));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Friend request sent to ${_name(person)}')),
      );
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(exception.toString())));
    }
  }

  Future<void> _block(Map<String, dynamic> person) async {
    await widget.controller.api.blockUser(_id(person));
    await _load();
  }

  Future<void> _unblock(Map<String, dynamic> person) async {
    await widget.controller.api.unblockUser(_id(person));
    await _load();
  }

  Widget _empty(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.muted),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'People',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        child: Row(
          children: [
            Expanded(child: _pickerChip(0, 'Invite', friends.length)),
            Expanded(child: _pickerChip(1, 'Recent', recent.length)),
            Expanded(child: _pickerChip(2, 'Requests', requests.length)),
            Expanded(child: _pickerChip(3, 'Blocked', blocked.length)),
          ],
        ),
      ),
      const Divider(height: 18, color: Color(0x28FFFFFF)),
      Expanded(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
            ? _empty(error!)
            : switch (section) {
                0 => _inviteList(),
                1 => _recentList(),
                2 => _requestList(),
                _ => _blockedList(),
              },
      ),
      if (section == 0)
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: selected.isEmpty || sending ? null : _inviteSelected,
                icon: sending
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  selected.isEmpty
                      ? 'Select friends to invite'
                      : 'Invite ${selected.length} selected',
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _pickerChip(int value, String label, int count) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: SizedBox(
      width: double.infinity,
      child: ChoiceChip(
        selected: section == value,
        onSelected: (_) => setState(() => section = value),
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        visualDensity: VisualDensity.compact,
        label: SizedBox(
          width: double.infinity,
          child: Text(
            '$label\n$count',
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(fontSize: 11, height: 1.05),
          ),
        ),
      ),
    ),
  );

  Widget _inviteList() {
    if (friends.isEmpty) {
      return _empty(
        'No friends yet. Recent room people appear in the next tab.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: friends.length,
      itemBuilder: (context, index) {
        final friend = friends[index];
        final id = _id(friend);
        final isSent = sent.contains(id);
        return ListTile(
          onTap: () => _openChat(friend),
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              _avatar(friend),
              if (friend['online'] == true)
                const Positioned(
                  right: -1,
                  bottom: -1,
                  child: CircleAvatar(
                    radius: 5,
                    backgroundColor: AppColors.mint,
                  ),
                ),
            ],
          ),
          title: Text(_name(friend)),
          subtitle: Text(
            '@${friend['username'] ?? 'friend'} · tap row to chat',
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
          trailing: isSent
              ? const Icon(Icons.check_circle_rounded, color: AppColors.mint)
              : Checkbox(
                  shape: const CircleBorder(),
                  value: selected.contains(id),
                  onChanged: (_) => setState(() {
                    selected.contains(id)
                        ? selected.remove(id)
                        : selected.add(id);
                  }),
                ),
        );
      },
    );
  }

  Widget _recentList() {
    if (recent.isEmpty) {
      return _empty(
        'People you share rooms with will appear here, once each, up to 500.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: recent.length,
      itemBuilder: (context, index) {
        final person = recent[index];
        final isFriend = person['friend'] == true;
        return ListTile(
          onTap: isFriend ? () => _openChat(person) : null,
          leading: _avatar(person),
          title: Text(_name(person)),
          subtitle: Text(
            '${person['roomName'] ?? 'Shared room'}${isFriend ? ' · tap to chat' : ''}',
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isFriend)
                IconButton(
                  tooltip: 'Add friend',
                  onPressed: () => _requestFriend(person),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'block') _block(person);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'block', child: Text('Block user')),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _requestList() {
    if (requests.isEmpty) return _empty('No pending friend requests.');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        final request = requests[index];
        return ListTile(
          leading: _avatar(request),
          title: Text(_name(request)),
          subtitle: Text('@${request['username'] ?? 'member'}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Reject',
                onPressed: () => _decide(request, false),
                icon: const Icon(Icons.close_rounded),
              ),
              IconButton.filledTonal(
                tooltip: 'Accept',
                onPressed: () => _decide(request, true),
                icon: const Icon(Icons.check_rounded),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _blockedList() {
    if (blocked.isEmpty) return _empty('You have not blocked anyone.');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: blocked.length,
      itemBuilder: (context, index) {
        final person = blocked[index];
        return ListTile(
          leading: _avatar(person),
          title: Text(_name(person)),
          subtitle: Text('@${person['username'] ?? 'member'}'),
          trailing: TextButton(
            onPressed: () => _unblock(person),
            child: const Text('Unblock'),
          ),
        );
      },
    );
  }
}

class _RoomConversationSetupCard extends StatefulWidget {
  const _RoomConversationSetupCard({required this.controller});

  final WatchPartyController controller;

  @override
  State<_RoomConversationSetupCard> createState() =>
      _RoomConversationSetupCardState();
}

class _RoomConversationSetupCardState
    extends State<_RoomConversationSetupCard> {
  List<Map<String, dynamic>> friends = const [];
  final Set<String> inviting = <String>{};
  final Set<String> invited = <String>{};
  bool changingAudience = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loaded = await widget.controller.api.friends();
      if (mounted) setState(() => friends = loaded);
    } catch (_) {
      // The full participants panel offers retry and detailed errors.
    }
  }

  Future<void> _invite(Map<String, dynamic> friend) async {
    final roomId = widget.controller.activeRoom?.id;
    final userId = (friend['id'] ?? friend['userId'])?.toString();
    if (roomId == null ||
        userId == null ||
        inviting.contains(userId) ||
        invited.contains(userId)) {
      return;
    }
    setState(() => inviting.add(userId));
    try {
      await widget.controller.api.inviteUserToRoom(roomId, userId);
      if (!mounted) return;
      setState(() => invited.add(userId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Invite sent to ${friend['displayName'] ?? friend['username'] ?? 'friend'}',
          ),
        ),
      );
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(exception.toString())));
    } finally {
      if (mounted) setState(() => inviting.remove(userId));
    }
  }

  Future<void> _setAudience(String visibility) async {
    if (changingAudience || widget.controller.activeRoom?.role != 'HOST') {
      return;
    }
    setState(() => changingAudience = true);
    try {
      await widget.controller.setRoomAudience(visibility);
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(exception.toString())));
    } finally {
      if (mounted) setState(() => changingAudience = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.controller.activeRoom;
    if (room == null) return const SizedBox.shrink();
    final isHost = room.role == 'HOST';
    final visibility = room.visibility.toUpperCase();
    final currentLabel = switch (visibility) {
      'PRIVATE' => 'Invite only',
      'FRIENDS' => 'Friends only',
      _ => 'Public',
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 10),
        decoration: BoxDecoration(
          color: const Color(0xB20B0C14),
          borderRadius: BorderRadius.circular(
            17,
          ).copyWith(bottomLeft: const Radius.circular(4)),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 14,
                  backgroundColor: Color(0x3352E09D),
                  child: Icon(
                    Icons.lock_person_rounded,
                    size: 15,
                    color: AppColors.mint,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isHost
                        ? 'Choose who can join this room'
                        : '$currentLabel room',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (changingAudience)
                  const SizedBox.square(
                    dimension: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (isHost) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _AudienceChoice(
                    label: 'Public',
                    icon: Icons.public_rounded,
                    selected: visibility == 'PUBLIC',
                    onTap: () => _setAudience('PUBLIC'),
                  ),
                  _AudienceChoice(
                    label: 'Friends',
                    icon: Icons.group_rounded,
                    selected: visibility == 'FRIENDS',
                    onTap: () => _setAudience('FRIENDS'),
                  ),
                  _AudienceChoice(
                    label: 'Invite only',
                    icon: Icons.lock_rounded,
                    selected: visibility == 'PRIVATE',
                    onTap: () => _setAudience('PRIVATE'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Invite with a message',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 75,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: friends.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _QuickInviteItem(
                      label: 'More',
                      icon: Icons.person_add_alt_1_rounded,
                      onTap: () => widget.controller.setPanel(RoomPanel.people),
                    );
                  }
                  final friend = friends[index - 1];
                  final userId =
                      (friend['id'] ?? friend['userId'])?.toString() ?? '';
                  final name =
                      (friend['displayName'] ?? friend['username'] ?? 'Friend')
                          .toString();
                  return _QuickInviteItem(
                    label: name,
                    avatarUrl: friend['avatarUrl']?.toString(),
                    online: friend['online'] == true,
                    busy: inviting.contains(userId),
                    invited: invited.contains(userId),
                    onTap: () => _invite(friend),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudienceChoice extends StatelessWidget {
  const _AudienceChoice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    selected: selected,
    onSelected: (_) => onTap(),
    avatar: Icon(icon, size: 15),
    label: Text(label),
    labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
    visualDensity: VisualDensity.compact,
  );
}

class _QuickInviteItem extends StatelessWidget {
  const _QuickInviteItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.avatarUrl,
    this.online = false,
    this.busy = false,
    this.invited = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final String? avatarUrl;
  final bool online;
  final bool busy;
  final bool invited;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 58,
    child: InkWell(
      onTap: busy || invited ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: const Color(0xFF242B33),
                foregroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
                    ? NetworkImage(avatarUrl!)
                    : null,
                child: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        invited ? Icons.check_rounded : icon ?? Icons.person,
                        color: invited ? AppColors.mint : Colors.white,
                      ),
              ),
              if (online && !invited)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: AppColors.mint,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.ink, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            invited ? 'Sent' : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: invited ? AppColors.mint : Colors.white70,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TimelineEventMessage extends StatelessWidget {
  const _TimelineEventMessage({
    required this.message,
    required this.controller,
  });

  final ChatMessage message;
  final WatchPartyController controller;

  Future<void> _openVideo(BuildContext context) async {
    final mediaId = message.mediaId?.trim();
    if (mediaId == null || mediaId.isEmpty) return;
    final provider = (message.mediaProvider ?? 'WEB').trim().toUpperCase();
    final parsed = Uri.tryParse(mediaId);
    final sourceUrl = provider == 'YOUTUBE'
        ? Uri.https('www.youtube.com', '/watch', {'v': mediaId}).toString()
        : parsed != null && const {'http', 'https'}.contains(parsed.scheme)
        ? mediaId
        : null;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MediaDiscoveryScreen(
          controller: controller,
          targetRoomId: controller.activeRoom?.id,
          initialProvider: provider,
          initialMediaId: mediaId,
          initialSourceUrl: sourceUrl,
        ),
      ),
    );
    controller.takeLastRoomSelection();
  }

  @override
  Widget build(BuildContext context) {
    final video = message.type == 'VIDEO';
    final thumbnail =
        video &&
            message.mediaProvider == 'YOUTUBE' &&
            (message.mediaId?.isNotEmpty ?? false)
        ? 'https://i.ytimg.com/vi/${Uri.encodeComponent(message.mediaId!)}/mqdefault.jpg'
        : null;
    final providerLabel = _providerName(message.mediaProvider ?? 'VIDEO');
    final currentVideo = controller.isCurrentTimelineVideo(message);
    return Center(
      child: GestureDetector(
        onTap: video ? () => _openVideo(context) : null,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 330),
          margin: const EdgeInsets.only(bottom: 9),
          padding: EdgeInsets.symmetric(
            horizontal: video ? 13 : 10,
            vertical: video ? 10 : 6,
          ),
          decoration: BoxDecoration(
            color: video ? const Color(0x88202638) : const Color(0x44191B25),
            borderRadius: BorderRadius.circular(video ? 14 : 20),
            border: Border.all(
              color: video ? const Color(0x446F63FF) : const Color(0x22FFFFFF),
            ),
          ),
          child: Row(
            mainAxisSize: video ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (video)
                SizedBox(
                  width: 92,
                  height: 58,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: thumbnail == null
                              ? const ColoredBox(
                                  color: Color(0xFF34304A),
                                  child: Icon(
                                    Icons.play_circle_fill_rounded,
                                    color: AppColors.lime,
                                    size: 28,
                                  ),
                                )
                              : Image.network(
                                  thumbnail,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const ColoredBox(
                                        color: Color(0xFF34304A),
                                        child: Icon(
                                          Icons.play_circle_fill_rounded,
                                          color: AppColors.lime,
                                          size: 28,
                                        ),
                                      ),
                                ),
                        ),
                      ),
                      Positioned(
                        right: -5,
                        bottom: -5,
                        child: CircleAvatar(
                          radius: 13,
                          backgroundColor: const Color(0xFF181923),
                          child: CircleAvatar(
                            radius: 11,
                            backgroundColor: const Color(0xFF7B4DFF),
                            backgroundImage:
                                message.avatarUrl?.isNotEmpty == true
                                ? NetworkImage(message.avatarUrl!)
                                : null,
                            child: message.avatarUrl?.isNotEmpty == true
                                ? null
                                : Text(
                                    message.senderName.substring(0, 1),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Icon(
                  message.type == 'JOIN'
                      ? Icons.login_rounded
                      : Icons.logout_rounded,
                  size: 14,
                  color: AppColors.muted,
                ),
              const SizedBox(width: 7),
              Flexible(
                child: video
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${currentVideo ? 'Now playing' : 'Played'} · $providerLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white60,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            message.mediaTitle ?? 'a video',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 6,
                            runSpacing: 5,
                            children: [
                              _TimelineAction(
                                icon: controller.isTimelineVideoLiked(message)
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                label: controller.isTimelineVideoLiked(message)
                                    ? 'Liked'
                                    : 'Like',
                                active: controller.isTimelineVideoLiked(
                                  message,
                                ),
                                onTap: () =>
                                    controller.toggleTimelineVideoLike(message),
                              ),
                              if (currentVideo)
                                _TimelineAction(
                                  icon: Icons.skip_next_rounded,
                                  label: controller.canControlWatch
                                      ? 'Skip'
                                      : 'Vote skip',
                                  onTap: () =>
                                      controller.skipTimelineVideo(message),
                                ),
                            ],
                          ),
                        ],
                      )
                    : Text(
                        '${message.senderName} ${message.body}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineAction extends StatelessWidget {
  const _TimelineAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: active ? const Color(0x556F3D78) : const Color(0x22111118),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? const Color(0x88FF78C8) : const Color(0x22FFFFFF),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: active ? Colors.pinkAccent : Colors.white70,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.onReply,
    required this.onReact,
    required this.onMore,
  });

  final ChatMessage message;
  final VoidCallback onReply;
  final ValueChanged<String> onReact;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => Align(
    alignment: message.isMine ? Alignment.centerRight : Alignment.centerLeft,
    child: GestureDetector(
      onLongPress: onMore,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > 280) {
          HapticFeedback.selectionClick();
          onReply();
        } else if (velocity < -280) {
          HapticFeedback.selectionClick();
          onMore();
        }
      },
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: message.isMine
              ? const Color(0xA663347E)
              : const Color(0x780B0C14),
          borderRadius: BorderRadius.circular(15).copyWith(
            bottomRight: message.isMine ? const Radius.circular(4) : null,
            bottomLeft: message.isMine ? null : const Radius.circular(4),
          ),
          border: Border.all(
            color: message.isMine
                ? const Color(0x52EF76C8)
                : const Color(0x24FFFFFF),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!message.isMine)
              Text(
                message.senderName,
                style: const TextStyle(
                  color: Color(0xFFFF8AD2),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            if (message.replyTo case final reply?) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0x33111118),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '${reply.senderName}: ${reply.body}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.white60),
                ),
              ),
              const SizedBox(height: 5),
            ],
            _MentionText(message.body),
            const SizedBox(height: 5),
            Wrap(
              spacing: 4,
              runSpacing: 3,
              children: [
                for (final reaction in message.reactions)
                  InkWell(
                    onTap: () => onReact(reaction.reaction),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: reaction.reactedByMe
                            ? const Color(0x557B4DFF)
                            : const Color(0x22FFFFFF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: reaction.reactedByMe
                              ? const Color(0x887B4DFF)
                              : const Color(0x22FFFFFF),
                        ),
                      ),
                      child: Text(
                        '${reaction.reaction} ${reaction.count}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _MentionText extends StatelessWidget {
  const _MentionText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final matches = RegExp(r'@[A-Za-z0-9_.-]+').allMatches(text).toList();
    if (matches.isEmpty) return Text(text);
    final spans = <TextSpan>[];
    var offset = 0;
    for (final match in matches) {
      if (match.start > offset) {
        spans.add(TextSpan(text: text.substring(offset, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: const TextStyle(
            color: AppColors.mint,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
      offset = match.end;
    }
    if (offset < text.length) spans.add(TextSpan(text: text.substring(offset)));
    return Text.rich(TextSpan(children: spans));
  }
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel({required this.controller});

  final WatchPartyController controller;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
    children: [
      const _ShelfLabel('UP NEXT · VOTE'),
      for (final item in controller.roomQueue)
        _QueueRow(
          controller: controller,
          item: item,
          onTap: () => controller.selectQueueItem(item),
        ),
      if (controller.roomQueue.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'No room picks yet. Add a video to start the queue.',
            style: TextStyle(color: AppColors.muted),
          ),
        ),
      if (controller.personalQueue.isNotEmpty) ...[
        const SizedBox(height: 12),
        const _ShelfLabel('YOUR QUEUE'),
        for (var index = 0; index < controller.personalQueue.length; index++)
          _QueueRow(
            controller: controller,
            item: controller.personalQueue[index],
            subtitle: index == 0
                ? 'Voting now · ${controller.personalQueue[index].voteCount} picks'
                : 'Waiting · #${index + 1} in your queue',
            onTap: index == 0
                ? () => controller.selectQueueItem(
                    controller.personalQueue[index],
                  )
                : null,
          ),
      ],
      const SizedBox(height: 4),
      OutlinedButton.icon(
        onPressed: () => controller.setShelfOpen(true),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Find another video'),
      ),
    ],
  );
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.controller,
    required this.item,
    required this.onTap,
    this.subtitle,
  });

  final WatchPartyController controller;
  final QueueItem item;
  final VoidCallback? onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(vertical: 3),
    leading: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 72,
        height: 48,
        child: MediaPreview(
          mediaId: item.mediaId,
          provider: item.provider,
          thumbnailUrl: item.thumbnailUrl,
          contentLabel: item.title,
        ),
      ),
    ),
    title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      subtitle ?? '${item.addedByName} · ${item.voteCount} picks',
      style: const TextStyle(color: AppColors.muted, fontSize: 11),
    ),
    trailing: SizedBox(
      width: 70,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _QueuePickerAvatars(
            pickers: item.pickers,
            controller: controller,
            size: 24,
            maxVisible: 2,
          ),
          const SizedBox(width: 5),
          Icon(
            item.votedByMe
                ? Icons.how_to_vote_rounded
                : Icons.touch_app_rounded,
            color: item.votedByMe ? AppColors.lime : AppColors.muted,
          ),
        ],
      ),
    ),
  );
}

class _PeoplePanel extends StatefulWidget {
  const _PeoplePanel({required this.controller});

  final WatchPartyController controller;

  @override
  State<_PeoplePanel> createState() => _PeoplePanelState();
}

String _publicDisplayName(
  Map<String, dynamic> person, {
  String fallback = 'Member',
}) {
  final displayName = person['displayName']?.toString().trim() ?? '';
  if (displayName.isNotEmpty && !displayName.contains('@')) return displayName;
  final username = person['username']?.toString().trim() ?? '';
  if (username.isNotEmpty && !username.contains('@')) return username;
  return fallback;
}

String _publicHandle(
  Map<String, dynamic> person, {
  String fallback = 'member',
}) {
  final username = person['username']?.toString().trim() ?? '';
  if (username.isNotEmpty && !username.contains('@')) return username;
  final id = (person['id'] ?? person['userId'])?.toString() ?? '';
  return id.length >= 8 ? 'member-${id.substring(0, 8)}' : fallback;
}

class _PeoplePanelState extends State<_PeoplePanel> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> participants = const [];
  List<Map<String, dynamic>> friends = const [];
  final Set<String> inviting = <String>{};
  final Set<String> invited = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final room = widget.controller.activeRoom;
    if (room == null) return;
    if (mounted) setState(() => loading = true);
    try {
      final result = await Future.wait([
        widget.controller.api.liveParticipants(room.id),
        widget.controller.api.friends(),
      ]);
      if (!mounted) return;
      setState(() {
        participants = result[0];
        friends = result[1];
        error = null;
        loading = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        error = exception.toString();
        loading = false;
      });
    }
  }

  Future<void> _invite(Map<String, dynamic> friend) async {
    final room = widget.controller.activeRoom;
    final userId = (friend['id'] ?? friend['userId'])?.toString();
    if (room == null || userId == null || inviting.contains(userId)) return;
    setState(() => inviting.add(userId));
    try {
      await widget.controller.api.inviteUserToRoom(room.id, userId);
      if (!mounted) return;
      setState(() => invited.add(userId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Invite sent to ${friend['displayName'] ?? friend['username'] ?? 'friend'}',
          ),
        ),
      );
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(exception.toString())));
    } finally {
      if (mounted) setState(() => inviting.remove(userId));
    }
  }

  Widget _avatar(Map<String, dynamic> person) {
    final name = _publicDisplayName(person, fallback: '?');
    final avatarUrl = person['avatarUrl']?.toString();
    return CircleAvatar(
      backgroundColor: AppColors.panelSoft,
      foregroundImage: avatarUrl != null && avatarUrl.isNotEmpty
          ? NetworkImage(avatarUrl)
          : null,
      child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase()),
    );
  }

  Future<void> _openFullProfile(Map<String, dynamic> person) async {
    final userId = (person['userId'] ?? person['id'])?.toString() ?? '';
    if (userId.isEmpty) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          controller: widget.controller,
          userId: userId,
          summary: person,
        ),
      ),
    );
  }

  Future<void> _openProfile(Map<String, dynamic> person) async {
    final userId = (person['userId'] ?? person['id'])?.toString() ?? '';
    final isMe = userId == widget.controller.profile?.id;
    final isFriend = friends.any(
      (friend) => (friend['id'] ?? friend['userId'])?.toString() == userId,
    );
    var friendNow = isFriend;
    var canAdd = person['canAddVideos'] == true;
    var canShare = person['canShareScreen'] == true;
    var canView = person['canViewVideo'] == true;
    var accessRequested = person['videoAccessRequested'] == true;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _avatar(person),
                const SizedBox(height: 12),
                Text(
                  _publicDisplayName(person),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '@${_publicHandle(person)} · ${person['role'] ?? 'MEMBER'}',
                  style: const TextStyle(color: AppColors.muted),
                ),
                if (!isMe) ...[
                  const SizedBox(height: 18),
                  ListTile(
                    title: Text(
                      widget.controller.voice.isListeningTo(userId)
                          ? 'Mute for me'
                          : 'Listen again',
                    ),
                    leading: const Icon(Icons.hearing_rounded),
                    onTap: () async {
                      await widget.controller.voice.toggleListeningTo(userId);
                      if (context.mounted) Navigator.pop(sheetContext);
                    },
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      if (friendNow) {
                        await widget.controller.api.removeFriend(userId);
                      } else {
                        await widget.controller.api.sendFriendRequest(userId);
                      }
                      setSheetState(() => friendNow = !friendNow);
                      await _load();
                    },
                    icon: Icon(
                      friendNow
                          ? Icons.person_remove_rounded
                          : Icons.person_add_rounded,
                    ),
                    label: Text(friendNow ? 'Remove friend' : 'Add friend'),
                  ),
                ],
                if (widget.controller.canControlWatch && !isMe) ...[
                  const Divider(height: 28),
                  ListTile(
                    title: const Text('Microphone'),
                    subtitle: const Text(
                      'Mute now or ask the member to unmute',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) async {
                        final room = widget.controller.activeRoom;
                        if (room != null)
                          await widget.controller.api.hostMicAction(
                            room.id,
                            userId,
                            action,
                          );
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'MUTE',
                          child: Text('Mute microphone'),
                        ),
                        PopupMenuItem(
                          value: 'REQUEST_UNMUTE',
                          child: Text('Ask to unmute'),
                        ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    value: canShare,
                    title: Text(
                      person['screenShareRequested'] == true
                          ? 'Screen share requested'
                          : 'Can share screen',
                    ),
                    subtitle: const Text('Only the host grants screen sharing'),
                    onChanged: (value) async {
                      final room = widget.controller.activeRoom;
                      if (room == null) return;
                      await widget.controller.api.setScreenPermission(
                        room.id,
                        userId,
                        value,
                      );
                      setSheetState(() => canShare = value);
                      await _load();
                    },
                  ),
                  SwitchListTile(
                    value: canAdd,
                    title: const Text('Can add videos'),
                    subtitle: const Text('Allow provider and suggestion picks'),
                    onChanged: (value) async {
                      final room = widget.controller.activeRoom;
                      if (room == null) return;
                      await widget.controller.api.updateVideoPermission(
                        room.id,
                        userId,
                        value,
                      );
                      setSheetState(() => canAdd = value);
                    },
                  ),
                  const Divider(height: 18),
                  SwitchListTile(
                    value: canView,
                    title: Text(
                      accessRequested && !canView
                          ? 'Video access requested'
                          : 'Can view video',
                    ),
                    subtitle: Text(
                      canView
                          ? 'Revoke to hide the player and controls'
                          : 'Viewer must use their own provider login',
                    ),
                    secondary: accessRequested && !canView
                        ? const Icon(
                            Icons.notification_important_rounded,
                            color: Color(0xFFFF6B91),
                          )
                        : const Icon(Icons.lock_person_rounded),
                    onChanged: (value) async {
                      final room = widget.controller.activeRoom;
                      if (room == null) return;
                      await widget.controller.api.updateVideoAccess(
                        room.id,
                        userId,
                        value,
                      );
                      setSheetState(() {
                        canView = value;
                        accessRequested = false;
                      });
                      await _load();
                    },
                  ),
                ],
                if (!isMe &&
                    (widget.controller.activeRoom?.role == 'HOST' ||
                        (widget.controller.activeRoom?.role == 'CO_HOST' &&
                            person['role'] == 'MEMBER')))
                  TextButton.icon(
                    onPressed: () async {
                      final room = widget.controller.activeRoom;
                      if (room == null) return;
                      await widget.controller.api.kickRoomMember(
                        room.id,
                        userId,
                      );
                      if (context.mounted) Navigator.pop(sheetContext);
                      await _load();
                    },
                    icon: const Icon(Icons.person_remove_rounded),
                    label: const Text('Remove from room'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _participantTile(Map<String, dynamic> person) {
    final userId = (person['userId'] ?? person['id'])?.toString() ?? '';
    final canManage =
        (widget.controller.canControlWatch ||
            (widget.controller.activeRoom?.role == 'CO_HOST' &&
                person['role'] == 'MEMBER')) &&
        userId.isNotEmpty &&
        userId != widget.controller.profile?.id;
    return ListTile(
      onTap: () => _openFullProfile(person),
      contentPadding: const EdgeInsets.symmetric(horizontal: 2),
      leading: Semantics(
        button: true,
        label: 'Open ${_publicDisplayName(person)} profile',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _openFullProfile(person),
          child: _avatar(person),
        ),
      ),
      title: Text(_publicDisplayName(person)),
      subtitle: Text(
        person['role'] == 'HOST'
            ? 'Host'
            : person['videoAccessRequested'] == true
            ? 'Requests video access'
            : person['canViewVideo'] == true
            ? 'Video access granted'
            : 'Watching now',
        style: const TextStyle(color: AppColors.muted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, size: 9, color: AppColors.mint),
          const SizedBox(width: 4),
          IconButton(
            tooltip: canManage ? 'Manage member' : 'View profile',
            onPressed: () =>
                canManage ? _openProfile(person) : _openFullProfile(person),
            icon: Icon(
              canManage
                  ? Icons.manage_accounts_rounded
                  : Icons.chevron_right_rounded,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final participantIds = participants
        .map((person) => person['userId']?.toString())
        .whereType<String>()
        .toSet();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
        children: [
          Row(
            children: [
              const Icon(Icons.groups_rounded, color: AppColors.mint, size: 19),
              const SizedBox(width: 8),
              Text(
                'In this room · ${participants.length}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (participants.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No live participants found. Pull down to reconnect.',
                style: TextStyle(color: AppColors.muted),
              ),
            )
          else
            for (final person in participants) _participantTile(person),
          const Divider(height: 26, color: Color(0x25FFFFFF)),
          const Row(
            children: [
              Icon(
                Icons.person_add_alt_1_rounded,
                color: Colors.white,
                size: 19,
              ),
              SizedBox(width: 8),
              Text(
                'Invite friends',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      error!,
                      style: const TextStyle(color: Color(0xFFFFA0B8)),
                    ),
                  ),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          else if (friends.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Add friends first, then invite them straight into this room.',
                style: TextStyle(color: AppColors.muted),
              ),
            )
          else
            for (final friend in friends)
              Builder(
                builder: (context) {
                  final userId =
                      (friend['id'] ?? friend['userId'])?.toString() ?? '';
                  final alreadyHere = participantIds.contains(userId);
                  final wasInvited = invited.contains(userId);
                  final isInviting = inviting.contains(userId);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                    leading: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _avatar(friend),
                        if (friend['online'] == true)
                          Positioned(
                            right: -1,
                            bottom: -1,
                            child: Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: AppColors.mint,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.ink,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Text(_publicDisplayName(friend, fallback: 'Friend')),
                    subtitle: Text(
                      '@${_publicHandle(friend, fallback: 'friend')}',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    trailing: alreadyHere
                        ? const Text(
                            'IN ROOM',
                            style: TextStyle(
                              color: AppColors.mint,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          )
                        : FilledButton.tonalIcon(
                            onPressed: isInviting || wasInvited
                                ? null
                                : () => _invite(friend),
                            icon: isInviting
                                ? const SizedBox.square(
                                    dimension: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    wasInvited
                                        ? Icons.check_rounded
                                        : Icons.send_rounded,
                                    size: 16,
                                  ),
                            label: Text(wasInvited ? 'Sent' : 'Invite'),
                          ),
                  );
                },
              ),
        ],
      ),
    );
  }
}

class _ShelfMode extends StatefulWidget {
  const _ShelfMode({required this.controller, required this.player});

  final WatchPartyController controller;
  final Widget? player;

  @override
  State<_ShelfMode> createState() => _ShelfModeState();
}

class _ShelfModeState extends State<_ShelfMode> {
  final search = TextEditingController();
  List<VideoSuggestion> results = const [];
  bool searching = false;
  Timer? searchDebounce;

  @override
  void dispose() {
    searchDebounce?.cancel();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: MediaQuery.sizeOf(context).width * .43,
              child: Stack(
                children: [
                  _PlayerCard(player: widget.player, compact: true),
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => widget.controller.setShelfOpen(false),
                        child: const Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: EdgeInsets.all(7),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color(0xCC080B0D),
                                borderRadius: BorderRadius.all(
                                  Radius.circular(8),
                                ),
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                child: Text(
                                  'TAP TO RETURN',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 8,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ROOM PICKS',
                    style: TextStyle(
                      color: AppColors.lime,
                      fontSize: 10,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Queue &\nsuggestions',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${widget.controller.queue.length} waiting',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => widget.controller.setShelfOpen(false),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: TextField(
          controller: search,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          onChanged: _searchWhileTyping,
          decoration: InputDecoration(
            hintText: 'Search YouTube',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    onPressed: () => _search(search.text),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
          children: [
            if (widget.controller.roomQueue.isNotEmpty) ...[
              const _ShelfLabel('UP NEXT · VOTE'),
              for (final item in widget.controller.roomQueue)
                _QueueRow(
                  controller: widget.controller,
                  item: item,
                  onTap: () => widget.controller.selectQueueItem(item),
                ),
              const SizedBox(height: 8),
            ],
            if (widget.controller.personalQueue.length > 1) ...[
              const _ShelfLabel('YOUR QUEUE'),
              for (
                var index = 1;
                index < widget.controller.personalQueue.length;
                index++
              )
                _QueueRow(
                  controller: widget.controller,
                  item: widget.controller.personalQueue[index],
                  subtitle: 'Waiting · #${index + 1} in your queue',
                  onTap: null,
                ),
              const SizedBox(height: 8),
            ],
            _ShelfLabel(
              results.isEmpty
                  ? widget.controller.suggestionSectionTitle
                  : 'SEARCH RESULTS',
            ),
            for (final video
                in results.isEmpty ? widget.controller.suggestions : results)
              _SuggestionCard(video: video, onAdd: () => _add(video)),
            if (results.isEmpty && widget.controller.suggestions.isEmpty)
              Padding(
                padding: const EdgeInsets.all(28),
                child: Center(
                  child: Text(
                    widget.controller.suggestionEmptyMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Future<void> _search(String value) async {
    if (value.trim().length < 2) return;
    setState(() => searching = true);
    try {
      final found = await widget.controller.searchVideos(value);
      final blocked = <String>{
        if (widget.controller.watchState != null)
          widget.controller.watchState!.mediaId,
        ...widget.controller.queue.map((item) => item.mediaId),
      };
      if (mounted) {
        setState(
          () => results = found
              .where((item) => !blocked.contains(item.videoId))
              .toList(),
        );
      }
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  void _searchWhileTyping(String value) {
    searchDebounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      if (results.isNotEmpty) setState(() => results = const []);
      return;
    }
    searchDebounce = Timer(
      const Duration(milliseconds: 450),
      () => _search(query),
    );
  }

  Future<void> _add(VideoSuggestion video) async {
    await widget.controller.addSuggestion(video);
    if (mounted) {
      setState(
        () => results = results
            .where((item) => item.videoId != video.videoId)
            .toList(),
      );
    }
  }
}

class _ShelfLabel extends StatelessWidget {
  const _ShelfLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.muted,
        fontSize: 10,
        letterSpacing: 1.3,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.video, required this.onAdd});

  final VideoSuggestion video;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: const Color(0xCC111619),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: SizedBox(
            width: 104,
            height: 62,
            child: MediaPreview(
              mediaId: video.videoId,
              provider: video.provider,
              thumbnailUrl: video.thumbnailUrl,
              contentLabel: video.title,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                video.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                video.channelTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 10),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onAdd,
          style: IconButton.styleFrom(
            backgroundColor: const Color(0x337ACB5A),
            foregroundColor: AppColors.lime,
          ),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    ),
  );
}

class _PlaybackSettings extends StatelessWidget {
  const _PlaybackSettings({
    required this.controller,
    required this.qualities,
    required this.onQuality,
    required this.captionLanguages,
    required this.onCaption,
  });

  final WatchPartyController controller;
  final List<String> qualities;
  final ValueChanged<String> onQuality;
  final Map<String, String> captionLanguages;
  final ValueChanged<String> onCaption;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Playback settings',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 18),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.high_quality_rounded),
            title: const Text('Video quality'),
            subtitle: Text(
              qualities.isEmpty
                  ? 'Auto · source controlled'
                  : '${qualities.length} qualities available',
            ),
            trailing: DropdownButton<String>(
              value: controller.selectedQuality,
              underline: const SizedBox.shrink(),
              items: [
                const DropdownMenuItem(value: 'auto', child: Text('Auto')),
                for (final quality in qualities)
                  DropdownMenuItem(value: quality, child: Text(quality)),
              ],
              onChanged: (value) {
                if (value != null) onQuality(value);
              },
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.closed_caption_rounded),
            title: const Text('Captions'),
            subtitle: Text(
              controller.selectedCaption == 'off'
                  ? 'Off'
                  : controller.selectedCaption.toUpperCase(),
            ),
            trailing: DropdownButton<String>(
              value: controller.selectedCaption,
              underline: const SizedBox.shrink(),
              items: [
                const DropdownMenuItem(value: 'off', child: Text('Off')),
                for (final entry in captionLanguages.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) {
                if (value != null) onCaption(value);
              },
            ),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.spatial_audio_off_rounded),
            title: Text('Audio track'),
            subtitle: Text(
              'YouTube exposes audio tracks only when the video provides them.',
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Playback settings are local to this phone and do not change room synchronization.',
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop({this.imageUrl, this.video});

  final String? imageUrl;
  final Widget? video;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (video != null)
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix(_partyColorMatrix),
                child: Opacity(
                  opacity: .34,
                  child: Transform.scale(
                    scale: 1.18,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(width: 1280, height: 720, child: video),
                    ),
                  ),
                ),
              ),
            )
          else if (imageUrl != null)
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix(_partyColorMatrix),
                child: Opacity(
                  opacity: .3,
                  child: Transform.scale(
                    scale: 1.2,
                    child: Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-.8, -1),
                end: Alignment(.75, 1),
                colors: [
                  Color(0x9E5A174F),
                  Color(0x8A123F61),
                  Color(0xD5070A16),
                ],
              ),
            ),
          ),
          const _PartyGlow(
            alignment: Alignment(-.85, -.7),
            color: Color(0x66FF4FB8),
            size: 310,
          ),
          const _PartyGlow(
            alignment: Alignment(.9, -.35),
            color: Color(0x555E7BFF),
            size: 360,
          ),
          const _PartyGlow(
            alignment: Alignment(.2, 1),
            color: Color(0x4D24E2C1),
            size: 330,
          ),
        ],
      ),
    ),
  );
}

const _partyColorMatrix = <double>[
  1.55,
  -.25,
  -.2,
  0,
  10,
  -.18,
  1.5,
  -.18,
  0,
  2,
  -.18,
  -.22,
  1.62,
  0,
  12,
  0,
  0,
  0,
  1,
  0,
];

class _PartyGlow extends StatelessWidget {
  const _PartyGlow({
    required this.alignment,
    required this.color,
    required this.size,
  });

  final Alignment alignment;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, Colors.transparent]),
        ),
      ),
    ),
  );
}

String _time(double seconds) {
  if (!seconds.isFinite || seconds < 0) return '0:00';
  final total = seconds.floor();
  final minutes = (total ~/ 60) % 60;
  final clock = '$minutes:${(total % 60).toString().padLeft(2, '0')}';
  final hours = total ~/ 3600;
  return hours > 0 ? '$hours:${clock.padLeft(5, '0')}' : clock;
}
