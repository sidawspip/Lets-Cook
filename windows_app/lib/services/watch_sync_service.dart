import 'dart:convert';

import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../core/app_config.dart';
import '../models/models.dart';
import 'lets_cook_api.dart';

class WatchSyncService {
  WatchSyncService(this.api);
  final LetsCookApi api;
  StompClient? _client;
  String? _roomId;
  void Function(RoomWatchState state)? _listener;
  void Function()? _timelineListener;
  bool get connected => _client?.connected == true;

  Future<void> connect(
    String roomId,
    void Function(RoomWatchState) listener, {
    void Function()? onTimelineChanged,
  }) async {
    _listener = listener;
    _timelineListener = onTimelineChanged;
    if (_roomId == roomId && _client?.connected == true) return;
    disconnect();
    _roomId = roomId;
    final token = await api.accessToken();
    final base = Uri.parse(AppConfig.apiBaseUrl);
    final url = base
        .replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '/ws')
        .toString();
    _client = StompClient(
      config: StompConfig(
        url: url,
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
        reconnectDelay: const Duration(seconds: 2),
        heartbeatIncoming: const Duration(seconds: 10),
        heartbeatOutgoing: const Duration(seconds: 10),
        onConnect: (frame) {
          _client?.subscribe(
            destination: '/topic/rooms/$roomId/watch',
            callback: (frame) {
              final body = frame.body;
              if (body == null) return;
              final json = jsonDecode(body) as Map<String, dynamic>;
              final state = json['state'];
              if (state is Map<String, dynamic>) {
                _listener?.call(RoomWatchState.fromJson(state));
              }
            },
          );
          _client?.subscribe(
            destination: '/topic/rooms/$roomId/chat',
            callback: (_) => _timelineListener?.call(),
          );
        },
      ),
    );
    _client!.activate();
  }

  bool publish(
    String type,
    RoomWatchState state, {
    double? positionSeconds,
    double? playbackRate,
  }) {
    if (_client?.connected != true || _roomId == null) return false;
    _client!.send(
      destination: '/app/rooms/$_roomId/watch/command',
      body: jsonEncode({
        'commandId': _uuid(),
        'expectedRevision': state.revision,
        'type': type,
        'positionSeconds': positionSeconds,
        'playbackRate': playbackRate,
        'clientTime': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    return true;
  }

  void disconnect() {
    _client?.deactivate();
    _client = null;
    _roomId = null;
    _listener = null;
    _timelineListener = null;
  }

  String _uuid() {
    final now = DateTime.now().microsecondsSinceEpoch
        .toRadixString(16)
        .padLeft(12, '0');
    return '00000000-0000-4000-8000-${now.substring(now.length - 12)}';
  }
}
