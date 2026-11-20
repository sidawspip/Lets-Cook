import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../models/models.dart';
import 'session_store.dart';

class ApiException implements Exception {
  const ApiException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class MediaToken {
  const MediaToken({
    required this.url,
    required this.token,
    required this.roomName,
    required this.canPublish,
  });

  final String url;
  final String token;
  final String roomName;
  final bool canPublish;

  factory MediaToken.fromJson(Map<String, dynamic> json) => MediaToken(
    url: json['url'] as String,
    token: json['token'] as String,
    roomName: json['roomName'] as String,
    canPublish: json['canPublish'] as bool? ?? false,
  );
}

class LetsCookApi {
  LetsCookApi(this._store, {http.Client? client})
    : _client = client ?? http.Client();

  final SessionStore _store;
  final http.Client _client;
  StoredSession? _session;
  Future<void>? _refreshInFlight;
  Timer? _sessionRefreshTimer;
  static const _networkTimeout = Duration(seconds: 12);

  bool get hasSession => _session != null;
  Future<String> accessToken() async {
    await _ensureFreshToken();
    return _session!.accessToken;
  }

  Future<bool> restoreSession() async {
    _session = await _store.readSession();
    if (_session == null) return false;
    try {
      await _ensureFreshToken();
      if (_session == null) return false;
      startSessionRefresh();
      return true;
    } on ApiException catch (exception) {
      if (exception.statusCode != 401) rethrow;
      await logout();
      return false;
    } catch (_) {
      // Do not erase a saved login during a temporary auth outage.
      startSessionRefresh();
      return true;
    }
  }

  void startSessionRefresh() {
    _sessionRefreshTimer?.cancel();
    if (_session == null) return;
    _sessionRefreshTimer = Timer.periodic(const Duration(minutes: 1), (
      _,
    ) async {
      try {
        await _ensureFreshToken();
      } catch (_) {
        // Retry at the next interval or authenticated request.
      }
    });
  }

  void dispose() {
    _sessionRefreshTimer?.cancel();
    _client.close();
  }

  Future<void> login(String username, String password) async {
    final response = await _client
        .post(
          Uri.parse(
            '${AppConfig.authBaseUrl}/realms/${AppConfig.realm}/protocol/openid-connect/token',
          ),
          headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'client_id': AppConfig.clientId,
            'grant_type': 'password',
            'username': username,
            'password': password,
            'scope': 'openid profile email offline_access',
          },
        )
        .timeout(_networkTimeout);
    if (response.statusCode != 200) {
      throw const ApiException(
        'Could not sign in. Check your username and password.',
      );
    }
    await _acceptTokenResponse(response);
    startSessionRefresh();
  }

  Future<void> loginWithIdentityProvider(String provider) =>
      _loginWithDesktopBrowser(provider);

  Future<void> logout() async {
    _sessionRefreshTimer?.cancel();
    _session = null;
    await _store.clearSession();
  }

  Future<void> _loginWithDesktopBrowser(String provider) async {
    final redirectUri = Uri.parse(AppConfig.desktopOauthRedirectUrl);
    HttpServer? callbackServer;
    try {
      callbackServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        redirectUri.port,
        shared: false,
      );
    } on SocketException {
      throw const ApiException(
        'Could not start the secure sign-in callback. Close another Xynk window and try again.',
      );
    }

    final verifier = _oauthRandom(64);
    final challenge = base64Url
        .encode(sha256.convert(utf8.encode(verifier)).bytes)
        .replaceAll('=', '');
    final state = _oauthRandom(32);
    final authorizationUri =
        Uri.parse(
          '${AppConfig.authBaseUrl}/realms/${AppConfig.realm}/protocol/openid-connect/auth',
        ).replace(
          queryParameters: {
            'client_id': AppConfig.clientId,
            'redirect_uri': redirectUri.toString(),
            'response_type': 'code',
            'scope': 'openid profile email offline_access',
            'code_challenge': challenge,
            'code_challenge_method': 'S256',
            'state': state,
            'kc_idp_hint': provider,
          },
        );

