import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../core/app_config.dart';
import 'lets_cook_api.dart';

class VoiceMember {
  const VoiceMember(this.identity, this.name, this.microphoneOn, this.speaking);

  final String identity;
  final String name;
  final bool microphoneOn;
  final bool speaking;
}

class RoomVoiceService extends ChangeNotifier {
  RoomVoiceService(this._api);

  final LetsCookApi _api;
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  String? _roomId;
  Set<String> _activeSpeakerIds = const {};
  final Set<String> _locallyMutedIds = {};
  bool isListeningTo(String identity) => !_locallyMutedIds.contains(identity);
  Future<void> toggleListeningTo(String identity) async {
    final participant = _room?.remoteParticipants.values.where((person) => person.identity == identity).firstOrNull;
    if (participant == null) return;
    final mute = !_locallyMutedIds.contains(identity);
    for (final publication in participant.audioTrackPublications) {
      if (publication.source == TrackSource.microphone) {
        if (mute) { await publication.unsubscribe(); } else { await publication.subscribe(); }
      }
    }
    if (mute) { _locallyMutedIds.add(identity); } else { _locallyMutedIds.remove(identity); }
    notifyListeners();
  }

  bool connected = false;
  bool microphoneEnabled = false;
  bool _microphoneTogglePending = false;
  bool screenShareEnabled = false;
  bool speakerphoneEnabled = true;
  bool busy = false;
  String? error;

  bool get localSpeaking =>
      _activeSpeakerIds.contains(_room?.localParticipant?.identity) ||
      _room?.localParticipant?.isSpeaking == true;

  String? get localIdentity => _room?.localParticipant?.identity;

  bool get localMicrophoneActive {
    final participant = _room?.localParticipant;
    return microphoneEnabled ||
        (participant?.audioTrackPublications.any(
              (publication) =>
                  publication.source == TrackSource.microphone &&
                  !publication.muted &&
                  publication.track != null,
            ) ??
            false);
  }

