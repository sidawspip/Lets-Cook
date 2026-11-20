import 'package:flutter_test/flutter_test.dart';
import 'package:lets_cook_windows/models/models.dart';
import 'package:lets_cook_windows/services/lets_cook_api.dart';
import 'package:lets_cook_windows/services/session_store.dart';
import 'package:lets_cook_windows/state/watch_party_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('history preserves playable source separately from its page identity', () async {
    final api = _FakeLetsCookApi();
    final controller = _FlowTestController(api);
    addTearDown(controller.dispose);
    await controller.selectDirectVideo('https://cdn.example/stream.mp4',
        sourceType: 'DIRECT_MP4', sourcePageUrl: 'https://site.example/watch/1',
        title: 'Saved video');
    await Future<void>.delayed(Duration.zero);
    expect(controller.history.single.mediaId, 'https://site.example/watch/1');
    expect(controller.history.single.sourceUrl, 'https://cdn.example/stream.mp4');
    expect(controller.history.single.sourceType, 'DIRECT_MP4');
    expect(ViewingActivity.fromJson(controller.history.single.toJson()).sourceUrl,
        'https://cdn.example/stream.mp4');
  });

  test('legacy web history refreshes into direct playback without provider browser', () async {
    final api = _FakeLetsCookApi();
    final controller = _FlowTestController(api);
    addTearDown(controller.dispose);
    await controller.selectLibraryItem(ViewingActivity(
      mediaId: 'https://site.example/watch/1', title: 'Legacy video',
      provider: 'WEB', thumbnailUrl: '', watchedAt: DateTime(2026), sensitive: false));
    expect(api.resolveCalls, 1);
    expect(api.items.single.sourceUrl, 'https://cdn.example/refreshed.mp4');
    expect(api.items.single.mediaId, 'https://site.example/watch/1');
    expect(api.items.single.provider, 'DIRECT_MP4');
    expect(api.playCalls, 1);
  });

  test('starts signed out without preview or seeded room data', () {
    final controller = WatchPartyController();
    addTearDown(controller.dispose);

    expect(controller.authenticated, isFalse);
    expect(controller.rooms, isEmpty);
    expect(controller.queue, isEmpty);
    expect(controller.suggestions, isEmpty);
    expect(controller.messages, isEmpty);
  });

  test('local player preferences remain local', () {
    final controller = WatchPartyController();
    addTearDown(controller.dispose);

    controller.setMuted(true);
    controller.setVolume(.55);
    controller.setCaption('hi');
    controller.setQuality('720p');

    expect(controller.volume, .55);
    expect(controller.muted, isFalse);
    expect(controller.selectedCaption, 'hi');
    expect(controller.selectedQuality, '720p');
  });

  test('recommendation labels follow the active media context', () {
    final controller = WatchPartyController();
    addTearDown(controller.dispose);

    controller.watchState = const RoomWatchState(
      mediaId: 'music-track',
      title: 'Artist - Song (Official Video)',
      playing: true,
      positionSeconds: 0,
    );
    expect(controller.suggestionSectionTitle, 'SIMILAR SONGS');
    expect(controller.suggestionItemLabel, 'SIMILAR SONG');

    controller.watchState = const RoomWatchState(
      provider: 'CRUNCHYROLL',
      sourceType: 'CRUNCHYROLL',
      mediaId: 'episode-4',
      title: 'Example Series Season 1 Episode 4',
      playing: true,
      positionSeconds: 0,
    );
    expect(controller.suggestionSectionTitle, 'NEXT EPISODES');
    expect(controller.suggestionItemLabel, 'NEXT EPISODE');

    controller.watchState = const RoomWatchState(
      provider: 'DIRECT_HLS',
      sourceType: 'DIRECT_HLS',
      sourceUrl: 'https://example.test/show/episode-4.m3u8',
      mediaId: 'https://example.test/show/episode-4.m3u8',
      title: 'Documentary clip',
      playing: true,
      positionSeconds: 0,
    );
    expect(controller.suggestionSectionTitle, 'MORE FROM THIS WEB SOURCE');
  });

  test(
    'home selection creates a room, queues, then starts the video',
    () async {
      final api = _FakeLetsCookApi();
      final controller = _FlowTestController(api);
      addTearDown(controller.dispose);

      await controller.selectYoutubeVideo(_video('home-video'));

      expect(api.createCalls, 1);
      expect(api.addCalls, 1);
      expect(api.playCalls, 1);
      expect(controller.activeRoom?.id, 'room-1');
      expect(controller.watchState?.mediaId, 'home-video');
      expect(controller.shelfOpen, isFalse);
    },
  );

  test(
    'host in-room selection queues without replacing current playback',
    () async {
      final api = _FakeLetsCookApi();
      final controller = _FlowTestController(api)
        ..activeRoom = _room
        ..watchState = _watch('currently-playing');
      addTearDown(controller.dispose);

      await controller.selectYoutubeVideo(
        _video('queued-video'),
        targetRoomId: _room.id,
      );

      expect(api.createCalls, 0);
      expect(api.addCalls, 1);
      expect(api.playCalls, 0);
      expect(controller.watchState?.mediaId, 'currently-playing');
      expect(controller.queue.single.mediaId, 'queued-video');
      expect(controller.shelfOpen, isTrue);
    },
  );

  test('host starts YouTube immediately when the room is idle', () async {
    final api = _FakeLetsCookApi();
    final controller = _FlowTestController(api)
      ..activeRoom = _room
      ..canAddToQueue = true;
    addTearDown(controller.dispose);

    await controller.selectYoutubeVideo(
      _video('idle-youtube'),
      targetRoomId: _room.id,
    );

    expect(api.playCalls, 1);
    expect(controller.watchState?.mediaId, 'idle-youtube');
    expect(controller.shelfOpen, isFalse);
  });

  test(
    'host starts provider media immediately when the room is idle',
    () async {
      final api = _FakeLetsCookApi();
      final controller = _FlowTestController(api)
        ..activeRoom = _room
        ..canAddToQueue = true;
      addTearDown(controller.dispose);

      await controller.selectProviderMedia(
        provider: 'VIMEO',
        mediaId: 'provider-video',
        title: 'Provider video',
        targetRoomId: _room.id,
      );

      expect(api.playCalls, 1);
      expect(controller.watchState?.mediaId, 'provider-video');
      expect(controller.shelfOpen, isFalse);
    },
  );

  test('host starts direct media immediately when the room is idle', () async {
    final api = _FakeLetsCookApi();
    final controller = _FlowTestController(api)
      ..activeRoom = _room
      ..canAddToQueue = true;
    addTearDown(controller.dispose);

    await controller.selectDirectVideo(
      'https://example.test/idle.mp4',
      targetRoomId: _room.id,
      title: 'Direct video',
    );

    expect(api.playCalls, 1);
    expect(controller.watchState?.mediaId, 'https://example.test/idle.mp4');
    expect(controller.shelfOpen, isFalse);
  });

  test('web selection keeps the page identity and queues resolved stream', () async {
    final api = _FakeLetsCookApi();
    final controller = _FlowTestController(api)..activeRoom = _room;
    addTearDown(controller.dispose);

    await controller.selectDirectVideo(
      'https://cdn.example.test/signed/video.mp4?expires=1',
      sourcePageUrl: 'https://example.test/watch/video',
      targetRoomId: _room.id,
      title: 'Web video',
    );

    expect(api.items.single.mediaId, 'https://example.test/watch/video');
    expect(
      api.items.single.sourceUrl,
      'https://cdn.example.test/signed/video.mp4?expires=1',
    );
  });

  test('queue vote is single-choice, ranked, and toggles off', () async {
    final api = _FakeLetsCookApi()
      ..items = [_queueItem('first', selected: true), _queueItem('second')];
    final controller = _FlowTestController(api)
      ..activeRoom = _room
      ..queue = List.of(api.items);
    addTearDown(controller.dispose);

    await controller.selectQueueItem(controller.queue.last);
    expect(controller.queue.first.mediaId, 'second');
    expect(controller.queue.first.votedByMe, isTrue);
    expect(controller.queue.last.votedByMe, isFalse);

    await controller.selectQueueItem(controller.queue.first);
    expect(controller.queue.every((item) => !item.votedByMe), isTrue);
  });

  test('chat video opens inside the room by adding it to the queue', () async {
    final api = _FakeLetsCookApi();
    final controller = _FlowTestController(api)
      ..activeRoom = _room
      ..watchState = _watch('currently-playing');
    addTearDown(controller.dispose);

    await controller.openTimelineVideo(_videoMessage('shared-video'));

    expect(api.addCalls, 1);
    expect(api.playCalls, 0);
    expect(controller.watchState?.mediaId, 'currently-playing');
    expect(controller.queue.single.mediaId, 'shared-video');
    expect(controller.shelfOpen, isTrue);
  });

  test('selected queue video can be shared into room chat', () async {
    final api = _FakeLetsCookApi();
    final controller = _FlowTestController(api)
      ..activeRoom = _room
      ..profile = const Profile(
        id: 'member-1',
        displayName: 'Member',
        username: 'member',
      );
    addTearDown(controller.dispose);

    await controller.shareQueueItemToChat(_queueItem('shared-video'));

    expect(api.shareCalls, 1);
    expect(controller.messages.single.mediaId, 'shared-video');
    expect(controller.panel, RoomPanel.chat);
  });
}