    try {
      final opened = await launchUrl(
        authorizationUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw const ApiException('Could not open the browser for sign-in.');
      }
      final request = await callbackServer.first.timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw const ApiException(
          'Sign-in timed out. Return to Xynk and try again.',
        ),
      );
      final callback = request.uri;
      final callbackState = callback.queryParameters['state'];
      final error = callback.queryParameters['error'];
      final code = callback.queryParameters['code'];
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(
          '<!doctype html><meta charset="utf-8"><title>Xynk</title>'
          '<style>body{background:#080914;color:#fff;font:18px system-ui;display:grid;place-items:center;height:100vh;margin:0}main{text-align:center}b{color:#ee8cff}</style>'
          '<main><h1>Sign-in complete</h1><p>You can close this window and return to <b>Xynk</b>.</p></main>',
        );
      await request.response.close();
      if (callbackState != state) {
        throw const ApiException('The sign-in response could not be verified.');
      }
      if (error != null) {
        throw ApiException(
          callback.queryParameters['error_description'] ??
              'The identity provider cancelled sign-in.',
        );
      }
      if (code == null || code.isEmpty) {
        throw const ApiException(
          'The identity provider returned no login code.',
        );
      }
      final response = await _client
          .post(
            Uri.parse(
              '${AppConfig.authBaseUrl}/realms/${AppConfig.realm}/protocol/openid-connect/token',
            ),
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {
              'client_id': AppConfig.clientId,
              'grant_type': 'authorization_code',
              'code': code,
              'redirect_uri': redirectUri.toString(),
              'code_verifier': verifier,
            },
          )
          .timeout(_networkTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw ApiException(
          'Could not complete browser sign-in (${response.statusCode}).',
          response.statusCode,
        );
      }
      await _acceptTokenResponse(response);
      startSessionRefresh();
    } finally {
      await callbackServer.close(force: true);
    }
  }

  static String _oauthRandom(int length) {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  Future<Profile> profile() async => Profile.fromJson(
    await _jsonRequest('GET', '/me/profile') as Map<String, dynamic>,
  );

  Future<Map<String, dynamic>> profileDashboard() async =>
      await _jsonRequest('GET', '/me/profile/dashboard')
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> publicProfile(String userId) async =>
      await _jsonRequest(
            'GET',
            '/me/profile/view/${Uri.encodeComponent(userId)}',
          )
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateProfilePreferences(
    Map<String, dynamic> preferences,
  ) async =>
      await _jsonRequest('PATCH', '/me/profile/preferences', body: preferences)
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateProfileVisibility(
    Map<String, dynamic> visibility,
  ) async =>
      await _jsonRequest('PATCH', '/me/profile/visibility', body: visibility)
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> mediaDashboard() async =>
      await _jsonRequest('GET', '/me/media') as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> friends() async =>
      (await _jsonRequest('GET', '/social/friends') as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> friendRequests() async =>
      (await _jsonRequest('GET', '/social/friend-requests') as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<void> sendFriendRequest(String userId) => _jsonRequest(
    'POST',
    '/social/friend-requests/${Uri.encodeComponent(userId)}',
  );

  Future<void> removeFriend(String userId) =>
      _jsonRequest('DELETE', '/social/friends/${Uri.encodeComponent(userId)}');

  Future<void> decideFriendRequest(
    String requestId,
    bool accept,
  ) => _jsonRequest(
    'POST',
    '/social/friend-requests/${Uri.encodeComponent(requestId)}/${accept ? 'accept' : 'reject'}',
  );

  Future<List<Map<String, dynamic>>> blockedPeople() async =>
      (await _jsonRequest('GET', '/social/blocked') as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<void> blockUser(String userId) =>
      _jsonRequest('POST', '/social/blocks/${Uri.encodeComponent(userId)}');

  Future<void> unblockUser(String userId) =>
      _jsonRequest('DELETE', '/social/blocks/${Uri.encodeComponent(userId)}');

  Future<List<DirectMessage>> directMessages(String friendId) async {
    final data =
        await _jsonRequest(
              'GET',
              '/social/messages/${Uri.encodeComponent(friendId)}',
            )
            as List<dynamic>;
    return data
        .map(
          (message) => DirectMessage.fromJson(message as Map<String, dynamic>),
        )
        .toList();
  }

  Future<DirectMessage> sendDirectMessage(String friendId, String body) async =>
      DirectMessage.fromJson(
        await _jsonRequest(
              'POST',
              '/social/messages/${Uri.encodeComponent(friendId)}',
              body: {'body': body},
            )
            as Map<String, dynamic>,
      );

  Future<DirectMessage> sendDirectAttachment({
    required String friendId,
    required String filePath,
    required String fileName,
    required String kind,
  }) async {
    await _ensureFreshToken();
    Future<http.Response> upload() async {
      final request =
          http.MultipartRequest(
              'POST',
              Uri.parse(
                '${AppConfig.apiBaseUrl}/social/messages/${Uri.encodeComponent(friendId)}/attachments',
              ),
            )
            ..headers['Authorization'] = 'Bearer ${_session!.accessToken}'
            ..fields['kind'] = kind
            ..files.add(
              await http.MultipartFile.fromPath(
                'file',
                filePath,
                filename: fileName,
              ),
            );
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 60));
      return http.Response.fromStream(
        streamed,
      ).timeout(const Duration(seconds: 60));
    }

    var response = await upload();
    if (response.statusCode == 401) {
      await _refreshToken(force: true);
      response = await upload();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? message;
      try {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        message = (json['detail'] ?? json['message'] ?? json['error'])
            ?.toString();
      } catch (_) {}
      throw ApiException(
        message?.isNotEmpty == true
            ? message!
            : 'Attachment upload failed (${response.statusCode}).',
        response.statusCode,
      );
    }
    return DirectMessage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<Map<String, dynamic>> recordMedia({
    required String mediaId,
    required String provider,
    required String title,
    String? thumbnailUrl,
    String? sourceUrl,
    String? sourceType,
    int watchSeconds = 0,
  }) async =>
      await _jsonRequest(
            'POST',
            '/me/media/history',
            body: {
              'mediaId': mediaId,
              'provider': provider,
              'title': title,
              'thumbnailUrl': thumbnailUrl,
              'sourceUrl': sourceUrl,
              'sourceType': sourceType,
              'watchSeconds': watchSeconds,
            },
          )
          as Map<String, dynamic>;

  Future<void> removeHistory(String mediaId) => _jsonRequest(
    'DELETE',
    '/me/media/history?mediaId=${Uri.encodeQueryComponent(mediaId)}',
  );

  Future<void> setMediaLike(String mediaId, bool enabled) => _jsonRequest(
    'PUT',
    '/me/media/like',
    body: {'mediaId': mediaId, 'enabled': enabled},
  );

  Future<void> setMediaGallery(String mediaId, bool enabled) => _jsonRequest(
    'PUT',
    '/me/media/gallery',
    body: {'mediaId': mediaId, 'enabled': enabled},
  );

  Future<void> updateMediaSettings(bool hideSensitiveContent) => _jsonRequest(
    'PATCH',
    '/me/media/settings',
    body: {'hideSensitiveContent': hideSensitiveContent},
  );

  Future<List<PartyRoom>> publicRooms() async {
    final data =
        await _jsonRequest('GET', '/rooms/public-live') as List<dynamic>;
    return data
        .map((json) => PartyRoom.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<PartyRoom>> myRooms() async {
    final data = await _jsonRequest('GET', '/rooms') as List<dynamic>;
    return data
        .map((json) => PartyRoom.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<PartyRoom> createRoom(String name) async {
    final data =
        await _jsonRequest(
              'POST',
              '/rooms',
              body: {
                'name': name,
                'description': "A Xynk watch party",
                'accessPolicy': 'OPEN',
                'approvalRequired': false,
                'maxMembers': 50,
                'visibility': 'PUBLIC',
                'ephemeral': true,
              },
            )
            as Map<String, dynamic>;
    final room = PartyRoom.fromJson({
      ...data['room'] as Map<String, dynamic>,
      'joined': true,
    });
    // New watch parties are collaborative by default. Hosts can tighten this
    // to selected people or host-only from Room controls.
    await updateWatchSettings(room.id, mode: 'VOTE');
    return room;
  }

  Future<void> unlockRoom(String roomId, {String accessKey = ''}) async {
    await _jsonRequest(
      'POST',
      '/rooms/$roomId/unlock',
      body: {'accessKey': accessKey.trim()},
    );
  }

  Future<void> joinLiveRoom(String roomId) async {
    await _jsonRequest('POST', '/rooms/$roomId/live/join', body: const {});
  }

  Future<void> heartbeatLiveRoom(String roomId) async {
    await _jsonRequest('POST', '/rooms/$roomId/live/heartbeat', body: const {});
  }

  Future<void> leaveLiveRoom(String roomId) async {
    await _jsonRequest('DELETE', '/rooms/$roomId/live/leave');
  }

  Future<MediaToken> mediaToken(String roomId) async => MediaToken.fromJson(
    await _jsonRequest('POST', '/rooms/$roomId/media-token', body: const {})
        as Map<String, dynamic>,
  );

  Future<void> requestScreenShare(String roomId) async {
    await _jsonRequest(
      'POST',
      '/rooms/$roomId/screen-share-request',
      body: const {},
    );
  }

  Future<void> setScreenPermission(
    String roomId,
    String userId,
    bool allowed,
  ) async {
    await _jsonRequest(
      'POST',
      '/rooms/$roomId/members/${Uri.encodeComponent(userId)}/screen-permission',
      body: {'allowed': allowed},
    );
  }

  Future<void> hostMicAction(
    String roomId,
    String userId,
    String action,
  ) async {
    await _jsonRequest(
      'POST',
      '/rooms/$roomId/members/${Uri.encodeComponent(userId)}/microphone-action',
      body: {'action': action},
    );
  }

  Future<void> kickRoomMember(String roomId, String userId) async {
    await _jsonRequest(
      'DELETE',
      '/rooms/$roomId/members/${Uri.encodeComponent(userId)}',
    );
  }

  Future<List<Map<String, dynamic>>> liveParticipants(String roomId) async =>
      (await _jsonRequest('GET', '/rooms/$roomId/live/participants')
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> recentRoomPeople(String roomId) async =>
      (await _jsonRequest(
                'GET',
                '/rooms/${Uri.encodeComponent(roomId)}/live/recent-people',
              )
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<void> inviteUserToRoom(String roomId, String userId) async {
    await _jsonRequest(
      'POST',
      '/rooms/${Uri.encodeComponent(roomId)}/invite-user/${Uri.encodeComponent(userId)}',
      body: const {},
    );
  }

  Future<void> updateRoomAudience(
    String roomId, {
    required String visibility,
    required String accessPolicy,
  }) async {
    await _jsonRequest(
      'PATCH',
      '/rooms/${Uri.encodeComponent(roomId)}/settings',
      body: {
        'visibility': visibility,
        'accessPolicy': accessPolicy,
        'approvalRequired': false,
      },
    );
  }

  Future<RoomWatchState?> watchState(String roomId) async {
    final data = await _jsonRequest('GET', '/rooms/$roomId/watch');
    if (data == null) return null;
    return RoomWatchState.fromJson(data as Map<String, dynamic>);
  }

  Future<List<QueueItem>> watchQueue(String roomId) async {
    final data =
        await _jsonRequest('GET', '/rooms/$roomId/watch/queue')
            as Map<String, dynamic>;
    return (data['items'] as List<dynamic>? ?? const [])
        .map((json) => QueueItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> watchQueueInfo(String roomId) async =>
      await _jsonRequest('GET', '/rooms/$roomId/watch/queue')
          as Map<String, dynamic>;

  Future<void> updateWatchSettings(
    String roomId, {
    required String mode,
    int transitionSeconds = 8,
  }) => _jsonRequest(
    'PATCH',
    '/rooms/$roomId/watch/settings',
    body: {'mode': mode, 'transitionSeconds': transitionSeconds},
  );

  Future<void> updateVideoPermission(
    String roomId,
    String userId,
    bool allowed,
  ) => _jsonRequest(
    'POST',
    '/rooms/$roomId/members/${Uri.encodeComponent(userId)}/video-permission',
    body: {'allowed': allowed},
  );

  Future<void> requestVideoAccess(String roomId) => _jsonRequest(
    'POST',
    '/rooms/$roomId/watch/access-request',
    body: const {},
  );

  Future<void> updateVideoAccess(String roomId, String userId, bool allowed) =>
      _jsonRequest(
        'POST',
        '/rooms/$roomId/members/${Uri.encodeComponent(userId)}/video-access',
        body: {'allowed': allowed},
      );

  Future<List<ChatMessage>> roomChat(String roomId, String myId) async {
    final data =
        await _jsonRequest('GET', '/rooms/$roomId/live/messages')
            as List<dynamic>;
    return data
        .map((json) => ChatMessage.fromJson(json as Map<String, dynamic>, myId))
        .toList();
  }

  Future<ChatMessage> sendRoomChat(
    String roomId,
    String body,
    String myId, {
    String? replyToId,
  }) async {
    final data =
        await _jsonRequest(
              'POST',
              '/rooms/$roomId/live/messages',
              body: {'body': body, 'replyToId': replyToId},
            )
            as Map<String, dynamic>;
    return ChatMessage.fromJson(data, myId);
  }

  Future<ChatMessage> shareRoomVideo(
    String roomId,
    String myId, {
    required String provider,
    required String mediaId,
    required String title,
  }) async {
    final data =
        await _jsonRequest(
              'POST',
              '/rooms/$roomId/live/messages/video',
              body: {'provider': provider, 'mediaId': mediaId, 'title': title},
            )
            as Map<String, dynamic>;
    return ChatMessage.fromJson(data, myId);
  }

  Future<ChatMessage> reactToRoomMessage(
    String roomId,
    String messageId,
    String reaction,
    String myId,
  ) async {
    final data =
        await _jsonRequest(
              'POST',
              '/rooms/$roomId/live/messages/$messageId/reactions',
              body: {'reaction': reaction},
            )
            as Map<String, dynamic>;
    return ChatMessage.fromJson(data, myId);
  }

  Future<List<VideoSuggestion>> searchYoutube(String query) async {
    final data =
        await _jsonRequest(
              'GET',
              '/youtube/search?q=${Uri.encodeQueryComponent(query)}',
            )
            as Map<String, dynamic>;
    return (data['results'] as List<dynamic>? ?? const [])
        .map((json) => VideoSuggestion.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> resolveWebMedia(String pageUrl) async =>
      await _jsonRequest(
            'POST',
            '/media/resolve-web',
            body: {'pageUrl': pageUrl},
          )
          as Map<String, dynamic>;

  Future<QueueItem> addToQueue(
    String roomId,
    VideoSuggestion video, {
    bool personalQueueItem = true,
  }) async {
    final data =
        await _jsonRequest(
              'POST',
              '/rooms/$roomId/watch/queue',
              body: {
                'provider': video.provider,
                'mediaId': video.videoId,
                'title': video.title,
                'thumbnailUrl': video.thumbnailUrl,
                'personalQueueItem': personalQueueItem,
              },
            )
            as Map<String, dynamic>;
    return QueueItem.fromJson(data);
  }

  Future<QueueItem> addDirectToQueue(
    String roomId,
    String provider,
    String mediaId, {
    String? sourceUrl,
    String? title,
    String? thumbnailUrl,
  }) async {
    final playableUrl = sourceUrl?.trim().isNotEmpty == true
        ? sourceUrl!.trim()
        : mediaId;
    final data =
        await _jsonRequest(
              'POST',
              '/rooms/$roomId/watch/queue',
              body: {
                'provider': provider,
                'mediaId': mediaId,
                'sourceUrl': playableUrl,
                'title': title?.trim().isNotEmpty == true
                    ? title!.trim()
                    : Uri.parse(playableUrl).pathSegments.isEmpty
                    ? 'Direct video'
                    : Uri.parse(playableUrl).pathSegments.last,
                'thumbnailUrl': thumbnailUrl,
              },
            )
            as Map<String, dynamic>;
    return QueueItem.fromJson(data);
  }

  Future<QueueItem> addProviderToQueue(
    String roomId, {
    required String provider,
    required String mediaId,
    required String title,
    String? thumbnailUrl,
  }) async {
    final data =
        await _jsonRequest(
              'POST',
              '/rooms/$roomId/watch/queue',
              body: {
                'provider': provider,
                'mediaId': mediaId,
                'title': title,
                'thumbnailUrl': thumbnailUrl,
              },
            )
            as Map<String, dynamic>;
    return QueueItem.fromJson(data);
  }

  Future<RoomWatchState> playQueueItem(String roomId, String queueId) async {
    final data =
        await _jsonRequest(
              'POST',
              '/rooms/$roomId/watch/queue/next',
              body: {'queueId': queueId},
            )
            as Map<String, dynamic>;
    return RoomWatchState.fromJson(data);
  }

  Future<RoomWatchState> playHighestVoted(String roomId) async {
    final data =
        await _jsonRequest('POST', '/rooms/$roomId/watch/queue/next')
            as Map<String, dynamic>;
    return RoomWatchState.fromJson(data);
  }

  Future<List<QueueItem>> voteQueueItem(String roomId, String queueId) async {
    final response =
        await _jsonRequest('POST', '/rooms/$roomId/watch/queue/$queueId/vote')
            as Map<String, dynamic>;
    return (response['items'] as List<dynamic>? ?? const [])
        .map((json) => QueueItem.fromJson(json as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> voteToSkip(String roomId) async =>
      await _jsonRequest('POST', '/rooms/$roomId/watch/skip-vote')
          as Map<String, dynamic>;

  Future<void> updateWatch(String roomId, RoomWatchState state) async {
    await _jsonRequest(
      'PUT',
      '/rooms/$roomId/watch',
      body: {
        'provider': state.provider,
        'sourceType': state.sourceType,
        'sourceUrl': state.sourceUrl,
        'mediaId': state.mediaId,
        'title': state.title,
        'playing': state.playing,
        'positionSeconds': state.positionSeconds,
        'durationSeconds': state.durationSeconds,
        'playbackRate': 1.0,
      },
    );
  }

  Future<dynamic> _jsonRequest(
    String method,
    String path, {
    Object? body,
  }) async {
    await _ensureFreshToken();
    var response = await _sendJsonRequest(method, path, body);
    if (response.statusCode == 401) {
      await _refreshToken(force: true);
      response = await _sendJsonRequest(method, path, body);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? serverMessage;
      try {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        serverMessage = (error['detail'] ?? error['message'] ?? error['error'])
            ?.toString();
      } catch (_) {}
      throw ApiException(
        response.statusCode == 401
            ? 'Your session expired. Please sign in again.'
            : serverMessage?.isNotEmpty == true
            ? serverMessage!
            : 'Request failed (${response.statusCode}).',
        response.statusCode,
      );
    }
    if (response.body.trim().isEmpty) return null;
    return jsonDecode(response.body);
  }

  Future<http.Response> _sendJsonRequest(
    String method,
    String path,
    Object? body,
  ) async {
    final request = http.Request(
      method,
      Uri.parse('${AppConfig.apiBaseUrl}$path'),
    );
    request.headers.addAll({
      'Authorization': 'Bearer ${_session!.accessToken}',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    });
    if (body != null) request.body = jsonEncode(body);
    final streamed = await _client.send(request).timeout(_networkTimeout);
    return http.Response.fromStream(streamed).timeout(_networkTimeout);
  }

  Future<void> _ensureFreshToken() async {
    final session = _session;
    if (session == null) throw const ApiException('Please sign in first.', 401);
    if (session.expiresAt.isAfter(
      DateTime.now().add(const Duration(seconds: 45)),
    )) {
      return;
    }
    await _refreshToken();
  }

  Future<void> _refreshToken({bool force = false}) async {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final session = _session;
    if (session == null) throw const ApiException('Please sign in first.', 401);
    if (!force &&
        session.expiresAt.isAfter(
          DateTime.now().add(const Duration(seconds: 45)),
        )) {
      return;
    }
    final operation = _performTokenRefresh(session);
    _refreshInFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_refreshInFlight, operation)) _refreshInFlight = null;
    }
  }

  Future<void> _performTokenRefresh(StoredSession session) async {
    final response = await _client
        .post(
          Uri.parse(
            '${AppConfig.authBaseUrl}/realms/${AppConfig.realm}/protocol/openid-connect/token',
          ),
          headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'client_id': AppConfig.clientId,
            'grant_type': 'refresh_token',
            'refresh_token': session.refreshToken,
          },
        )
        .timeout(_networkTimeout);
    if (response.statusCode != 200) {
      throw const ApiException('Your session expired.', 401);
    }
    if (!identical(_session, session)) return;
    await _acceptTokenResponse(response);
  }

  Future<void> _acceptTokenResponse(http.Response response) async {
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    _session = StoredSession(
      accessToken: json['access_token'] as String,
      refreshToken:
          (json['refresh_token'] as String?) ?? _session?.refreshToken ?? '',
      expiresAt: DateTime.now().add(
        Duration(seconds: (json['expires_in'] as num? ?? 300).toInt()),
      ),
    );
    await _store.saveSession(_session!);
  }
}
