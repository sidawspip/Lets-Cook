class Profile {
  const Profile({
    required this.id,
    required this.displayName,
    required this.username,
    this.avatarUrl,
    this.bio,
  });

  final String id;
  final String displayName;
  final String username;
  final String? avatarUrl;
  final String? bio;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    username: (json['username'] ?? 'member') as String,
    displayName:
        (json['displayName'] ?? json['username'] ?? 'Member') as String,
    avatarUrl: json['avatarUrl'] as String?,
    bio: json['bio'] as String?,
  );
}

class PartyRoom {
  const PartyRoom({
    required this.id,
    required this.name,
    required this.viewerCount,
    this.ownerName,
    this.description,
    this.mediaTitle,
    this.mediaId,
    this.mediaProvider,
    this.thumbnailUrl,
    this.positionSeconds = 0,
    this.durationSeconds,
    this.joined = false,
    this.role = 'MEMBER',
    this.accessPolicy = 'OPEN',
    this.visibility = 'PUBLIC',
  });

  final String id;
  final String name;
  final int viewerCount;
  final String? ownerName;
  final String? description;
  final String? mediaTitle;
  final String? mediaId;
  final String? mediaProvider;
  final String? thumbnailUrl;
  final double positionSeconds;
  final double? durationSeconds;
  final bool joined;
  final String role;
  final String accessPolicy;
  final String visibility;

  PartyRoom copyWith({
    String? name,
    String? description,
    String? role,
    String? accessPolicy,
    String? visibility,
  }) => PartyRoom(
    id: id,
    name: name ?? this.name,
    viewerCount: viewerCount,
    ownerName: ownerName,
    description: description ?? this.description,
    mediaTitle: mediaTitle,
    mediaId: mediaId,
    mediaProvider: mediaProvider,
    thumbnailUrl: thumbnailUrl,
    positionSeconds: positionSeconds,
    durationSeconds: durationSeconds,
    joined: joined,
    role: role ?? this.role,
    accessPolicy: accessPolicy ?? this.accessPolicy,
    visibility: visibility ?? this.visibility,
  );

  factory PartyRoom.fromJson(Map<String, dynamic> json) => PartyRoom(
    id: json['id'] as String,
    name: json['name'] as String,
    viewerCount: (json['viewerCount'] ?? json['memberCount'] ?? 0) as int,
    ownerName: json['ownerName'] as String?,
    description: json['description'] as String?,
    mediaTitle: json['mediaTitle'] as String?,
    mediaId: json['mediaId'] as String?,
    mediaProvider: (json['mediaProvider'] ?? json['provider']) as String?,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    positionSeconds: (json['positionSeconds'] as num? ?? 0).toDouble(),
    durationSeconds: (json['durationSeconds'] as num?)?.toDouble(),
    joined: (json['joined'] ?? true) as bool,
    role: (json['role'] ?? 'MEMBER') as String,
    accessPolicy: (json['accessPolicy'] ?? 'OPEN') as String,
    visibility: (json['visibility'] ?? 'PUBLIC') as String,
  );
}

class RoomWatchState {
  const RoomWatchState({
    this.roomId = '',
    this.provider = 'YOUTUBE',
    this.sourceType = 'YOUTUBE',
    this.sourceUrl,
    this.thumbnailUrl,
    required this.mediaId,
    required this.title,
    required this.playing,
    required this.positionSeconds,
    this.durationSeconds,
    this.playbackRate = 1,
    this.revision = 0,
    this.updatedAt,
    this.serverTime,
  });

  final String roomId;
  final String provider;
  final String sourceType;
  final String? sourceUrl;
  final String? thumbnailUrl;
  final String mediaId;
  final String title;
  final bool playing;
  final double positionSeconds;
  final double? durationSeconds;
  final double playbackRate;
  final int revision;
  final DateTime? updatedAt;
  final DateTime? serverTime;

  RoomWatchState copyWith({
    String? provider,
    String? sourceType,
    String? sourceUrl,
    String? thumbnailUrl,
    String? mediaId,
    String? title,
    bool? playing,
    double? positionSeconds,
    double? durationSeconds,
  }) => RoomWatchState(
    roomId: roomId,
    provider: provider ?? this.provider,
    sourceType: sourceType ?? this.sourceType,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    mediaId: mediaId ?? this.mediaId,
    title: title ?? this.title,
    playing: playing ?? this.playing,
    positionSeconds: positionSeconds ?? this.positionSeconds,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    playbackRate: playbackRate,
    revision: revision,
    updatedAt: updatedAt,
    serverTime: serverTime,
  );

