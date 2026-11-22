import type { PartyRoom, RoomWatchState, QueueItem, Profile, VideoSuggestion, ChatMessage, DirectMessage, ViewingActivity, MediaToken, StoredSession, VoiceMember } from './models';

export interface IpcChannels {
  // Auth
  'auth:login': { username: string; password: string };
  'auth:logout': void;
  'auth:restore': void;
  'auth:state': { authenticated: boolean; profile?: Profile };

  // Rooms
  'rooms:create': { name?: string };
  'rooms:open': { room: PartyRoom; accessKey?: string };
  'rooms:leave': void;
  'rooms:refresh': void;
  'rooms:list': PartyRoom[];

  // Watch sync
  'watch:state': RoomWatchState | null;
  'watch:play': { position: number };
  'watch:pause': { position: number };
  'watch:seek': { position: number };
  'watch:set-rate': { rate: number };
  'watch:queue': QueueItem[];
  'watch:queue-mode': string;
  'watch:add-to-queue': { item: VideoSuggestion; targetRoomId?: string };
  'watch:play-queue-item': { queueId: string };
  'watch:select-queue-item': { queueId: string };
  'watch:vote-queue-item': { queueId: string };
  'watch:remove-from-queue': { queueId: string };

  // Chat
  'chat:messages': ChatMessage[];
  'chat:send': { body: string; replyToId?: string };
  'chat:react': { messageId: string; reaction: string };
  'chat:reply': { messageId: string; tag?: boolean };

  // Voice
  'voice:connect': { roomId: string };
  'voice:disconnect': void;
  'voice:toggle-mic': void;
  'voice:toggle-speaker': void;
  'voice:toggle-screen-share': void;
  'voice:state': { connected: boolean; micEnabled: boolean; screenShareEnabled: boolean; members: VoiceMember[] };

  // Media discovery
  'media:search': { query: string; results: VideoSuggestion[] };
  'media:resolve': { mediaId: string; provider: string; result: { uri: string; headers: Record<string, string> } };

  // Profile
  'profile:get': Profile | null;
  'profile:update-prefs': { prefs: Record<string, unknown> };

  // Notifications
  'notifications:connect': void;
  'notifications:event': { type: string; payload: unknown };

  // Dart backend
  'dart:invoke': { method: string; args: unknown[] };
  'dart:event': { event: string; data: unknown };
}

export type IpcRenderer = {
  invoke<K extends keyof IpcChannels>(channel: K, ...args: IpcChannels[K] extends void ? [] : [IpcChannels[K]]): Promise<IpcChannels[K] extends { then: unknown } ? Awaited<IpcChannels[K]> : IpcChannels[K]>;
  on<K extends keyof IpcChannels>(channel: K, listener: (data: IpcChannels[K]) => void): () => void;
  once<K extends keyof IpcChannels>(channel: K, listener: (data: IpcChannels[K]) => void): () => void;
};

declare global {
  interface Window {
    xynkDesktop: {
      minimize(): Promise<void>;
      maximize(): Promise<void>;
      close(): Promise<void>;
      isMaximized(): Promise<boolean>;
      loginWithProvider(provider: 'google' | 'x'): Promise<StoredSession>;
      register(): Promise<void>;
      prepareCrunchyroll(episodeId: string): Promise<{manifestUrl: string}>;
      requestCrunchyrollLicense(challenge: Uint8Array): Promise<Uint8Array>;
      resolveYouTube(videoId: string, quality?: string): Promise<{url: string; quality: string; qualities: string[]}>;
      getScreenSources(): Promise<Array<{id: string; name: string; thumbnail: string}>>;
      selectScreenSource(sourceId: string): Promise<void>;
    };
    ipc: IpcRenderer;
    dart: {
      invoke(method: string, args: unknown[]): Promise<unknown>;
      on(event: string, listener: (data: unknown) => void): () => void;
    };
  }
}
