import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lets_cook_windows/services/lets_cook_api.dart';
import 'package:lets_cook_windows/services/session_store.dart';

class _MemorySessionStore extends SessionStore {
  StoredSession? saved;
  int clears = 0;

  @override
  Future<StoredSession?> readSession() async => saved;

  @override
  Future<void> saveSession(StoredSession session) async {
    saved = session;
  }

  @override
  Future<void> clearSession() async {
    saved = null;
    clears++;
  }
}

void main() {
  final expired = StoredSession(
    accessToken: 'expired-access',
    refreshToken: 'saved-refresh',
    expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
  );

  test('local sign-in requests a durable offline refresh session', () async {
    final store = _MemorySessionStore();
    final api = LetsCookApi(
      store,
      client: MockClient((request) async {
        expect(request.bodyFields['scope'], contains('offline_access'));
        return http.Response(
          '{"access_token":"new-access","refresh_token":"new-refresh","expires_in":300}',
          200,
        );
      }),
    );
    addTearDown(api.dispose);

    await api.login('test', 'test');
    expect(store.saved?.refreshToken, 'new-refresh');
  });

  test('temporary auth outage preserves saved login for retry', () async {
    final store = _MemorySessionStore()..saved = expired;
    final api = LetsCookApi(
      store,
      client: MockClient((_) async {
        throw const SocketException('offline');
      }),
    );
    addTearDown(api.dispose);

    expect(await api.restoreSession(), isTrue);
    expect(store.clears, 0);
    expect(store.saved?.refreshToken, 'saved-refresh');
  });

  test('revoked refresh token clears invalid session', () async {
    final store = _MemorySessionStore()..saved = expired;
    final api = LetsCookApi(
      store,
      client: MockClient((_) async => http.Response('{}', 400)),
    );
    addTearDown(api.dispose);

    expect(await api.restoreSession(), isFalse);
    expect(store.clears, 1);
  });

  test('refresh finishing after logout cannot restore the old account', () async {
    final store = _MemorySessionStore()..saved = expired;
    final response = Completer<http.Response>();
    final requestStarted = Completer<void>();
    final api = LetsCookApi(
      store,
      client: MockClient((_) {
        requestStarted.complete();
        return response.future;
      }),
    );
    addTearDown(api.dispose);

    final restore = api.restoreSession();
    await requestStarted.future;
    await api.logout();
    response.complete(
      http.Response(
        '{"access_token":"old-access","refresh_token":"old-refresh","expires_in":300}',
        200,
      ),
    );
    await restore;
    expect(api.hasSession, isFalse);
    expect(store.saved, isNull);
  });
}