  factory RoomWatchState.fromJson(Map<String, dynamic> json) => RoomWatchState(
    roomId: (json['roomId'] ?? '') as String,
    provider: (json['provider'] ?? 'YOUTUBE') as String,
    sourceType: (json['sourceType'] ?? json['provider'] ?? 'YOUTUBE') as String,
    sourceUrl: json['sourceUrl'] as String?,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    mediaId: json['mediaId'] as String,
    title: (json['title'] ?? 'Now playing') as String,
    playing: (json['playing'] ?? false) as bool,
    positionSeconds: (json['positionSeconds'] as num? ?? 0).toDouble(),
    durationSeconds: (json['durationSeconds'] as num?)?.toDouble(),
    playbackRate: (json['playbackRate'] as num? ?? 1).toDouble(),
    revision: (json['revision'] as num? ?? 0).toInt(),
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    serverTime: DateTime.tryParse(json['serverTime'] as String? ?? ''),
  );
}

class QueueItem {
  const QueueItem({
    required this.id,
    this.provider = 'YOUTUBE',
    required this.mediaId,
    this.sourceUrl,
    required this.title,
    required this.addedBy,
    required this.addedByName,
    this.personalPosition = 0,
    this.personalQueueItem = true,
    this.thumbnailUrl,
    this.voteCount = 0,
    this.votedByMe = false,
    this.pickers = const [],
  });

  final String id;
  final String provider;
  final String mediaId;
  final String? sourceUrl;
  final String title;
  final String addedBy;
  final String addedByName;
  final int personalPosition;
  final bool personalQueueItem;
  final String? thumbnailUrl;
  final int voteCount;
  final bool votedByMe;
  final List<QueuePicker> pickers;

