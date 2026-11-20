import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/lets_cook_api.dart';
import '../services/session_store.dart';
import '../services/watch_sync_service.dart';
import '../services/notification_stream_service.dart';
import '../services/room_voice_service.dart';
import '../services/device_features.dart';

enum RoomPanel { chat, queue, people }

class ViewingActivity {
  const ViewingActivity({
    required this.mediaId,
    required this.title,
    required this.provider,
    required this.thumbnailUrl,
    required this.watchedAt,
    required this.sensitive,
    this.views = 1,
    this.sourceUrl,
    this.sourceType,
  });

  final String mediaId;
  final String title;
  final String provider;
  final String thumbnailUrl;
  final DateTime watchedAt;
  final bool sensitive;
  final int views;
  final String? sourceUrl;
  final String? sourceType;

  Map<String, dynamic> toJson() => {
    'mediaId': mediaId,
    'title': title,
    'provider': provider,
    'thumbnailUrl': thumbnailUrl,
    'watchedAt': watchedAt.toIso8601String(),
    'sensitive': sensitive,
    'views': views,
    'sourceUrl': sourceUrl,
    'sourceType': sourceType,
  };

  factory ViewingActivity.fromJson(
    Map<String, dynamic> json,
  ) => ViewingActivity(
    mediaId: json['mediaId'] as String,
    title: json['title'] as String,
    provider: (json['provider'] ?? 'WEB') as String,
    thumbnailUrl: (json['thumbnailUrl'] ?? '') as String,
    watchedAt:
        DateTime.tryParse(json['watchedAt'] as String? ?? '') ?? DateTime.now(),
    sensitive: (json['sensitive'] ?? false) as bool,
    views: (json['views'] as num? ?? json['playCount'] as num? ?? 1).toInt(),
    sourceUrl: json['sourceUrl'] as String?,
    sourceType: json['sourceType'] as String?,
  );
}

class WatchPartyController extends ChangeNotifier {
  WatchPartyController({SessionStore? store, LetsCookApi? api}) {
    this.store = store ?? SessionStore();
    this.api = api ?? LetsCookApi(this.store);
    watchSync = WatchSyncService(this.api);
    notificationStream = NotificationStreamService(this.api);
    voice = RoomVoiceService(this.api)..addListener(notifyListeners);
    DeviceFeatures.onNotificationTap(_handleNotificationTap);
  }

  late final SessionStore store;
  late final LetsCookApi api;
  late final WatchSyncService watchSync;
  late final NotificationStreamService notificationStream;
  late final RoomVoiceService voice;

  bool initializing = true;
  bool busy = false;
  String? error;
  Profile? profile;
  List<PartyRoom> rooms = const [];
  PartyRoom? activeRoom;
  List<Map<String, dynamic>> activeParticipants = const [];
  RoomWatchState? watchState;
  List<QueueItem> queue = const [];
  QueueItem? _lastRoomSelection;
  List<VideoSuggestion> suggestions = const [];
  String queueMode = 'HOSTS_ONLY';
  bool canAddToQueue = false;
  bool canViewVideo = false;
  bool checkingVideoAccess = false;
  bool videoAccessRequested = false;
  final Map<String, String> _resolvedMediaTitles = {};
  String? _resolvedWebSourcesPage;
  List<Map<String, dynamic>> _resolvedWebSources = const [];
  int _suggestionLoadRevision = 0;
  List<ChatMessage> messages = const [];
  ChatMessage? replyToMessage;
  RoomPanel panel = RoomPanel.chat;
  bool shelfOpen = false;
  bool muted = false;
  double volume = .82;
  String selectedQuality = 'auto';
  String selectedCaption = 'off';
  Timer? _refreshTimer;
  Timer? _heartbeatTimer;
  bool _refreshing = false;
  bool unmuteRequested = false;
  bool screenShareApproved = false;
  bool _refreshingTimeline = false;
  bool reconnecting = false;
  bool _resumeInFlight = false;
  String? pendingDirectMessageSenderId;
  final Set<String> unreadDirectMessageSenderIds = <String>{};
  DateTime? _watchReceivedAt;
  List<ViewingActivity> history = const [];
  List<ViewingActivity> gallery = const [];
  List<ViewingActivity> likedVideos = const [];
  Set<String> likedMediaIds = <String>{};
  bool hideSensitiveContent = true;
  int watchTogetherSeconds = 0;
  int friendCount = 0;
  bool hideLocation = false;
  bool restrictInvites = false;
  bool floatingVideo = true;
  bool muteOtherAudio = true;
  bool hapticFeedback = true;
  bool autoTranslate = false;
  final Set<String> savingProfilePreferences = <String>{};
  String preferredLanguage = 'en';
  String quickReaction = '❤️';
  List<String> profileInterests = const [];
  List<Map<String, dynamic>> profileConnections = const [];
  Map<String, String> profileVisibility = const {
    'bio': 'PUBLIC',
    'gallery': 'PUBLIC',
    'activity': 'FRIENDS',
    'stats': 'PUBLIC',
    'friends': 'FRIENDS',
    'interests': 'PUBLIC',
    'connections': 'PUBLIC',
  };

  double get synchronizedPosition {
    final state = watchState;
    if (state == null) return 0;
    final elapsed = state.playing && _watchReceivedAt != null
        ? DateTime.now().difference(_watchReceivedAt!).inMilliseconds / 1000
        : 0.0;
    return state.positionSeconds + elapsed;
  }

  bool get authenticated => api.hasSession;
  bool get canControlWatch => activeRoom?.role == 'HOST';
  bool get videoUnlocked =>
      canControlWatch || activeRoom?.role == 'CO_HOST' || canViewVideo;
  bool get notificationConnected => notificationStream.connected;
  bool get roomConnected => activeRoom == null || watchSync.connected;
  bool get fullyConnected => notificationConnected && roomConnected;
  String get displayName => profile?.displayName ?? 'Guest';
  List<QueueItem> get roomQueue {
    final heads = <String, QueueItem>{};
    for (final item in queue.where((item) => item.voteCount > 0)) {
      heads[item.id] = item;
    }
    final result = heads.values.toList(growable: false);
    result.sort((left, right) => right.voteCount.compareTo(left.voteCount));
    return result;
  }

  List<QueueItem> get personalQueue {
    final userId = profile?.id;
    if (userId == null) return const [];
    final result = queue
        .where((item) => item.addedBy == userId && item.personalQueueItem)
        .toList();
    result.sort(
      (left, right) => left.personalPosition.compareTo(right.personalPosition),
    );
    return result;
  }

  Future<void> setRoomQueueMode(String mode) async {
    final room = activeRoom;
    if (room == null || !canControlWatch) return;
    await api.updateWatchSettings(room.id, mode: mode);
    queueMode = mode;
    canAddToQueue = true;
    notifyListeners();
  }

  String? get currentThumbnail {
    final state = watchState;
    if (state == null) return activeRoom?.thumbnailUrl;
    final supplied = state.thumbnailUrl ?? activeRoom?.thumbnailUrl;
    if (supplied?.isNotEmpty == true) return supplied;
    return state.provider == 'YOUTUBE'
        ? 'https://i.ytimg.com/vi/${state.mediaId}/hqdefault.jpg'
        : null;
  }

  Future<void> initialize() async {
    try {
      if (await api.restoreSession()) await _loadAuthenticatedHome();
    } catch (exception) {
      error = exception.toString();
    } finally {
      initializing = false;
      notifyListeners();
    }
  }