const _room = PartyRoom(
  id: 'room-1',
  name: 'Flow test',
  viewerCount: 1,
  joined: true,
  role: 'HOST',
);

VideoSuggestion _video(String id) => VideoSuggestion(
  videoId: id,
  title: 'Video $id',
  channelTitle: 'Test channel',
  thumbnailUrl: 'https://example.test/$id.jpg',
);

RoomWatchState _watch(String id) => RoomWatchState(
  roomId: _room.id,
  mediaId: id,
  title: 'Video $id',
  playing: true,
  positionSeconds: 12,
);

QueueItem _queueItem(String id, {bool selected = false}) => QueueItem(
  id: 'queue-$id',
  mediaId: id,
  title: 'Video $id',
  addedBy: 'member-1',
  addedByName: 'Member',
  voteCount: selected ? 1 : 0,
  votedByMe: selected,
);

ChatMessage _videoMessage(String id) => ChatMessage(
  id: 'message-$id',
  senderId: 'member-2',
  senderName: 'Friend',
  senderUsername: 'friend',
  body: 'selected a video',
  type: 'VIDEO',
  mediaProvider: 'YOUTUBE',
  mediaId: id,
  mediaTitle: 'Video $id',
  createdAt: DateTime(2026),
);

class _FlowTestController extends WatchPartyController {
  _FlowTestController(_FakeLetsCookApi api)
    : super(store: SessionStore(), api: api);

