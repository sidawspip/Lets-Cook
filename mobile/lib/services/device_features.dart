import 'package:flutter/services.dart';

class DeviceFeatures {
  DeviceFeatures._();
  static const _channel = MethodChannel('xynk.in/device');
  static Future<void> Function(Map<String, dynamic>)? _notificationTapListener;
  static Future<void> Function(bool)? _pipModeListener;
  static bool _handlerInstalled = false;
  static Future<bool> requestNotifications() async =>
      await _channel.invokeMethod<bool>('requestNotifications') ?? false;
  static Future<bool> requestMicrophone() async =>
      await _channel.invokeMethod<bool>('requestMicrophone') ?? false;
  static Future<bool> notificationStatus() async =>
      await _channel.invokeMethod<bool>('notificationStatus') ?? false;
  static Future<bool> microphoneStatus() async =>
      await _channel.invokeMethod<bool>('microphoneStatus') ?? false;
  static Future<void> vibrateMention() =>
      _channel.invokeMethod('vibrateMention');
  static Future<bool> enterPip() async =>
      await _channel.invokeMethod<bool>('enterPip') ?? false;
  static Future<void> setPipAutoEnabled(bool enabled) =>
      _channel.invokeMethod('setPipAutoEnabled', {'enabled': enabled});
  static Future<bool> isPipSupported() async =>
      await _channel.invokeMethod<bool>('isPipSupported') ?? false;
  static Future<bool> isInPip() async =>
      await _channel.invokeMethod<bool>('isInPip') ?? false;
  static Future<Map<String, dynamic>?> launchPayload() async =>
      (await _channel.invokeMapMethod<String, dynamic>('getLaunchPayload'));
  static Future<void> showNotification({
    required String type,
    required String title,
    required String body,
    String? senderId,
    String? roomId,
  }) => _channel.invokeMethod('showNotification', {
    'type': type,
    'title': title,
    'body': body,
    'senderId': senderId ?? '',
    'roomId': roomId ?? '',
  });
  static void onNotificationTap(
    Future<void> Function(Map<String, dynamic>) listener,
  ) {
    _notificationTapListener = listener;
    _installHandler();
  }

  static void onPipModeChanged(Future<void> Function(bool)? listener) {
    _pipModeListener = listener;
    _installHandler();
  }

  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'notificationTap' && call.arguments is Map) {
        final listener = _notificationTapListener;
        if (listener != null) {
          await listener(Map<String, dynamic>.from(call.arguments as Map));
        }
      } else if (call.method == 'pipWillEnter') {
        await _pipModeListener?.call(true);
      } else if (call.method == 'pipModeChanged') {
        await _pipModeListener?.call(call.arguments == true);
      }
    });
  }
}