  Future<void> login(String username, String password) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await api.login(username.trim(), password);
      await _loadAuthenticatedHome();
    } catch (exception) {
      error = exception.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> loginWithIdentityProvider(String provider) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await api.loginWithIdentityProvider(provider);
      await _loadAuthenticatedHome();
    } catch (exception) {
      error = exception.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> createParty({String? roomName}) async {
    busy = true;
    notifyListeners();
    try {
      final room = await api.createRoom(roomName ?? "$displayName's room");
      rooms = [room, ...rooms];
      await openRoom(room);
    } catch (exception) {
      error = exception.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> startScreenSharing({String? targetRoomId}) async {
    error = null;
    var roomId = targetRoomId;
    if (roomId == null) {
      await createParty(roomName: _uniqueRoomName());
      roomId = activeRoom?.id;
    }
    if (roomId == null) return;
    try {
      await voice.toggleScreenShare(roomId);
    } catch (exception) {
      error = voice.error ?? exception.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> createYoutubeParty(VideoSuggestion video) async {
    await selectMediaResource(MediaResource.fromVideo(video));
  }

  Future<void> selectYoutubeVideo(
    VideoSuggestion video, {
    String? targetRoomId,
  }) async {
    await selectMediaResource(
      MediaResource.fromVideo(video),
      targetRoomId: targetRoomId,
    );
  }

  Future<void> selectViewingActivity(
    ViewingActivity item, {
    String? targetRoomId,
  }) async {
    final sourceType = item.sourceType?.trim().toUpperCase();
    var provider = const {'DIRECT_MP4', 'DIRECT_HLS'}.contains(sourceType)
        ? sourceType!
        : item.provider.trim().toUpperCase();
    var mediaId = item.mediaId;
    var sourceUrl = item.sourceUrl?.trim();
    final pageUri = Uri.tryParse(mediaId);
    final directPage =
        provider.startsWith('DIRECT_') &&
        (sourceUrl == null || sourceUrl.isEmpty || sourceUrl == mediaId) &&
        !(pageUri?.path.toLowerCase().endsWith('.mp4') ?? false) &&
        !(pageUri?.path.toLowerCase().endsWith('.m3u8') ?? false);
    if (provider == 'WEB' || directPage) {
      busy = true;
      error = null;
      notifyListeners();
      try {
        final resolved = await api.resolveWebMedia(mediaId);
        sourceUrl = (resolved['sourceUrl'] as String?)?.trim();
        provider = (resolved['sourceType'] as String? ?? '').toUpperCase();
        if (!const {'DIRECT_MP4', 'DIRECT_HLS'}.contains(provider) ||
            Uri.tryParse(sourceUrl ?? '')?.scheme != 'https') {
          throw StateError('This saved page did not return a playable video.');
        }
      } catch (exception) {
        error = exception.toString();
        busy = false;
        notifyListeners();
        return;
      }
    }
    if (provider == 'YOUTUBE') {
      final uri = Uri.tryParse(mediaId);
      mediaId =
          uri?.queryParameters['v'] ??
          (uri?.host == 'youtu.be' && uri!.pathSegments.isNotEmpty
              ? uri.pathSegments.first
              : mediaId);
    }
    await selectMediaResource(
      MediaResource(
        provider: provider,
        mediaId: mediaId,
        sourceUrl: sourceUrl,
        sourcePageUrl: item.mediaId,
        title: item.title,
        thumbnailUrl: item.thumbnailUrl,
      ),
      targetRoomId: targetRoomId,
    );
  }

  Future<void> selectProviderMedia({
    required String provider,
    required String mediaId,
    required String title,
    String? thumbnailUrl,
    String? targetRoomId,
    List<({String mediaId, String title, String? thumbnailUrl})>
        followingMedia =
        const [],
  }) async {
    await selectMediaResource(
      MediaResource(
        provider: provider,
        mediaId: mediaId,
        title: title,
        thumbnailUrl: thumbnailUrl,
        sourcePageUrl: mediaId,
      ),
      targetRoomId: targetRoomId,
      followingMedia: followingMedia,
    );
  }

  Future<void> selectDirectVideo(
    String url, {
    String? targetRoomId,
    String? sourceType,
    String? title,
    String? thumbnailUrl,
    String? sourcePageUrl,
  }) async {
    final uri = Uri.tryParse(url.trim());
    final path = uri?.path.toLowerCase() ?? '';
    final provider =
        sourceType ??
        (path.endsWith('.m3u8')
            ? 'DIRECT_HLS'
            : path.endsWith('.mp4')
            ? 'DIRECT_MP4'
            : null);
    if (uri?.scheme != 'https' ||
        !const {'DIRECT_MP4', 'DIRECT_HLS'}.contains(provider)) {
      error = 'Enter a public HTTPS .mp4 or .m3u8 URL.';
      notifyListeners();
      return;
    }
    await selectMediaResource(
      MediaResource(
        provider: provider!,
        mediaId: sourcePageUrl?.trim().isNotEmpty == true
            ? sourcePageUrl!.trim()
            : url.trim(),
        sourceUrl: url.trim(),
        title: title?.trim().isNotEmpty == true ? title!.trim() : 'Web video',
        thumbnailUrl: thumbnailUrl,
        sourcePageUrl: sourcePageUrl,
      ),
      targetRoomId: targetRoomId,
    );
  }

  Future<void> createDirectParty(
    String url, {
    String? sourceType,
    String? title,
    String? thumbnailUrl,
  }) async {
    await selectDirectVideo(
      url,
      sourceType: sourceType,
      title: title,
      thumbnailUrl: thumbnailUrl,
    );
  }

  /// The single room-routing action for every provider adapter.
  Future<void> selectMediaResource(
    MediaResource resource, {
    String? targetRoomId,
    List<({String mediaId, String title, String? thumbnailUrl})>
        followingMedia =
        const [],
  }) async {
    final provider = resource.normalizedProvider;
    if (provider.isEmpty ||
        resource.mediaId.trim().isEmpty ||
        resource.title.trim().isEmpty) {
      error = 'This provider did not return a playable media resource.';
      notifyListeners();
      return;
    }
    if (const {'NETFLIX', 'PRIME_VIDEO'}.contains(provider) ||
        (provider == 'CRUNCHYROLL' &&
            defaultTargetPlatform != TargetPlatform.android)) {
      error =
          'Protected DRM providers are disabled for now and will be added later.';
      notifyListeners();
      return;
    }
    if (resource.isDirect) {
      final uri = Uri.tryParse(
        (resource.sourceUrl?.trim().isNotEmpty == true
                ? resource.sourceUrl
                : resource.mediaId)!
            .trim(),
      );
      if (uri?.scheme != 'https' ||
          !const {'DIRECT_MP4', 'DIRECT_HLS'}.contains(provider)) {
        error = 'Enter a public HTTPS .mp4 or .m3u8 URL.';
        notifyListeners();
        return;
      }
    }

    busy = true;
    error = null;
    if (!resource.isYoutube) suggestions = const [];
    notifyListeners();
    try {
      var roomId = targetRoomId;
      PartyRoom? createdRoom;
      if (roomId == null) {
        createdRoom = await api.createRoom(_uniqueRoomName());
        rooms = [createdRoom, ...rooms];
        roomId = createdRoom.id;
      }
      final resolvedRoomId = roomId;
      final added = await _enqueueMediaResource(resolvedRoomId, resource);
      if (createdRoom == null) _lastRoomSelection = added;
      _recordActivityInBackground(resource.toVideoSuggestion());

      if (resource.isYoutube) {
        suggestions = suggestions
            .where((item) => item.videoId != resource.mediaId)
            .toList();
      } else {
        suggestions = followingMedia
            .map(
              (media) => VideoSuggestion(
                videoId: media.mediaId,
                title: media.title,
                channelTitle: provider,
                thumbnailUrl: media.thumbnailUrl ?? '',
                provider: provider,
              ),
            )
            .toList();
      }

      if (createdRoom != null) {
        await api.playQueueItem(resolvedRoomId, added.id);
        _watchReceivedAt = DateTime.now();
        await openRoom(createdRoom);
        shelfOpen = false;
      } else if (activeRoom?.id == resolvedRoomId) {
        final shouldStartNow = watchState?.playing != true;
        if (canAddToQueue && shouldStartNow) {
          watchState = await api.playQueueItem(resolvedRoomId, added.id);
          _watchReceivedAt = DateTime.now();
          await _syncDevicePip();
        }
        _setQueue(await api.watchQueue(resolvedRoomId));
        _syncActiveRoomPreview(knownThumbnail: resource.thumbnailUrl);
        shelfOpen = !shouldStartNow || !canAddToQueue;
      }
    } catch (exception) {
      error = exception.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<QueueItem> _enqueueMediaResource(
    String roomId,
    MediaResource resource,
  ) {
    if (resource.isYoutube) {
      return api.addToQueue(roomId, resource.toVideoSuggestion());
    }
    if (resource.isDirect) {
      return api.addDirectToQueue(
        roomId,
        resource.normalizedProvider,
        resource.mediaId.trim(),
        sourceUrl: resource.sourceUrl,
        title: resource.title,
        thumbnailUrl: resource.thumbnailUrl,
      );
    }
    return api.addProviderToQueue(
      roomId,
      provider: resource.normalizedProvider,
      mediaId: resource.mediaId.trim(),
      title: resource.title,
      thumbnailUrl: resource.thumbnailUrl,
    );
  }

  Future<List<VideoSuggestion>> searchVideos(String query) async {
    if (query.trim().length < 2) return const [];
    return api.searchYoutube(query.trim());
  }

  String _uniqueRoomName() {
    final suffix = DateTime.now().millisecondsSinceEpoch.remainder(1000000);
    return "$displayName's room $suffix";
  }

  Map<String, PartyRoom> _mergeRoomLists(
    List<PartyRoom> mine,
    List<PartyRoom> publicRooms,
  ) {
    final membership = {for (final room in mine) room.id: room};
    return {
      ...membership,
      for (final room in publicRooms)
        room.id: room.copyWith(role: membership[room.id]?.role ?? room.role),
    };
  }

  Future<void> _loadAuthenticatedHome() async {
    await Future.wait([_loadActivityPreferences(), _loadProfilePreferences()]);
    final results = await Future.wait([
      api.profile(),
      api.publicRooms(),
      api.myRooms(),
    ]);
    profile = results[0] as Profile;
    final publicRooms = results[1] as List<PartyRoom>;
    final mine = results[2] as List<PartyRoom>;
    final roomById = _mergeRoomLists(mine, publicRooms);
    rooms = roomById.values.toList();
    await DeviceFeatures.requestNotifications();
    await _connectNotifications();
    final launchPayload = await DeviceFeatures.launchPayload();
    if (launchPayload != null) await _handleNotificationTap(launchPayload);
    if (activeRoom == null) {
      final savedRoomId = await store.readActiveRoomId();
      final saved = roomById[savedRoomId];
      if (saved != null) await openRoom(saved, restoring: true);
    }
  }

  Future<void> _connectNotifications() =>
      notificationStream.connect((event) async {
        if (event['roomId']?.toString() == activeRoom?.id &&
            event['type'] == 'HOST_MUTE') {
          await voice.muteMicrophone(activeRoom!.id);
          return;
        }
        if (event['roomId']?.toString() == activeRoom?.id &&
            event['type'] == 'HOST_UNMUTE_REQUEST') {
          unmuteRequested = true;
          notifyListeners();
          return;
        }
        if (event['roomId']?.toString() == activeRoom?.id &&
            event['type'] == 'SCREEN_SHARE_APPROVED') {
          screenShareApproved = true;
          notifyListeners();
          return;
        }
        if (event['type'] == 'DIRECT_MESSAGE') {
          final senderId = event['senderId']?.toString();
          if (senderId != null && senderId.isNotEmpty) {
            unreadDirectMessageSenderIds.add(senderId);
            notifyListeners();
          }
          return;
        }
        if (event['type'] == 'ROOM_INVITE') {
          try {
            final latest = await api.myRooms();
            final merged = <String, PartyRoom>{
              for (final room in [...rooms, ...latest]) room.id: room,
            };
            rooms = merged.values.toList();
            notifyListeners();
          } catch (_) {}
        }
        if (event['type'] == 'ROOM_MENTION') {
          if (event['haptic'] == true && hapticFeedback) {
            await DeviceFeatures.vibrateMention();
          }
          final roomId = event['roomId']?.toString();
          if (roomId != null && activeRoom?.id == roomId) {
            try {
              messages = await api.roomChat(roomId, profile!.id);
              notifyListeners();
            } catch (_) {}
          }
        }
      });

  String? takePendingDirectMessageSenderId() {
    final senderId = pendingDirectMessageSenderId;
    pendingDirectMessageSenderId = null;
    if (senderId != null) unreadDirectMessageSenderIds.remove(senderId);
    return senderId;
  }

  void markDirectMessagesRead(String senderId) {
    if (unreadDirectMessageSenderIds.remove(senderId)) notifyListeners();
  }

  Future<void> setRoomAudience(String visibility) async {
    final room = activeRoom;
    if (room == null || room.role != 'HOST') return;
    final normalized = visibility.toUpperCase();
    final policy = normalized == 'PRIVATE' ? 'INVITE_ONLY' : 'OPEN';
    await api.updateRoomAudience(
      room.id,
      visibility: normalized,
      accessPolicy: policy,
    );
    final updated = room.copyWith(visibility: normalized, accessPolicy: policy);
    activeRoom = updated;
    rooms = rooms.map((item) => item.id == room.id ? updated : item).toList();
    notifyListeners();
  }

  Future<void> _connectRoomSync(String roomId) =>
      watchSync.connect(roomId, (state) {
        if ((watchState?.revision ?? -1) > state.revision) return;
        watchState = state;
        _watchReceivedAt = DateTime.now();
        _syncActiveRoomPreview();
        unawaited(_syncDevicePip());
        notifyListeners();
      }, onTimelineChanged: () => unawaited(_refreshTimeline(roomId)));

  Future<void> _refreshTimeline(String roomId) async {
    final me = profile;
    if (_refreshingTimeline || me == null || activeRoom?.id != roomId) return;
    _refreshingTimeline = true;
    try {
      messages = await api.roomChat(roomId, me.id);
      final room = activeRoom;
      if (room?.id == roomId) {
        final participants = await api.liveParticipants(roomId);
        final mine = participants.where(
          (item) => item['userId']?.toString() == me.id,
        );
        if (mine.isNotEmpty) {
          final role = mine.first['role']?.toString().toUpperCase();
          if (role == 'HOST' && room!.role != 'HOST') {
            activeRoom = room.copyWith(role: 'HOST');
            await voice.refreshPermissions(roomId);
          } else if (role == 'CO_HOST' || role == 'MEMBER') {
            activeRoom = room!.copyWith(role: role);
          }
        }
      }
      _removeDuplicateSuggestions();
      notifyListeners();
    } catch (_) {
      // The periodic refresh remains a fallback during transient reconnects.
    } finally {
      _refreshingTimeline = false;
    }
  }

  /// Re-establishes network state after Android/iOS suspends the process.
  /// We intentionally do not leave a room when the app backgrounds.
  Future<void> resumeConnections() async {
    if (!authenticated || initializing || _resumeInFlight) return;
    _resumeInFlight = true;
    reconnecting = true;
    notifyListeners();
    try {
      await api.accessToken();
      await _connectNotifications();
      final room = activeRoom;
      if (room != null) {
        // Re-joining is idempotent server-side and restores expired presence.
        await api.joinLiveRoom(room.id);
        await _refreshRoomData();
        await _connectRoomSync(room.id);
        _startRefreshLoop();
        await _syncDevicePip();
      } else {
        final latest = await Future.wait<List<PartyRoom>>([
          api.publicRooms(),
          api.myRooms(),
        ]);
        rooms = _mergeRoomLists(latest[1], latest[0]).values.toList();
      }
      error = null;
    } catch (exception) {
      error = 'Reconnecting: $exception';
    } finally {
      reconnecting = false;
      _resumeInFlight = false;
      notifyListeners();
    }
  }

  Future<void> _handleNotificationTap(Map<String, dynamic> payload) async {
    if (!authenticated) return;
    if (payload['type'] == 'DIRECT_MESSAGE') {
      final senderId = payload['senderId']?.toString();
      if (senderId == null || senderId.isEmpty) return;
      pendingDirectMessageSenderId = senderId;
      notifyListeners();
      return;
    }
    if (payload['type'] != 'ROOM_INVITE' && payload['type'] != 'ROOM_MENTION') {
      return;
    }
    final roomId = payload['roomId']?.toString();
    if (roomId == null || roomId.isEmpty) return;
    try {
      var room = rooms.where((item) => item.id == roomId).firstOrNull;
      if (room == null) {
        final latest = await api.myRooms();
        final merged = <String, PartyRoom>{
          for (final item in [...rooms, ...latest]) item.id: item,
        };
        rooms = merged.values.toList();
        room = merged[roomId];
      }
      if (room != null) await openRoom(room);
    } catch (exception) {
      error = 'Could not open the invited room: $exception';
      notifyListeners();
    }
  }

  Future<void> openRoom(
    PartyRoom room, {
    bool restoring = false,
    String accessKey = '',
  }) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final switchingRooms = activeRoom?.id != room.id;
      activeRoom = room;
      if (switchingRooms) {
        activeParticipants = const [];
        watchState = null;
        queue = const [];
        messages = const [];
        replyToMessage = null;
        suggestions = const [];
        canViewVideo = room.role == 'HOST' || room.role == 'CO_HOST';
        videoAccessRequested = false;
      }
      checkingVideoAccess = !canViewVideo;
      // Transition to the room immediately so the player can mount while the
      // join, queue, chat, and sync requests finish in the background UI.
      notifyListeners();
      if (!room.joined) {
        await api.unlockRoom(room.id, accessKey: accessKey);
      }
      await api.joinLiveRoom(room.id);
      if (!room.joined) {
        // Successful admission grants a new member viewing access. The live
        // participant projection may still lag this write for one refresh.
        canViewVideo = true;
        checkingVideoAccess = false;
        notifyListeners();
      }
      await _refreshRoomData(loadSuggestions: true);
      // The player must receive the fetched watch state before optional
      // realtime/persistence setup, which can be slow on a cold emulator.
      notifyListeners();
      await _syncDevicePip();
      await _connectRoomSync(room.id);
      try {
        await voice.connect(room.id);
      } catch (exception) {
        debugPrint('Room screen media could not connect: $exception');
      }
      await store.saveActiveRoomId(room.id);
      _startRefreshLoop();
    } catch (exception) {
      checkingVideoAccess = false;
      activeRoom = null;
      error = restoring
          ? 'Your previous room is no longer available.'
          : exception.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _refreshRoomData({bool loadSuggestions = false}) async {
    final room = activeRoom;
    final me = profile;
    if (room == null || me == null) return;
    final participants = await api.liveParticipants(room.id);
    activeParticipants = participants;
    // Viewing access must appear as soon as membership is confirmed. A slow
    // chat or queue response must not leave an admitted member behind the
    // private-video gate while the remaining room data loads.
    final myMembership = participants.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['userId']?.toString() == me.id,
      orElse: () => null,
    );
    final liveRole = myMembership?['role']?.toString().toUpperCase();
    if (liveRole == 'HOST' || liveRole == 'CO_HOST' || liveRole == 'MEMBER') {
      activeRoom = room.copyWith(role: liveRole);
      if (liveRole == 'HOST' && room.role != 'HOST') {
        await voice.refreshPermissions(room.id);
      }
    }
    canViewVideo =
        canControlWatch ||
        room.role == 'CO_HOST' ||
        liveRole == 'HOST' ||
        liveRole == 'CO_HOST' ||
        myMembership?['canViewVideo'] == true;
    // A just-admitted member can be absent from the first participant read.
    // Keep the joining loader until membership is visible; only an explicit
    // canViewVideo=false result should open the access gate.
    checkingVideoAccess = myMembership == null && !canViewVideo;
    videoAccessRequested = myMembership?['videoAccessRequested'] == true;
    notifyListeners();
    final results = await Future.wait([
      api.watchState(room.id),
      api.watchQueueInfo(room.id),
      api.roomChat(room.id, me.id),
    ]);
    final previousId = watchState?.mediaId;
    watchState = results[0] as RoomWatchState?;
    _syncActiveRoomPreview();
    _watchReceivedAt = DateTime.now();
    final queueInfo = results[1] as Map<String, dynamic>;
    queueMode = (queueInfo['mode'] ?? 'HOSTS_ONLY').toString();
    canAddToQueue = queueInfo['canAdd'] == true;
    _setQueue(
      (queueInfo['items'] as List<dynamic>? ?? const []).map(
        (item) => QueueItem.fromJson(item as Map<String, dynamic>),
      ),
    );
    messages = results[2] as List<ChatMessage>;
    if (loadSuggestions || previousId != watchState?.mediaId) {
      final state = watchState;
      if (state == null) {
        suggestions = const [];
      } else if (state.provider.toUpperCase() == 'YOUTUBE') {
        suggestions = const [];
        _loadSuggestionsInBackground(state);
      } else {
        // Provider-supplied continuations (for example later episodes) must
        // survive periodic room refreshes. They were previously replaced by
        // an unrelated YouTube search for every provider.
        suggestions = suggestions
            .where(
              (item) =>
                  item.provider.toUpperCase() == state.provider.toUpperCase(),
            )
            .toList(growable: false);
        _removeDuplicateSuggestions();
      }
    } else {
      _removeDuplicateSuggestions();
    }
  }

  Future<void> requestCurrentVideoAccess() async {
    final room = activeRoom;
    if (room == null || videoUnlocked || videoAccessRequested) return;
    await api.requestVideoAccess(room.id);
    videoAccessRequested = true;
    notifyListeners();
  }

  void _loadSuggestionsInBackground(RoomWatchState expected) {
    if (expected.provider.toUpperCase() != 'YOUTUBE') return;
    final title = _recommendationTitle(expected);
    if (_isGenericMediaTitle(title)) return;
    final revision = ++_suggestionLoadRevision;
    unawaited(() async {
      List<VideoSuggestion> loaded = const [];
      try {
        loaded = await api.searchYoutube(_recommendationQuery(title));
      } catch (_) {}
      if (revision != _suggestionLoadRevision ||
          activeRoom == null ||
          watchState?.mediaId != expected.mediaId) {
        return;
      }
      suggestions = loaded;
      _removeDuplicateSuggestions();
      notifyListeners();
    }());
  }

  void _removeDuplicateSuggestions() {
    final unavailable = <String>{
      if (watchState != null) watchState!.mediaId,
      ...queue.map((item) => item.mediaId),
      ...messages
          .where(
            (message) => message.type == 'VIDEO' && message.mediaId != null,
          )
          .map((message) => message.mediaId!),
    };
    final currentTitle = watchState == null
        ? ''
        : _recommendationTitle(watchState!);
    final seenIds = <String>{};
    final seenTitles = <String>{
      ...messages
          .where(
            (message) => message.type == 'VIDEO' && message.mediaTitle != null,
          )
          .map((message) => _normalizedMediaTitle(message.mediaTitle!))
          .where((title) => title.isNotEmpty),
    };
    suggestions = suggestions
        .where((video) {
          final idKey =
              '${video.provider.toUpperCase()}|${video.videoId.trim()}';
          final titleKey = _normalizedMediaTitle(video.title);
          if (unavailable.contains(video.videoId) || !seenIds.add(idKey)) {
            return false;
          }
          if (_sameMediaTitle(video.title, currentTitle)) return false;
          if (titleKey.isNotEmpty && !seenTitles.add(titleKey)) return false;
          return true;
        })
        .toList(growable: false);
  }

  void _setQueue(Iterable<QueueItem> items) {
    final unique = <String, QueueItem>{};
    for (final item in items) {
      final normalizedTitle = _normalizedMediaTitle(item.title);
      final key =
          normalizedTitle.length >= 5 && !_isGenericMediaTitle(normalizedTitle)
          ? '${item.provider.trim().toUpperCase()}|TITLE|$normalizedTitle'
          : '${item.provider.trim().toUpperCase()}|ID|${item.mediaId.trim()}';
      final existing = unique[key];
      if (existing == null || item.voteCount > existing.voteCount) {
        unique[key] = item;
      }
    }
    final ranked = unique.values.toList(growable: false);
    final stableOrder = <String, int>{
      for (var index = 0; index < ranked.length; index++)
        ranked[index].id: index,
    };
    ranked.sort((left, right) {
      final votes = right.voteCount.compareTo(left.voteCount);
      if (votes != 0) return votes;
      return stableOrder[left.id]!.compareTo(stableOrder[right.id]!);
    });
    queue = ranked;
  }

  String get suggestionSectionTitle {
    final state = watchState;
    if (state == null) return 'SUGGESTED FOR THIS ROOM';
    final provider = state.provider.toUpperCase();
    final title = _recommendationTitle(state);
    if (provider == 'CRUNCHYROLL' || _looksEpisodic(title)) {
      return 'NEXT EPISODES';
    }
    if (provider == 'YOUTUBE' && _looksLikeMusic(title)) {
      return 'SIMILAR SONGS';
    }
    if (provider.startsWith('DIRECT') || provider == 'WEB') {
      return 'MORE FROM THIS WEB SOURCE';
    }
    return provider == 'YOUTUBE' ? 'RELATED VIDEOS' : 'MORE FROM THIS PROVIDER';
  }

  String get suggestionItemLabel {
    final heading = suggestionSectionTitle;
    if (heading == 'NEXT EPISODES') return 'NEXT EPISODE';
    if (heading == 'SIMILAR SONGS') return 'SIMILAR SONG';
    return 'SUGGESTED';
  }

  String get suggestionEmptyMessage {
    final provider = watchState?.provider.toUpperCase() ?? '';
    if (provider == 'CRUNCHYROLL' ||
        (watchState != null &&
            _looksEpisodic(_recommendationTitle(watchState!)))) {
      return 'No later episodes were found. Browse this provider to choose the next one.';
    }
    if (provider.startsWith('DIRECT') || provider == 'WEB') {
      return 'Browse the same website to add related videos from that provider.';
    }
    return 'No distinct related videos were found.';
  }

  void rememberResolvedMediaTitle(String mediaId, String? title) {
    final cleaned = title?.trim() ?? '';
    if (cleaned.isEmpty || _isGenericMediaTitle(cleaned)) return;
    if (_resolvedMediaTitles[mediaId] == cleaned) return;
    _resolvedMediaTitles[mediaId] = cleaned;
    final state = watchState;
    if (state != null &&
        state.mediaId == mediaId &&
        state.provider.toUpperCase() == 'YOUTUBE') {
      suggestions = const [];
      _loadSuggestionsInBackground(state);
      notifyListeners();
    }
  }

  String _recommendationTitle(RoomWatchState state) =>
      _resolvedMediaTitles[state.mediaId] ?? state.title.trim();

  static String _recommendationQuery(String title) {
    final seed = title
        .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)'), ' ')
        .replaceAll(
          RegExp(
            r'\b(official|video|audio|lyrics?|lyrical|hd|4k|8k|full song)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (_looksEpisodic(title)) return '$seed next episode';
    if (_looksLikeMusic(title)) return 'songs similar to $seed';
    return '$seed related videos';
  }

  static bool _looksLikeMusic(String title) {
    final lower = title.toLowerCase();
    return lower.contains(' - ') ||
        RegExp(
          r'\b(song|music|official audio|official video|lyrics?|remix|lofi|album|feat\.?|ft\.?)\b',
        ).hasMatch(lower);
  }

  static bool _looksEpisodic(String title) => RegExp(
    r'\b(s\d{1,2}\s*e\d{1,3}|season\s*\d+|episode\s*\d+|ep\.?\s*\d+)\b',
    caseSensitive: false,
  ).hasMatch(title);

  static bool _isGenericMediaTitle(String title) {
    final normalized = _normalizedMediaTitle(title);
    return normalized.isEmpty ||
        normalized == 'youtube video' ||
        normalized == 'selected web video' ||
        normalized == 'video' ||
        normalized == 'now playing';
  }

  static bool _sameMediaTitle(String left, String right) {
    final a = _normalizedMediaTitle(left);
    final b = _normalizedMediaTitle(right);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    final shorter = a.length < b.length ? a : b;
    final longer = a.length < b.length ? b : a;
    return shorter.length >= 10 &&
        longer.contains(shorter) &&
        shorter.length / longer.length >= .78;
  }

  static String _normalizedMediaTitle(String title) => title
      .toLowerCase()
      .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)'), ' ')
      .replaceAll(
        RegExp(
          r'\b(official|video|audio|lyrics?|lyrical|hd|4k|8k|full song)\b',
        ),
        ' ',
      )
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  void _mergeQueueItem(QueueItem item) {
    _setQueue([...queue, item]);
  }

  Future<void> addSuggestion(VideoSuggestion video) async {
    if (watchState?.mediaId == video.videoId) {
      return;
    }
    final existing = queue
        .where((item) => item.mediaId == video.videoId)
        .firstOrNull;
    if (existing != null) {
      if (canAddToQueue && watchState?.playing != true) {
        await playQueueItem(existing);
      } else {
        await selectQueueItem(existing);
      }
      suggestions = suggestions
          .where((item) => item.videoId != video.videoId)
          .toList();
      notifyListeners();
      return;
    }
    if (activeRoom != null) {
      final added = await api.addToQueue(
        activeRoom!.id,
        video,
        personalQueueItem: false,
      );
      if (canAddToQueue && watchState?.playing != true) {
        await playQueueItem(added);
      } else {
        _mergeQueueItem(added);
        shelfOpen = true;
      }
    }
    suggestions = suggestions
        .where((item) => item.videoId != video.videoId)
        .toList();
    notifyListeners();
  }

  Future<void> playQueueItem(QueueItem item) async {
    if (activeRoom != null) {
      watchState = await api.playQueueItem(activeRoom!.id, item.id);
      await _syncDevicePip();
      _setQueue(await api.watchQueue(activeRoom!.id));
      _syncActiveRoomPreview(knownThumbnail: item.thumbnailUrl);
    }
    await _recordActivity(
      VideoSuggestion(
        videoId: item.mediaId,
        title: item.title,
        channelTitle: watchState?.provider ?? 'WEB',
        thumbnailUrl: item.thumbnailUrl ?? '',
        provider: watchState?.provider ?? 'WEB',
        sourceUrl: watchState?.sourceUrl ?? item.sourceUrl,
        sourceType: watchState?.sourceType,
      ),
    );
    muted = false;
    shelfOpen = false;
    _removeDuplicateSuggestions();
    notifyListeners();
  }

  Future<void> selectQueueItem(QueueItem item) async {
    final room = activeRoom;
    if (room == null) return;
    if (canAddToQueue && watchState?.playing != true) {
      await playQueueItem(item);
      return;
    }
    _setQueue(await api.voteQueueItem(room.id, item.id));
    shelfOpen = true;
    notifyListeners();
  }

  QueueItem? takeLastRoomSelection() {
    final selected = _lastRoomSelection;
    _lastRoomSelection = null;
    return selected;
  }

  Future<void> openTimelineVideo(ChatMessage message) async {
    final room = activeRoom;
    final mediaId = message.mediaId?.trim();
    if (room == null || mediaId == null || mediaId.isEmpty) return;
    if (isCurrentTimelineVideo(message)) {
      shelfOpen = false;
      notifyListeners();
      return;
    }
    final provider = (message.mediaProvider ?? 'YOUTUBE').toUpperCase();
    final title = message.mediaTitle?.trim().isNotEmpty == true
        ? message.mediaTitle!.trim()
        : 'Shared video';
    if (provider == 'YOUTUBE') {
      await selectYoutubeVideo(
        VideoSuggestion(
          videoId: mediaId,
          title: title,
          channelTitle: 'Room chat',
          thumbnailUrl: 'https://i.ytimg.com/vi/$mediaId/hqdefault.jpg',
        ),
        targetRoomId: room.id,
      );
    } else if (provider == 'DIRECT_MP4' || provider == 'DIRECT_HLS') {
      await selectDirectVideo(
        mediaId,
        targetRoomId: room.id,
        sourceType: provider,
        title: title,
      );
    } else {
      await selectProviderMedia(
        provider: provider,
        mediaId: mediaId,
        title: title,
        targetRoomId: room.id,
      );
    }
  }

  Future<void> shareQueueItemToChat(QueueItem item) async {
    final room = activeRoom;
    final me = profile;
    if (room == null || me == null) return;
    final sent = await api.shareRoomVideo(
      room.id,
      me.id,
      provider: item.provider,
      mediaId: item.mediaId,
      title: item.title,
    );
    messages = [...messages.where((message) => message.id != sent.id), sent];
    panel = RoomPanel.chat;
    notifyListeners();
  }

  Future<bool> playHighestVoted() async {
    final room = activeRoom;
    if (room == null || !canControlWatch || roomQueue.isEmpty) return false;
    watchState = await api.playHighestVoted(room.id);
    await _syncDevicePip();
    _setQueue(await api.watchQueue(room.id));
    _syncActiveRoomPreview();
    shelfOpen = false;
    _watchReceivedAt = DateTime.now();
    _removeDuplicateSuggestions();
    notifyListeners();
    return true;
  }

  void _syncActiveRoomPreview({String? knownThumbnail}) {
    final room = activeRoom;
    final state = watchState;
    if (room == null || state == null) return;
    final updated = PartyRoom(
      id: room.id,
      name: room.name,
      viewerCount: room.viewerCount,
      ownerName: room.ownerName,
      description: room.description,
      mediaTitle: state.title,
      mediaId: state.mediaId,
      mediaProvider: state.provider,
      thumbnailUrl: knownThumbnail ?? state.thumbnailUrl ?? room.thumbnailUrl,
      joined: room.joined,
      role: room.role,
      accessPolicy: room.accessPolicy,
      visibility: room.visibility,
    );
    activeRoom = updated;
    rooms = rooms
        .map((candidate) => candidate.id == updated.id ? updated : candidate)
        .toList();
  }

  Future<void> togglePlayback(double positionSeconds) async {
    final state = watchState;
    if (state == null || !canControlWatch) return;
    watchState = state.copyWith(
      playing: !state.playing,
      positionSeconds: positionSeconds,
    );
    _watchReceivedAt = DateTime.now();
    await _syncDevicePip();
    notifyListeners();
    if (activeRoom != null &&
        !watchSync.publish(
          watchState!.playing ? 'PLAY' : 'PAUSE',
          watchState!,
          positionSeconds: positionSeconds,
        )) {
      await api.updateWatch(activeRoom!.id, watchState!);
    }
  }

  void updatePlayerPosition(double seconds) {
    final state = watchState;
    if (state == null) return;
    watchState = state.copyWith(positionSeconds: seconds);
    _watchReceivedAt = DateTime.now();
  }

  /// Re-resolves a Web page when its temporary signed media URL has expired.
  /// The stable page URL remains [RoomWatchState.mediaId], so history, queue
  /// identity, and chat cards do not change when the provider rotates links.
  List<Map<String, dynamic>> resolvedWebSourcesFor(String pageUrl) =>
      _resolvedWebSourcesPage == pageUrl ? _resolvedWebSources : const [];

  Future<bool> refreshExpiredWebMedia() async {
    final state = watchState;
    final pageUri = Uri.tryParse(state?.mediaId ?? '');
    final streamUri = Uri.tryParse(state?.sourceUrl ?? '');
    if (state == null ||
        !state.provider.toUpperCase().startsWith('DIRECT_') ||
        pageUri?.scheme != 'https' ||
        pageUri?.host.isEmpty != false) {
      return false;
    }
    final pagePath = pageUri!.path.toLowerCase();
    if (state.mediaId == state.sourceUrl &&
        (pagePath.endsWith('.mp4') || pagePath.endsWith('.m3u8'))) {
      return false;
    }
    try {
      final resolved = await api.resolveWebMedia(state.mediaId);
      final resolvedSources =
          (resolved['sources'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((source) => Map<String, dynamic>.from(source))
              .toList(growable: false);
      final sourceUrl = (resolved['sourceUrl'] as String? ?? '').trim();
      final sourceType = (resolved['sourceType'] as String? ?? '').trim();
      final resolvedUri = Uri.tryParse(sourceUrl);
      if (resolvedUri?.scheme != 'https' ||
          resolvedUri?.host.isEmpty != false ||
          !const {'DIRECT_MP4', 'DIRECT_HLS'}.contains(sourceType)) {
        return false;
      }
      _resolvedWebSourcesPage = state.mediaId;
      _resolvedWebSources = resolvedSources;
      final primaryChanged = sourceUrl != streamUri?.toString();
      if (!primaryChanged && resolvedSources.isEmpty) return false;
      watchState = state.copyWith(
        provider: sourceType,
        sourceType: sourceType,
        sourceUrl: sourceUrl,
        thumbnailUrl: (resolved['thumbnailUrl'] as String?)?.trim(),
      );
      _watchReceivedAt = DateTime.now();
      notifyListeners();
      if (canControlWatch && activeRoom != null) {
        await api.updateWatch(activeRoom!.id, watchState!);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> seek(double seconds) async {
    if (!canControlWatch) return;
    updatePlayerPosition(seconds);
    notifyListeners();
    if (activeRoom != null &&
        watchState != null &&
        !watchSync.publish('SEEK', watchState!, positionSeconds: seconds)) {
      await api.updateWatch(activeRoom!.id, watchState!);
    }
  }

  Future<void> stopPlayback() async {
    final state = watchState;
    if (state == null || !canControlWatch) return;
    watchState = state.copyWith(playing: false, positionSeconds: 0);
    _watchReceivedAt = DateTime.now();
    await _syncDevicePip();
    notifyListeners();
    if (activeRoom != null &&
        !watchSync.publish('STOP', watchState!, positionSeconds: 0)) {
      await api.updateWatch(activeRoom!.id, watchState!);
    }
  }

  Future<void> reportMediaDuration(String mediaId, double duration) async {
    final room = activeRoom;
    final state = watchState;
    if (room == null ||
        state == null ||
        !canControlWatch ||
        state.mediaId != mediaId ||
        duration <= 0 ||
        (state.durationSeconds != null &&
            (state.durationSeconds! - duration).abs() < 1)) {
      return;
    }
    final position = synchronizedPosition.clamp(0.0, duration);
    watchState = state.copyWith(
      durationSeconds: duration,
      positionSeconds: position,
      playing: state.playing && position < duration - .5,
    );
    _watchReceivedAt = DateTime.now();
    notifyListeners();
    await api.updateWatch(room.id, watchState!);
  }

  void setMuted(bool value) {
    muted = value;
    notifyListeners();
  }

  void setVolume(double value) {
    volume = value.clamp(0, 1);
    if (volume > 0) muted = false;
    notifyListeners();
  }

  void setPanel(RoomPanel next) {
    panel = next;
    notifyListeners();
  }

  void setShelfOpen(bool value) {
    shelfOpen = value;
    notifyListeners();
  }

  void openPostPlaybackShelf() {
    final state = watchState;
    if (state != null && state.provider.toUpperCase() == 'YOUTUBE') {
      suggestions = const [];
      _loadSuggestionsInBackground(state);
    } else {
      _removeDuplicateSuggestions();
    }
    shelfOpen = true;
    notifyListeners();
  }

  void setQuality(String quality) {
    selectedQuality = quality;
    notifyListeners();
  }

  void setCaption(String caption) {
    selectedCaption = caption;
    notifyListeners();
  }

  List<PartyRoom> get visibleRooms => hideSensitiveContent
      ? rooms
            .where(
              (room) => !_isSensitive(
                '${room.name} ${room.mediaTitle ?? ''} ${room.mediaId ?? ''}',
              ),
            )
            .toList()
      : rooms;

  Map<String, int> get categoryViews {
    final result = <String, int>{};
    for (final item in history) {
      final label = item.provider == 'YOUTUBE'
          ? 'YouTube'
          : item.provider == 'CRUNCHYROLL'
          ? 'Anime'
          : item.provider.startsWith('DIRECT')
          ? 'Direct'
          : 'Web';
      result[label] = (result[label] ?? 0) + item.views;
    }
    return result;
  }

  Future<void> setHideSensitiveContent(bool value) async {
    const key = 'hideSensitiveContent';
    if (savingProfilePreferences.contains(key)) return;
    final previous = hideSensitiveContent;
    hideSensitiveContent = value;
    savingProfilePreferences.add(key);
    notifyListeners();
    try {
      final results = await Future.wait<dynamic>([
        api.updateProfilePreferences({'hideSensitiveContent': value}),
        Future<void>.delayed(const Duration(milliseconds: 1400)),
      ]);
      final saved = results.first as Map<String, dynamic>;
      _applySavedPreferences(saved);
      error = null;
    } catch (exception) {
      hideSensitiveContent = previous;
      error = 'Could not save that setting. Please try again.';
    } finally {
      savingProfilePreferences.remove(key);
      notifyListeners();
    }
  }

  Future<void> _loadProfilePreferences() async {
    final dashboard = await api.profileDashboard();
    final preferences =
        dashboard['preferences'] as Map<String, dynamic>? ?? const {};
    hideSensitiveContent = preferences['hideSensitiveContent'] as bool? ?? true;
    hideLocation = preferences['hideLocation'] as bool? ?? false;
    restrictInvites = preferences['restrictInvites'] as bool? ?? false;
    floatingVideo = preferences['floatingVideo'] as bool? ?? true;
    muteOtherAudio = preferences['muteOtherAudio'] as bool? ?? true;
    hapticFeedback = preferences['hapticFeedback'] as bool? ?? true;
    autoTranslate = preferences['autoTranslate'] as bool? ?? false;
    preferredLanguage = preferences['preferredLanguage'] as String? ?? 'en';
    quickReaction = preferences['quickReaction'] as String? ?? '❤️';
    profileInterests = List<String>.from(
      dashboard['interests'] as List? ?? const [],
    );
    profileConnections = (dashboard['connections'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final visibility = dashboard['visibility'] as Map<String, dynamic>?;
    if (visibility != null) {
      profileVisibility = visibility.map(
        (key, value) => MapEntry(key, value.toString()),
      );
    }
  }

  Future<void> saveProfilePreferences() async {
    final saved = await api.updateProfilePreferences({
      'hideSensitiveContent': hideSensitiveContent,
      'hideLocation': hideLocation,
      'restrictInvites': restrictInvites,
      'floatingVideo': floatingVideo,
      'muteOtherAudio': muteOtherAudio,
      'hapticFeedback': hapticFeedback,
      'autoTranslate': autoTranslate,
      'preferredLanguage': preferredLanguage,
      'quickReaction': quickReaction,
    });
    _applySavedPreferences(saved);
    notifyListeners();
  }

  void _applySavedPreferences(Map<String, dynamic> preferences) {
    hideSensitiveContent =
        preferences['hideSensitiveContent'] as bool? ?? hideSensitiveContent;
    hideLocation = preferences['hideLocation'] as bool? ?? hideLocation;
    restrictInvites =
        preferences['restrictInvites'] as bool? ?? restrictInvites;
    floatingVideo = preferences['floatingVideo'] as bool? ?? floatingVideo;
    muteOtherAudio = preferences['muteOtherAudio'] as bool? ?? muteOtherAudio;
    hapticFeedback = preferences['hapticFeedback'] as bool? ?? hapticFeedback;
    autoTranslate = preferences['autoTranslate'] as bool? ?? autoTranslate;
    preferredLanguage =
        preferences['preferredLanguage'] as String? ?? preferredLanguage;
    quickReaction = preferences['quickReaction'] as String? ?? quickReaction;
  }

  Future<void> setProfilePreference(String key, bool value) async {
    if (savingProfilePreferences.contains(key)) return;
    final previous = _profilePreferenceValue(key);
    if (previous == null) return;
    _setProfilePreferenceValue(key, value);
    if (key == 'floatingVideo') unawaited(_syncDevicePip());
    savingProfilePreferences.add(key);
    notifyListeners();
    try {
      final results = await Future.wait<dynamic>([
        api.updateProfilePreferences({key: value}),
        Future<void>.delayed(const Duration(milliseconds: 1400)),
      ]);
      final saved = results.first as Map<String, dynamic>;
      _applySavedPreferences(saved);
      error = null;
    } catch (exception) {
      _setProfilePreferenceValue(key, previous);
      error = 'Could not save that setting. Please try again.';
    } finally {
      savingProfilePreferences.remove(key);
      notifyListeners();
    }
  }

  bool? _profilePreferenceValue(String key) => switch (key) {
    'hideLocation' => hideLocation,
    'restrictInvites' => restrictInvites,
    'floatingVideo' => floatingVideo,
    'muteOtherAudio' => muteOtherAudio,
    'hapticFeedback' => hapticFeedback,
    'autoTranslate' => autoTranslate,
    _ => null,
  };

  void _setProfilePreferenceValue(String key, bool value) {
    switch (key) {
      case 'hideLocation':
        hideLocation = value;
        break;
      case 'restrictInvites':
        restrictInvites = value;
        break;
      case 'floatingVideo':
        floatingVideo = value;
        break;
      case 'muteOtherAudio':
        muteOtherAudio = value;
        break;
      case 'hapticFeedback':
        hapticFeedback = value;
        break;
      case 'autoTranslate':
        autoTranslate = value;
        break;
    }
  }

  Future<void> setProfileVisibility(String section, String visibility) async {
    profileVisibility = {...profileVisibility, section: visibility};
    await api.updateProfileVisibility(profileVisibility);
    notifyListeners();
  }

  Future<void> toggleLike(ViewingActivity item) async {
    final enabled = !likedMediaIds.contains(item.mediaId);
    await api.setMediaLike(item.mediaId, enabled);
    if (enabled) {
      likedMediaIds.add(item.mediaId);
      likedVideos = [
        item,
        ...likedVideos.where((entry) => entry.mediaId != item.mediaId),
      ];
    } else {
      likedMediaIds.remove(item.mediaId);
      likedVideos = likedVideos
          .where((entry) => entry.mediaId != item.mediaId)
          .toList();
    }
    notifyListeners();
  }

  bool isTimelineVideoLiked(ChatMessage message) =>
      message.mediaId != null && likedMediaIds.contains(message.mediaId);

  bool isCurrentTimelineVideo(ChatMessage message) =>
      message.type == 'VIDEO' &&
      message.mediaId != null &&
      message.mediaId == watchState?.mediaId;

  Future<void> toggleTimelineVideoLike(ChatMessage message) async {
    final mediaId = message.mediaId;
    if (mediaId == null) return;
    final thumbnail = message.mediaProvider == 'YOUTUBE'
        ? 'https://i.ytimg.com/vi/${Uri.encodeComponent(mediaId)}/mqdefault.jpg'
        : '';
    await toggleLike(
      ViewingActivity(
        mediaId: mediaId,
        title: message.mediaTitle ?? 'Video',
        provider: message.mediaProvider ?? 'WEB',
        thumbnailUrl: thumbnail,
        watchedAt: message.createdAt,
        sensitive: false,
        sourceUrl: isCurrentTimelineVideo(message)
            ? watchState?.sourceUrl
            : history
                  .where((item) => item.mediaId == mediaId)
                  .firstOrNull
                  ?.sourceUrl,
        sourceType: isCurrentTimelineVideo(message)
            ? watchState?.sourceType
            : history
                  .where((item) => item.mediaId == mediaId)
                  .firstOrNull
                  ?.sourceType,
      ),
    );
  }

  Future<void> skipTimelineVideo(ChatMessage message) async {
    final room = activeRoom;
    if (room == null || !isCurrentTimelineVideo(message)) return;
    try {
      final result = await api.voteToSkip(room.id);
      if (result['skipped'] == true) {
        final state = result['state'];
        watchState = state is Map<String, dynamic>
            ? RoomWatchState.fromJson(state)
            : watchState?.copyWith(playing: false, positionSeconds: 0);
        _watchReceivedAt = DateTime.now();
        _setQueue(await api.watchQueue(room.id));
        _removeDuplicateSuggestions();
      }
      error = null;
    } catch (exception) {
      error = exception.toString();
    }
    notifyListeners();
  }

  Future<void> toggleGallery(ViewingActivity item) async {
    final enabled = !gallery.any((entry) => entry.mediaId == item.mediaId);
    await api.setMediaGallery(item.mediaId, enabled);
    gallery = enabled
        ? [item, ...gallery.where((entry) => entry.mediaId != item.mediaId)]
        : gallery.where((entry) => entry.mediaId != item.mediaId).toList();
    notifyListeners();
  }

  Future<void> removeHistory(ViewingActivity item) async {
    await api.removeHistory(item.mediaId);
    history = history.where((entry) => entry.mediaId != item.mediaId).toList();
    notifyListeners();
  }

  Future<void> _loadActivityPreferences() async {
    final dashboard = await api.mediaDashboard();
    history = (dashboard['history'] as List<dynamic>? ?? const [])
        .map((item) => ViewingActivity.fromJson(item as Map<String, dynamic>))
        .toList();
    gallery = (dashboard['gallery'] as List<dynamic>? ?? const [])
        .map((item) => ViewingActivity.fromJson(item as Map<String, dynamic>))
        .toList();
    likedVideos = (dashboard['likes'] as List<dynamic>? ?? const [])
        .map((item) => ViewingActivity.fromJson(item as Map<String, dynamic>))
        .toList();
    likedMediaIds = likedVideos.map((item) => item.mediaId).toSet();
    hideSensitiveContent = (dashboard['hideSensitiveContent'] ?? true) as bool;
    watchTogetherSeconds = (dashboard['watchTogetherSeconds'] as num? ?? 0)
        .toInt();
    friendCount = (dashboard['friendCount'] as num? ?? 0).toInt();
  }

  Future<void> _recordActivity(VideoSuggestion video) async {
    final data = await api.recordMedia(
      mediaId: video.videoId,
      provider: video.provider,
      title: video.title,
      thumbnailUrl: video.thumbnailUrl,
      sourceUrl: video.provider == 'YOUTUBE' ? null : video.sourceUrl,
      sourceType: video.sourceType,
    );
    final entry = ViewingActivity.fromJson(data);
    history = [
      entry,
      ...history.where((item) => item.mediaId != entry.mediaId),
    ].take(40).toList();
  }

  void _recordActivityInBackground(VideoSuggestion video) {
    unawaited(() async {
      try {
        await _recordActivity(video);
        notifyListeners();
      } catch (_) {
        // History is optional and must never hold up or break playback.
      }
    }());
  }

  static bool _isSensitive(String value) {
    final text = value.toLowerCase();
    return const [
      'nsfw',
      'adult',
      'porn',
      'xxx',
      'xhamster',
      'xvideos',
      'pornhub',
      'femdom',
      'nude',
      'sex',
    ].any(text.contains);
  }

  void beginReply(ChatMessage message) {
    if (message.type != 'MESSAGE') return;
    replyToMessage = message;
    notifyListeners();
  }

  void cancelReply() {
    if (replyToMessage == null) return;
    replyToMessage = null;
    notifyListeners();
  }

  Future<void> sendMessage(String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty || activeRoom == null || profile == null) return;
    final replyId = replyToMessage?.id;
    final sent = await api.sendRoomChat(
      activeRoom!.id,
      trimmed,
      profile!.id,
      replyToId: replyId,
    );
    messages = [...messages, sent];
    replyToMessage = null;
    notifyListeners();
  }

  Future<void> reactToMessage(ChatMessage message, String reaction) async {
    final room = activeRoom;
    final me = profile;
    if (room == null || me == null || message.isSystem) return;
    final updated = await api.reactToRoomMessage(
      room.id,
      message.id,
      reaction,
      me.id,
    );
    messages = messages
        .map((item) => item.id == updated.id ? updated : item)
        .toList(growable: false);
    notifyListeners();
  }

  Future<void> leaveRoom() async {
    final room = activeRoom;
    _refreshTimer?.cancel();
    _heartbeatTimer?.cancel();
    watchSync.disconnect();
    await voice.disconnect();
    activeRoom = null;
    activeParticipants = const [];
    watchState = null;
    await _syncDevicePip();
    queue = const [];
    suggestions = const [];
    messages = const [];
    replyToMessage = null;
    await store.saveActiveRoomId(null);
    notifyListeners();
    if (room != null) {
      try {
        await api.leaveLiveRoom(room.id);
      } catch (_) {}
    }
  }

  Future<void> logout() async {
    await leaveRoom();
    notificationStream.disconnect();
    await api.logout();
    profile = null;
    rooms = const [];
    notifyListeners();
  }

  void _startRefreshLoop() {
    _refreshTimer?.cancel();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final room = activeRoom;
      if (room != null) {
        try {
          await api.heartbeatLiveRoom(room.id);
        } catch (_) {}
      }
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      final room = activeRoom;
      if (room == null || _refreshing) return;
      _refreshing = true;
      try {
        await _refreshRoomData();
        await _syncDevicePip();
        notifyListeners();
      } catch (exception) {
        error = 'Room connection interrupted: $exception';
        notifyListeners();
      } finally {
        _refreshing = false;
      }
    });
  }

  Future<void> _syncDevicePip() async {
    await DeviceFeatures.setPipAutoEnabled(
      activeRoom != null && floatingVideo && watchState?.playing == true,
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _heartbeatTimer?.cancel();
    watchSync.disconnect();
    notificationStream.disconnect();
    voice.dispose();
    api.dispose();
    super.dispose();
  }
}
