import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import '../core/app_config.dart';
import 'device_features.dart';
import 'lets_cook_api.dart';

class NotificationStreamService {
  NotificationStreamService(this.api);
  final LetsCookApi api;
  StompClient? _client;
  bool get connected => _client?.connected == true;

  Future<void> connect(
    Future<void> Function(Map<String, dynamic>) onEvent,
  ) async {
    if (_client?.connected == true) return;
    disconnect();
    final headers = <String, String>{};
    final base = Uri.parse(AppConfig.apiBaseUrl);
    _client = StompClient(
      config: StompConfig(
        url: base
            .replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '/ws')
            .toString(),
        stompConnectHeaders: headers,
        webSocketConnectHeaders: headers,
        beforeConnect: () async {
          headers['Authorization'] = 'Bearer ${await api.accessToken()}';
        },
        reconnectDelay: const Duration(seconds: 2),
        heartbeatIncoming: const Duration(seconds: 10),
        heartbeatOutgoing: const Duration(seconds: 10),
        connectionTimeout: const Duration(seconds: 10),
        onStompError: (frame) => debugPrint(
          'Notification STOMP error: ${frame.headers['message'] ?? frame.body}',
        ),
        onWebSocketError: (error) =>
            debugPrint('Notification WebSocket error: $error'),
        onWebSocketDone: () =>
            debugPrint('Notification WebSocket connection closed'),
        onConnect: (_) {
          debugPrint('Notification WebSocket connected');
          _client?.subscribe(
            destination: '/user/queue/notifications',
            callback: (frame) async {
              if (frame.body == null) return;
              final event = jsonDecode(frame.body!) as Map<String, dynamic>;
              await DeviceFeatures.showNotification(
                type: event['type']?.toString() ?? 'EVENT',
                title: event['type'] == 'ROOM_INVITE'
                    ? '${event['senderName']} invited you'
                    : event['type'] == 'ROOM_MENTION'
                    ? '${event['senderName']} mentioned you'
                    : 'Message from ${event['senderName']}',
                body: event['body']?.toString() ?? '',
                senderId: event['senderId']?.toString(),
                roomId: event['roomId']?.toString(),
              );
              await onEvent(event);
            },
          );
        },
      ),
    );
    _client!.activate();
  }

  void disconnect() {
    _client?.deactivate();
    _client = null;
  }
}