  factory QueueItem.fromJson(Map<String, dynamic> json) => QueueItem(
    id: json['id'] as String,
    provider: (json['provider'] ?? 'YOUTUBE') as String,
    mediaId: json['mediaId'] as String,
    sourceUrl: json['sourceUrl'] as String?,
    title: json['title'] as String,
    addedBy: (json['addedBy'] ?? '').toString(),
    addedByName: (json['addedByName'] ?? 'Member') as String,
    personalPosition: (json['personalPosition'] as num? ?? 0).toInt(),
    personalQueueItem: (json['personalQueueItem'] as bool?) ?? true,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    voteCount: (json['voteCount'] ?? 0) as int,
    votedByMe: (json['votedByMe'] ?? false) as bool,
    pickers: (json['pickers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(QueuePicker.fromJson)
        .toList(growable: false),
  );
}

class QueuePicker {
  const QueuePicker({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;

  factory QueuePicker.fromJson(Map<String, dynamic> json) => QueuePicker(
    userId: (json['userId'] ?? '').toString(),
    displayName: (json['displayName'] ?? 'Member').toString(),
    avatarUrl: json['avatarUrl'] as String?,
  );
}

class VideoSuggestion {
  const VideoSuggestion({
    required this.videoId,
    required this.title,
    required this.channelTitle,
    required this.thumbnailUrl,
    this.provider = 'YOUTUBE',
    this.sourceUrl,
    this.sourceType,
  });

  final String videoId;
  final String title;
  final String channelTitle;
  final String thumbnailUrl;
  final String provider;
  final String? sourceUrl;
  final String? sourceType;

  factory VideoSuggestion.fromJson(Map<String, dynamic> json) =>
      VideoSuggestion(
        videoId: json['videoId'] as String,
        title: json['title'] as String,
        channelTitle: (json['channelTitle'] ?? 'YouTube') as String,
        thumbnailUrl: (json['thumbnailUrl'] ?? '') as String,
        provider: (json['provider'] ?? 'YOUTUBE') as String,
        sourceUrl: json['sourceUrl'] as String?,
        sourceType: json['sourceType'] as String?,
      );
}

/// Provider-neutral media selected by discovery before it is routed to a room.
///
/// Provider adapters are responsible for producing this resource. The room
/// controller then applies the same create/play-or-queue policy to every
/// provider.
class MediaResource {
  const MediaResource({
    required this.provider,
    required this.mediaId,
    this.sourceUrl,
    required this.title,
    this.thumbnailUrl,
    this.channelTitle,
    this.sourcePageUrl,
  });

  final String provider;
  final String mediaId;

  /// The currently resolved stream. For scraped Web media [mediaId] remains
  /// the durable page URL while this value may be refreshed when it expires.
  final String? sourceUrl;
  final String title;
  final String? thumbnailUrl;
  final String? channelTitle;
  final String? sourcePageUrl;

  String get normalizedProvider => provider.trim().toUpperCase();
  bool get isYoutube => normalizedProvider == 'YOUTUBE';
  bool get isDirect => normalizedProvider.startsWith('DIRECT_');

  factory MediaResource.fromVideo(VideoSuggestion video) => MediaResource(
    provider: video.provider,
    mediaId: video.videoId,
    title: video.title,
    thumbnailUrl: video.thumbnailUrl,
    channelTitle: video.channelTitle,
  );

  VideoSuggestion toVideoSuggestion({String? channelTitle}) => VideoSuggestion(
    videoId: mediaId,
    title: title,
    channelTitle: channelTitle ?? this.channelTitle ?? provider,
    thumbnailUrl: thumbnailUrl ?? '',
    provider: provider,
    sourceUrl: sourceUrl,
    sourceType: isDirect ? normalizedProvider : null,
  );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderUsername,
    required this.body,
    required this.type,
    required this.createdAt,
    this.avatarUrl,
    this.replyTo,
    this.reactions = const [],
    this.mediaProvider,
    this.mediaId,
    this.mediaTitle,
    this.isMine = false,
  });

  final String id;
  final String senderId;
  final String senderName;
  final String senderUsername;
  final String body;
  final String type;
  final DateTime createdAt;
  final String? avatarUrl;
  final ChatReply? replyTo;
  final List<ChatReaction> reactions;
  final String? mediaProvider;
  final String? mediaId;
  final String? mediaTitle;
  final bool isMine;

  bool get isSystem => type != 'MESSAGE';

  ChatMessage copyWith({List<ChatReaction>? reactions}) => ChatMessage(
    id: id,
    senderId: senderId,
    senderName: senderName,
    senderUsername: senderUsername,
    body: body,
    type: type,
    createdAt: createdAt,
    avatarUrl: avatarUrl,
    replyTo: replyTo,
    reactions: reactions ?? this.reactions,
    mediaProvider: mediaProvider,
    mediaId: mediaId,
    mediaTitle: mediaTitle,
    isMine: isMine,
  );

  factory ChatMessage.fromJson(
    Map<String, dynamic> json,
    String myId,
  ) => ChatMessage(
    id: json['id'] as String,
    senderId: (json['senderId'] ?? '') as String,
    senderName: (json['senderName'] ?? 'Member') as String,
    senderUsername: (json['senderUsername'] ?? '') as String,
    body: json['body'] as String,
    type: (json['type'] ?? 'MESSAGE') as String,
    avatarUrl: json['avatarUrl'] as String?,
    replyTo: json['replyTo'] is Map
        ? ChatReply.fromJson(Map<String, dynamic>.from(json['replyTo'] as Map))
        : null,
    reactions: (json['reactions'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              ChatReaction.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false),
    mediaProvider: json['mediaProvider'] as String?,
    mediaId: json['mediaId'] as String?,
    mediaTitle: json['mediaTitle'] as String?,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    isMine: json['senderId'] == myId,
  );
}

class ChatReply {
  const ChatReply({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderUsername,
    required this.body,
    required this.type,
  });

  final String id;
  final String senderId;
  final String senderName;
  final String senderUsername;
  final String body;
  final String type;

  factory ChatReply.fromJson(Map<String, dynamic> json) => ChatReply(
    id: json['id'] as String,
    senderId: (json['senderId'] ?? '') as String,
    senderName: (json['senderName'] ?? 'Member') as String,
    senderUsername: (json['senderUsername'] ?? '') as String,
    body: (json['body'] ?? '') as String,
    type: (json['type'] ?? 'MESSAGE') as String,
  );
}

class ChatReaction {
  const ChatReaction({
    required this.reaction,
    required this.count,
    required this.reactedByMe,
  });

  final String reaction;
  final int count;
  final bool reactedByMe;

  factory ChatReaction.fromJson(Map<String, dynamic> json) => ChatReaction(
    reaction: (json['reaction'] ?? '') as String,
    count: (json['count'] as num? ?? 0).toInt(),
    reactedByMe: json['reactedByMe'] == true,
  );
}

class DirectMessage {
  const DirectMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.body,
    required this.createdAt,
    this.attachmentType,
    this.attachmentUrl,
    this.attachmentName,
  });

  final String id;
  final String senderId;
  final String recipientId;
  final String body;
  final DateTime createdAt;
  final String? attachmentType;
  final String? attachmentUrl;
  final String? attachmentName;

  factory DirectMessage.fromJson(Map<String, dynamic> json) => DirectMessage(
    id: json['id'] as String,
    senderId: json['senderId'] as String,
    recipientId: json['recipientId'] as String,
    body: json['body'] as String,
    attachmentType: json['attachmentType'] as String?,
    attachmentUrl: json['attachmentUrl'] as String?,
    attachmentName: json['attachmentName'] as String?,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}