  RemoteVideoTrack? get remoteScreenTrack {
    final room = _room;
    if (!connected || room == null) return null;
    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.videoTrackPublications) {
        if (publication.source == TrackSource.screenShareVideo &&
            !publication.muted &&
            publication.track != null) {
          return publication.track;
        }
      }
    }
    return null;
  }

  VideoTrack? get screenTrack {
    final room = _room;
    if (!connected || room == null) return null;
    for (final publication
        in room.localParticipant?.videoTrackPublications ?? []) {
      if (publication.source == TrackSource.screenShareVideo &&
          !publication.muted &&
          publication.track != null) {
        return publication.track;
      }
    }
    return remoteScreenTrack;
  }

  List<VoiceMember> get members {
    final room = _room;
    if (room == null) return const [];
    final local = room.localParticipant;
    return [
      if (local != null)
        VoiceMember(
          local.identity,
          local.name.isNotEmpty ? local.name : 'You',
          localMicrophoneActive,
          localSpeaking,
        ),
      for (final participant in room.remoteParticipants.values)
        VoiceMember(
          participant.identity,
          participant.name.isNotEmpty ? participant.name : participant.identity,
          participant.audioTrackPublications.any(
            (publication) =>
                publication.source == TrackSource.microphone &&
                !publication.muted &&
                publication.track != null,
          ),
          _activeSpeakerIds.contains(participant.identity) ||
              participant.isSpeaking,
        ),
    ];
  }

  Future<void> connect(String roomId) async {
    if (connected && _roomId == roomId) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await disconnect();
      debugPrint('RoomVoice: requesting credentials for $roomId');
      final credentials = await _api.mediaToken(roomId);
      Future<(Room, EventsListener<RoomEvent>)> openRoom(bool relayOnly) async {
        final room = Room(
          roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
        );
        final listener = room.createListener()
          ..on<RoomDisconnectedEvent>((_) {
            connected = false;
            microphoneEnabled = false;
            screenShareEnabled = false;
            notifyListeners();
          })
          ..on<RoomReconnectedEvent>((_) => notifyListeners())
          ..on<ParticipantConnectedEvent>((_) => notifyListeners())
          ..on<ParticipantDisconnectedEvent>((_) => notifyListeners())
          ..on<TrackPublishedEvent>((_) => notifyListeners())
          ..on<TrackUnpublishedEvent>((_) => notifyListeners())
          ..on<TrackSubscribedEvent>((_) => notifyListeners())
          ..on<TrackUnsubscribedEvent>((_) => notifyListeners())
          ..on<TrackMutedEvent>((event) {
            if (event.participant is LocalParticipant &&
                event.publication.source == TrackSource.microphone) {
              microphoneEnabled = false;
            }
            notifyListeners();
          })
          ..on<TrackUnmutedEvent>((event) {
            if (event.participant is LocalParticipant &&
                event.publication.source == TrackSource.microphone) {
              microphoneEnabled = true;
            }
            notifyListeners();
          })
          ..on<LocalTrackPublishedEvent>((event) {
            if (event.publication.source == TrackSource.microphone) {
              microphoneEnabled = true;
            }
            notifyListeners();
          })
          ..on<LocalTrackUnpublishedEvent>((event) {
            if (event.publication.source == TrackSource.microphone) {
              microphoneEnabled = false;
            }
            notifyListeners();
          })
          ..on<ActiveSpeakersChangedEvent>((event) {
            _activeSpeakerIds = event.speakers
                .map((participant) => participant.identity)
                .toSet();
            notifyListeners();
          });
        try {
          await room.connect(
            _publicMediaUrl(credentials.url),
            credentials.token,
            connectOptions: relayOnly
                ? const ConnectOptions(
                    rtcConfiguration: RTCConfiguration(
                      iceTransportPolicy: RTCIceTransportPolicy.relay,
                    ),
                  )
                : const ConnectOptions(),
          );
          return (room, listener);
        } catch (_) {
          await listener.dispose();
          await room.dispose();
          rethrow;
        }
      }

      late final (Room, EventsListener<RoomEvent>) session;
      try {
        session = await openRoom(false);
      } catch (firstError) {
        if (!Platform.isAndroid ||
            !firstError.toString().contains('MediaConnectException')) {
          rethrow;
        }
        debugPrint('RoomVoice: retrying with LiveKit TURN relay');
        session = await openRoom(true);
      }
      final (room, listener) = session;
      debugPrint('RoomVoice: connected to ${credentials.roomName}');
      _room = room;
      _listener = listener;
      _roomId = roomId;
      connected = true;
      try {
        await Hardware.instance
            .setSpeakerphoneOn(speakerphoneEnabled)
            .timeout(const Duration(seconds: 2));
      } catch (exception) {
        debugPrint('RoomVoice: speaker route setup skipped: $exception');
      }
    } catch (exception) {
      debugPrint('RoomVoice: connection failed: $exception');
      error = _friendlyError(exception);
      await disconnect();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> toggleMicrophone(String roomId) async {
    if (_microphoneTogglePending) return;
    if (!connected || _roomId != roomId) await connect(roomId);
    final participant = _room?.localParticipant;
    if (participant == null) {
      throw const ApiException('Voice room is not connected.');
    }
    _microphoneTogglePending = true;
    busy = true;
    error = null;
    final previous = microphoneEnabled;
    final enabled = !previous;
    microphoneEnabled = enabled;
    notifyListeners();
    try {
      await participant
          .setMicrophoneEnabled(enabled)
          .timeout(const Duration(seconds: 12));
    } catch (exception) {
      microphoneEnabled = previous;
      error = _friendlyError(exception);
      rethrow;
    } finally {
      _microphoneTogglePending = false;
      busy = false;
      notifyListeners();
    }
  }

  Future<void> muteMicrophone(String roomId) async {
    if (microphoneEnabled) await toggleMicrophone(roomId);
  }

  Future<void> refreshPermissions(String roomId) async {
    if (!connected || _roomId != roomId) return;
    final restoreMicrophone = microphoneEnabled;
    await disconnect();
    await connect(roomId);
    if (restoreMicrophone) {
      await _room!.localParticipant!.setMicrophoneEnabled(true);
      microphoneEnabled = true;
      notifyListeners();
    }
  }

  Future<void> toggleSpeakerphone(String roomId) async {
    if (!connected || _roomId != roomId) await connect(roomId);
    busy = true;
    error = null;
    notifyListeners();
    try {
      speakerphoneEnabled = !speakerphoneEnabled;
      await Hardware.instance
          .setSpeakerphoneOn(speakerphoneEnabled)
          .timeout(const Duration(seconds: 2));
    } catch (exception) {
      error = _friendlyError(exception);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> toggleScreenShare(String roomId) async {
    if (!connected || _roomId != roomId) await connect(roomId);
    final participant = _room?.localParticipant;
    if (participant == null) {
      throw const ApiException('The LiveKit room is not connected.');
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (screenShareEnabled) {
        await participant.setScreenShareEnabled(false);
        screenShareEnabled = false;
        return;
      }
      if (Platform.isAndroid) {
        final captureAllowed = await Helper.requestCapturePermission();
        if (!captureAllowed) {
          throw const ApiException(
            'Screen capture was cancelled. Tap Share screen and approve Android’s prompt.',
          );
        }
        // A permission grant alone does not initialize the foreground service.
        // Initialize on every start, including after Android restores a grant.
        const androidConfig = FlutterBackgroundAndroidConfig(
          notificationTitle: "Xynk screen sharing",
          notificationText: 'Your room can see your screen.',
          notificationImportance: AndroidNotificationImportance.normal,
          notificationIcon: AndroidResource(
            name: 'ic_launcher',
            defType: 'mipmap',
          ),
        );
        final backgroundAllowed = await FlutterBackground.initialize(
          androidConfig: androidConfig,
        );
        if (!backgroundAllowed) {
          throw const ApiException(
            'Android did not allow the screen-sharing foreground service.',
          );
        }
        if (!FlutterBackground.isBackgroundExecutionEnabled) {
          await FlutterBackground.enableBackgroundExecution();
        }
      }
      await participant.setScreenShareEnabled(true, captureScreenAudio: true);
      screenShareEnabled = true;
    } catch (exception) {
      error = _friendlyError(exception, screenShare: true);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    final listener = _listener;
    final room = _room;
    _listener = null;
    _room = null;
    _roomId = null;
    _activeSpeakerIds = const {};
    connected = false;
    microphoneEnabled = false;
    screenShareEnabled = false;
    if (listener != null) await listener.dispose();
    if (room != null) await room.dispose();
  }

  String _publicMediaUrl(String configuredUrl) {
    final uri = Uri.parse(configuredUrl);
    if (uri.host != 'localhost' && uri.host != '127.0.0.1') {
      return configuredUrl;
    }
    final apiHost = Uri.parse(AppConfig.apiBaseUrl).host;
    return uri.replace(host: apiHost).toString();
  }

  String _friendlyError(Object exception, {bool screenShare = false}) {
    final message = exception.toString();
    if (exception is ApiException) return exception.message;
    if (screenShare && message.toLowerCase().contains('not allowed')) {
      return 'The host has not allowed screen sharing for this member.';
    }
    if (message.toLowerCase().contains('permission')) {
      return screenShare
          ? 'Screen capture permission was denied. Approve Android’s sharing prompt and try again.'
          : 'Microphone permission was denied. Allow it in Android settings and try again.';
    }
    return screenShare
        ? 'Could not start LiveKit screen sharing. Check the room permission and network.'
        : 'Could not connect to room voice. Check the LiveKit address and network.';
  }

  @override
  void dispose() {
    unawaited(disconnect());
    super.dispose();
  }
}
