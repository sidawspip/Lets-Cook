export interface Profile {
  id: string;
  displayName: string;
  username: string;
  avatarUrl?: string;
  bio?: string;
}

export interface PartyRoom {
  id: string;
  name: string;
  viewerCount: number;
  ownerName?: string;
  description?: string;
  mediaTitle?: string;
  mediaId?: string;
  mediaProvider?: string;
  thumbnailUrl?: string;
  positionSeconds: number;
  durationSeconds?: number;
  joined: boolean;
  role: string;
  accessPolicy: string;
  visibility: string;
}

export interface RoomWatchState {
  roomId: string;
  provider: string;
  sourceType: string;
  sourceUrl?: string;
  thumbnailUrl?: string;
  mediaId: string;
  title: string;
  playing: boolean;
  positionSeconds: number;
  durationSeconds?: number;
  playbackRate: number;
  revision: number;
  updatedAt?: Date;
  serverTime?: Date;
}

export interface QueueItem {
  id: string;
  provider: string;
  mediaId: string;
  title: string;
  addedBy: string;
  addedByName: string;
  personalPosition: number;
  personalQueueItem: boolean;
  thumbnailUrl?: string;
  sourceUrl?: string;
  voteCount: number;
  votedByMe: boolean;
  pickers: QueuePicker[];
}

export interface QueuePicker {
  userId: string;
  displayName: string;
  avatarUrl?: string;
}

export interface VideoSuggestion {
  videoId: string;
  title: string;
  channelTitle: string;
  thumbnailUrl: string;
  provider: string;
}

export interface ChatMessage {
  id: string;
  senderId: string;
  senderName: string;
  senderUsername: string;
  body: string;
  type: string;
  createdAt: Date;
  avatarUrl?: string;
  replyTo?: ChatReply;
  reactions: ChatReaction[];
  mediaProvider?: string;
  mediaId?: string;
  mediaTitle?: string;
  isMine: boolean;
}

export interface ChatReply {
  id: string;
  senderId: string;
  senderName: string;
  senderUsername: string;
  body: string;
  type: string;
}

export interface ChatReaction {
  reaction: string;
  count: number;
  reactedByMe: boolean;
}

export interface DirectMessage {
  id: string;
  senderId: string;
  recipientId: string;
  body: string;
  createdAt: Date;
  attachmentType?: string;
  attachmentUrl?: string;
  attachmentName?: string;
}

export interface ViewingActivity {
  mediaId: string;
  title: string;
  provider: string;
  thumbnailUrl: string;
  watchedAt: Date;
  sensitive: boolean;
  views: number;
  sourceUrl?: string;
  sourceType?: string;
}

export interface StoredSession {
  accessToken: string;
  refreshToken: string;
  expiresAt: string;
}

export interface MediaToken {
  url: string;
  token: string;
  roomName: string;
  canPublish: boolean;
}

export type RoomPanel = 'chat' | 'queue' | 'people';

export interface VoiceMember {
  identity: string;
  name: string;
  microphoneOn: boolean;
  speaking: boolean;
}

export interface ResolvedMedia {
  uri: string;
  title?: string;
  qualities: string[];
  captionLanguages: Record<string, string>;
  httpHeaders: Record<string, string>;
}

export interface CaptionCue {
  text: string;
  start: number;
  end: number;
}