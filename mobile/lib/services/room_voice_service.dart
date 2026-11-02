import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../core/app_config.dart';
import 'lets_cook_api.dart';

class RoomVoiceService extends ChangeNotifier {
  RoomVoiceService(this._api);

  final LetsCookApi _api;
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  String? _roomId;

  bool connected = false;
  bool microphoneEnabled = false;
  bool screenShareEnabled = false;
  bool speakerphoneEnabled = true;
  bool busy = false;
  String? error;

  Future<void> connect(String roomId) async {
    if (connected && _roomId == roomId) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await disconnect();
      debugPrint('RoomVoice: requesting credentials for $roomId');
      final credentials = await _api.mediaToken(roomId);
      final room = Room(
        roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true),
      );
      final listener = room.createListener()
        ..on<RoomDisconnectedEvent>((_) {
          connected = false;
          microphoneEnabled = false;
          screenShareEnabled = false;
          notifyListeners();
        });
      await room.connect(_publicMediaUrl(credentials.url), credentials.token);
      debugPrint('RoomVoice: connected to ${credentials.roomName}');
      _room = room;
      _listener = listener;
      _roomId = roomId;
      connected = true;
      await Hardware.instance.setSpeakerphoneOn(speakerphoneEnabled);
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
    if (!connected || _roomId != roomId) await connect(roomId);
    final participant = _room?.localParticipant;
    if (participant == null) {
      throw const ApiException('Voice room is not connected.');
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      final enabled = !microphoneEnabled;
      await participant.setMicrophoneEnabled(enabled);
      microphoneEnabled = enabled;
    } catch (exception) {
      error = _friendlyError(exception);
      rethrow;
    } finally {
      busy = false;
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
      await Hardware.instance.setSpeakerphoneOn(speakerphoneEnabled);
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
        var backgroundAllowed = await FlutterBackground.hasPermissions;
        if (!backgroundAllowed) {
          const androidConfig = FlutterBackgroundAndroidConfig(
            notificationTitle: "Let's Cook screen sharing",
            notificationText: 'Your room can see your screen.',
            notificationImportance: AndroidNotificationImportance.normal,
            notificationIcon: AndroidResource(
              name: 'ic_launcher',
              defType: 'mipmap',
            ),
          );
          backgroundAllowed = await FlutterBackground.initialize(
            androidConfig: androidConfig,
          );
        }
        if (!backgroundAllowed) {
          throw const ApiException(
            'Android did not allow the screen-sharing foreground service.',
          );
        }
        if (!FlutterBackground.isBackgroundExecutionEnabled) {
          await FlutterBackground.enableBackgroundExecution();
        }
      }
      await participant.setScreenShareEnabled(
        true,
        captureScreenAudio: true,
      );
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