  @override
  Future<void> openRoom(
    PartyRoom room, {
    bool restoring = false,
    String accessKey = '',
  }) async {
    final fake = api as _FakeLetsCookApi;
    activeRoom = room;
    watchState = fake.currentWatch;
    queue = List.of(fake.items);
    shelfOpen = false;
    notifyListeners();
  }
}

class _FakeLetsCookApi extends LetsCookApi {
  _FakeLetsCookApi() : super(SessionStore());

  int createCalls = 0;
  int addCalls = 0;
  int playCalls = 0;
  int shareCalls = 0;
  RoomWatchState? currentWatch;
  List<QueueItem> items = [];
  int resolveCalls = 0;

  @override
  Future<Map<String, dynamic>> resolveWebMedia(String pageUrl) async {
    resolveCalls++;
    return {'sourceUrl': 'https://cdn.example/refreshed.mp4', 'sourceType': 'DIRECT_MP4'};
  }

  @override
  Future<Map<String, dynamic>> recordMedia({
    required String mediaId, required String provider, required String title,
    String? thumbnailUrl, String? sourceUrl, String? sourceType, int watchSeconds = 0,
  }) async => {
    'mediaId': mediaId, 'provider': provider, 'title': title,
    'thumbnailUrl': thumbnailUrl, 'sourceUrl': sourceUrl, 'sourceType': sourceType,
  };

