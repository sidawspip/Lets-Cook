import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DeviceFeatures {
  DeviceFeatures._();
  static const _channel = MethodChannel('letscook.world/device');
  static Future<void> Function(Map<String, dynamic>)? _notificationTapListener;
  static Future<void> Function(bool)? _pipModeListener;
  static bool _handlerInstalled = false;
  static bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;

  static Future<bool> requestNotifications() async =>
      _isWindows ? false : await _invokeBool('requestNotifications');
  static Future<bool> requestMicrophone() async =>
      _isWindows ? true : await _invokeBool('requestMicrophone');
  static Future<bool> notificationStatus() async =>
      _isWindows ? false : await _invokeBool('notificationStatus');
  static Future<bool> microphoneStatus() async =>
      _isWindows ? true : await _invokeBool('microphoneStatus');
  static Future<void> vibrateMention() async {
    if (!_isWindows) await _invokeVoid('vibrateMention');
  }

  static Future<bool> enterPip() async =>
      _isWindows ? false : await _invokeBool('enterPip');
  static Future<void> setPipAutoEnabled(bool enabled) async {
    if (!_isWindows) {
      await _invokeVoid('setPipAutoEnabled', {'enabled': enabled});
    }
  }

  static Future<bool> isPipSupported() async =>
      _isWindows ? false : await _invokeBool('isPipSupported');
  static Future<bool> isInPip() async =>
      _isWindows ? false : await _invokeBool('isInPip');
  static Future<Map<String, dynamic>?> launchPayload() async {
    if (_isWindows) return null;
    try {
      return await _channel.invokeMapMethod<String, dynamic>(
        'getLaunchPayload',
      );
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> showNotification({
    required String type,
    required String title,
    required String body,
    String? senderId,
    String? roomId,
  }) async {
    if (_isWindows) return;
    await _invokeVoid('showNotification', {
      'type': type,
      'title': title,
      'body': body,
      'senderId': senderId ?? '',
      'roomId': roomId ?? '',
    });
  }

  static Future<bool> _invokeBool(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> _invokeVoid(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Desktop support can be added without blocking the shared app flow.
    }
  }

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
