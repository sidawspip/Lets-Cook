import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StoredSession {
  const StoredSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
}

class SessionStore {
  static const _accessKey = 'lc_access_token';
  static const _refreshKey = 'lc_refresh_token';
  static const _expiryKey = 'lc_token_expiry';
  static const _roomKey = 'lc_active_room';
  static const _secure = FlutterSecureStorage();

  Future<StoredSession?> readSession() async {
    final values = await Future.wait([
      _secure.read(key: _accessKey),
      _secure.read(key: _refreshKey),
      _secure.read(key: _expiryKey),
    ]);
    if (values.any((value) => value == null)) return null;
    final expiry = DateTime.tryParse(values[2]!);
    if (expiry == null) return null;
    return StoredSession(
      accessToken: values[0]!,
      refreshToken: values[1]!,
      expiresAt: expiry,
    );
  }

  Future<void> saveSession(StoredSession session) async {
    await Future.wait([
      _secure.write(key: _accessKey, value: session.accessToken),
      _secure.write(key: _refreshKey, value: session.refreshToken),
      _secure.write(
        key: _expiryKey,
        value: session.expiresAt.toIso8601String(),
      ),
    ]);
  }

  Future<void> clearSession() => _secure.deleteAll();

  Future<String?> readActiveRoomId() async =>
      (await SharedPreferences.getInstance()).getString(_roomKey);

  Future<void> saveActiveRoomId(String? roomId) async {
    final preferences = await SharedPreferences.getInstance();
    if (roomId == null) {
      await preferences.remove(_roomKey);
    } else {
      await preferences.setString(_roomKey, roomId);
    }
  }
}