  @override
  Future<PartyRoom> createRoom(String name) async {
    createCalls++;
    return _room;
  }

  @override
  Future<QueueItem> addToQueue(
    String roomId,
    VideoSuggestion video, {
    bool personalQueueItem = true,
  }) async {
    addCalls++;
    final existing = items
        .where((item) => item.mediaId == video.videoId)
        .firstOrNull;
    if (existing != null) {
      _select(existing.id);
      return items.firstWhere((item) => item.id == existing.id);
    }
    final item = QueueItem(
      id: 'queue-${video.videoId}',
      mediaId: video.videoId,
      title: video.title,
      addedBy: 'member-1',
      addedByName: 'Member',
      voteCount: items.isEmpty ? 1 : 0,
      votedByMe: items.isEmpty,
    );
    items = [...items, item];
    return item;
  }

  @override
  Future<QueueItem> addProviderToQueue(
    String roomId, {
    required String provider,
    required String mediaId,
    required String title,
    String? thumbnailUrl,
  }) async => _addMedia(
    provider: provider,
    mediaId: mediaId,
    title: title,
    thumbnailUrl: thumbnailUrl,
  );

  @override
  Future<QueueItem> addDirectToQueue(
    String roomId,
    String provider,
    String mediaId, {
    String? sourceUrl,
    String? title,
    String? thumbnailUrl,
  }) async => _addMedia(
    provider: provider,
    mediaId: mediaId,
    sourceUrl: sourceUrl,
    title: title ?? 'Direct video',
    thumbnailUrl: thumbnailUrl,
  );

  QueueItem _addMedia({
    required String provider,
    required String mediaId,
    required String title,
    String? sourceUrl,
    String? thumbnailUrl,
  }) {
    addCalls++;
    final item = QueueItem(
      id: 'queue-$mediaId',
      provider: provider,
      mediaId: mediaId,
      sourceUrl: sourceUrl,
      title: title,
      addedBy: 'member-1',
      addedByName: 'Member',
      thumbnailUrl: thumbnailUrl,
      voteCount: items.isEmpty ? 1 : 0,
      votedByMe: items.isEmpty,
    );
    items = [...items, item];
    return item;
  }

  @override
  Future<RoomWatchState> playQueueItem(String roomId, String queueId) async {
    playCalls++;
    final item = items.firstWhere((candidate) => candidate.id == queueId);
    currentWatch = _watch(item.mediaId);
    return currentWatch!;
  }

  @override
  Future<List<QueueItem>> watchQueue(String roomId) async => List.of(items);

  @override
  Future<List<QueueItem>> voteQueueItem(String roomId, String queueId) async {
    final selected = items.firstWhere((item) => item.id == queueId);
    if (selected.votedByMe) {
      items = items.map((item) => _copy(item, selected: false)).toList();
    } else {
      _select(queueId);
    }
    items.sort((a, b) => b.voteCount.compareTo(a.voteCount));
    return List.of(items);
  }

  @override
  Future<ChatMessage> shareRoomVideo(
    String roomId,
    String myId, {
    required String provider,
    required String mediaId,
    required String title,
  }) async {
    shareCalls++;
    return ChatMessage(
      id: 'shared-$mediaId',
      senderId: myId,
      senderName: 'Member',
      senderUsername: 'member',
      body: 'selected a video',
      type: 'VIDEO',
      mediaProvider: provider,
      mediaId: mediaId,
      mediaTitle: title,
      createdAt: DateTime(2026),
      isMine: true,
    );
  }

  void _select(String queueId) {
    items = items
        .map((item) => _copy(item, selected: item.id == queueId))
        .toList();
  }

  QueueItem _copy(QueueItem item, {required bool selected}) => QueueItem(
    id: item.id,
    provider: item.provider,
    mediaId: item.mediaId,
    title: item.title,
    addedBy: item.addedBy,
    addedByName: item.addedByName,
    personalPosition: item.personalPosition,
    personalQueueItem: item.personalQueueItem,
    thumbnailUrl: item.thumbnailUrl,
    voteCount: selected ? 1 : 0,
    votedByMe: selected,
    pickers: item.pickers,
  );
}
