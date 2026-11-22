import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import { api } from '../services/api';
import { roomVoice } from '../services/room-voice';
import { notifications } from '../services/notifications';
import type { PartyRoom, RoomWatchState, QueueItem, Profile, VideoSuggestion, ChatMessage } from '../types/models';

async function createVideoRoom(title: string): Promise<PartyRoom> {
  const name = title.trim().slice(0, 120) || 'Watch party';
  try {
    return (await api.createRoom(name)).room as PartyRoom;
  } catch (error) {
    if (!(error instanceof Error) || !/room name is already taken/i.test(error.message)) throw error;
  }
  // Room names are globally unique, while different parties can watch the same video.
  // Preserve the media title in the queue/watch state and disambiguate only the room name.
  for (let attempt = 0; attempt < 3; attempt++) {
    const suffix = ` · ${crypto.randomUUID().slice(0, 8)}`;
    try {
      return (await api.createRoom(`${name.slice(0, 120 - suffix.length)}${suffix}`)).room as PartyRoom;
    } catch (error) {
      if (!(error instanceof Error) || !/room name is already taken/i.test(error.message)) throw error;
    }
  }
  throw new Error('Could not create a room. Please try again.');
}

interface WatchPartyState {
  displayName: string;
  checkingVideoAccess: boolean;
  canControlWatch: boolean;
  fullyConnected: boolean;
  reconnecting: boolean;
  savingProfilePreferences: Set<string>;
  hapticFeedback: boolean;
  autoTranslate: boolean;
  hideLocation: boolean;
  restrictInvites: boolean;
  preferredLanguage: string;
  quickReaction: string;
  profileVisibility: Record<string, string>;
  setProfilePreference: (key: string, value: boolean | string) => Promise<void>;
  saveProfilePreferences: () => Promise<void>;
  setProfileVisibility: (section: string, visibility: string) => Promise<void>;
  selectedQuality: string;
  selectedCaption: string;
  qualities: string[];
  setAvailableQualities: (qualities: string[]) => void;
  captionLanguages: Record<string, string>;
  setQuality: (quality: string) => void;
  setCaption: (language: string) => void;
  addSuggestion: (video: VideoSuggestion) => Promise<void>;
  voice: typeof roomVoice;
  voiceRevision: number;
  activeParticipants: Array<{userId: string; displayName: string; username: string; avatarUrl?: string; role: string; canShareScreen: boolean; canViewVideo: boolean; canAddVideos: boolean; screenShareRequested: boolean; videoAccessRequested: boolean}>;
  toggleMicrophone: () => Promise<void>;
  toggleSpeaker: () => Promise<void>;
  toggleScreenShare: () => Promise<void>;
  muted: boolean;
  volume: number;
  setMuted: (muted: boolean) => void;
  setVolume: (volume: number) => void;
  togglePlayback: () => Promise<void>;
  seek: (seconds: number) => Promise<void>;
  busy: boolean;
  initialize: () => Promise<void>;
  login: (username: string, password: string) => Promise<void>;
  loginWithProvider: (provider: 'google' | 'x') => Promise<void>;
  logout: () => Promise<void>;
  refreshHomeRooms: () => Promise<void>;
  openRoom: (room: PartyRoom, accessKey?: string) => Promise<void>;
  leaveRoom: () => Promise<void>;
  sendMessage: (body: string) => Promise<void>;
  replyToMessage: ChatMessage | null;
  beginReply: (message: ChatMessage) => void;
  cancelReply: () => void;
  reactToMessage: (messageId: string, reaction: string) => Promise<void>;
  selectQueueItem: (item: QueueItem) => Promise<void>;
  searchVideos: (query: string) => Promise<VideoSuggestion[]>;
  selectYoutubeVideo: (video: VideoSuggestion, targetRoomId?: string) => Promise<void>;
  selectCrunchyrollVideo: (episodeId: string, title: string, thumbnailUrl?: string, targetRoomId?: string) => Promise<void>;
  selectDirectVideo: (url: string, targetRoomId?: string) => Promise<void>;
  createDirectParty: (url: string) => Promise<void>;
  // Auth
  initializing: boolean;
  authenticated: boolean;
  profile: Profile | null;
  setProfile: (p: Profile | null) => void;
  setAuthenticated: (v: boolean) => void;
  setInitializing: (v: boolean) => void;

  // Rooms
  rooms: PartyRoom[];
  activeRoom: PartyRoom | null;
  visibleRooms: PartyRoom[];
  setRooms: (r: PartyRoom[]) => void;
  setActiveRoom: (r: PartyRoom | null) => void;
  setVisibleRooms: (r: PartyRoom[]) => void;

  // Watch state
  watchState: RoomWatchState | null;
  setWatchState: (s: RoomWatchState | null) => void;
  updatePosition: (pos: number) => void;
  setPlaying: (v: boolean) => void;

  // Queue
  queue: QueueItem[];
  roomQueue: QueueItem[];
  personalQueue: QueueItem[];
  setQueue: (q: QueueItem[]) => void;
  addToQueue: (item: QueueItem) => void;
  removeFromQueue: (id: string) => void;
  voteQueueItem: (id: string) => void;

  // Suggestions
  suggestions: VideoSuggestion[];
  setSuggestions: (s: VideoSuggestion[]) => void;

  // Chat
  messages: ChatMessage[];
  setMessages: (m: ChatMessage[]) => void;
  addMessage: (msg: ChatMessage) => void;

  // Media
  canViewVideo: boolean;
  setCanViewVideo: (v: boolean) => void;

  // UI
  shelfOpen: boolean;
  setShelfOpen: (v: boolean) => void;
  panel: 'chat' | 'queue' | 'people';
  setPanel: (p: 'chat' | 'queue' | 'people') => void;

  // Preferences
  hideSensitiveContent: boolean;
  setHideSensitiveContent: (v: boolean) => void;
  floatingVideo: boolean;
  setFloatingVideo: (v: boolean) => void;
  muteOtherAudio: boolean;
  setMuteOtherAudio: (v: boolean) => void;

  // Errors
  error: string | null;
  setError: (e: string | null) => void;
}

let roomRefreshTimer: ReturnType<typeof setInterval> | null = null;
let roomRefreshBusy = false;

export const useWatchPartyStore = create<WatchPartyState>()(
  persist(
    (set, get) => ({
      displayName: '',
      checkingVideoAccess: false,
      canControlWatch: false,
      fullyConnected: false,
      reconnecting: false,
      savingProfilePreferences: new Set<string>(),
      hapticFeedback: false,
      autoTranslate: false,
      hideLocation: false,
      restrictInvites: false,
      preferredLanguage: 'en',
      quickReaction: '❤️',
      profileVisibility: {},
      setProfilePreference: async (key, value) => {
        set({[key]: value} as Partial<WatchPartyState>);
        const saving = new Set(get().savingProfilePreferences).add(key);
        set({savingProfilePreferences: saving});
        try { await api.updateProfile({[key]: value}); }
        catch (error) { set({error: String(error)}); throw error; }
        finally { const next = new Set(get().savingProfilePreferences); next.delete(key); set({savingProfilePreferences: next}); }
      },
      saveProfilePreferences: async () => {
        const {hideSensitiveContent, floatingVideo, muteOtherAudio, hapticFeedback, autoTranslate, hideLocation, restrictInvites, preferredLanguage, quickReaction} = get();
        await api.updateProfile({hideSensitiveContent, floatingVideo, muteOtherAudio, hapticFeedback, autoTranslate, hideLocation, restrictInvites, preferredLanguage, quickReaction});
      },
      setProfileVisibility: async (section, visibility) => {
        const next = {...get().profileVisibility, [section]: visibility};
        await api.updateProfileVisibility(next);
        set({profileVisibility: next});
      },
      selectedQuality: 'auto',
      selectedCaption: 'off',
      qualities: ['auto'],
      setAvailableQualities: qualities => set({qualities}),
      captionLanguages: {},
      setQuality: selectedQuality => set({selectedQuality}),
      setCaption: selectedCaption => set({selectedCaption}),
      addSuggestion: video => get().selectYoutubeVideo(video, get().activeRoom?.id),
      voice: roomVoice,
      voiceRevision: 0,
      activeParticipants: [],
      toggleMicrophone: async () => {
        const room = get().activeRoom;
        if (!room) return;
        await roomVoice.toggleMicrophone(room.id);
        set(state => ({voiceRevision: state.voiceRevision + 1}));
      },
      toggleSpeaker: async () => {
        const room = get().activeRoom;
        if (!room) return;
        await roomVoice.connect(room.id);
        roomVoice.toggleListening();
        set(state => ({voiceRevision: state.voiceRevision + 1}));
      },
      toggleScreenShare: async () => {
        const room = get().activeRoom;
        if (!room) return;
        const me = get().activeParticipants.find(member => member.userId === get().profile?.id);
        if (room.role !== 'HOST' && !me?.canShareScreen) {
          await api.requestScreenShare(room.id);
          set({error: 'Screen-share request sent to the host'});
          return;
        }
        await roomVoice.shareScreen(room.id, true);
        set(state => ({voiceRevision: state.voiceRevision + 1}));
      },
      muted: false,
      volume: 0.82,
      setMuted: muted => set({muted}),
      setVolume: volume => set({volume: Math.max(0, Math.min(1, volume))}),
      togglePlayback: async () => {
        const {activeRoom, watchState} = get();
        if (!activeRoom || !watchState) return;
        set({watchState: await api.updateWatch(activeRoom.id, {...watchState, playing: !watchState.playing})});
      },
      seek: async seconds => {
        const {activeRoom, watchState} = get();
        if (!activeRoom || !watchState) return;
        set({watchState: await api.updateWatch(activeRoom.id, {...watchState, positionSeconds: Math.max(0, seconds)})});
      },
      busy: false,
      replyToMessage: null,
      beginReply: message => set({replyToMessage: message}),
      cancelReply: () => set({replyToMessage: null}),
      initialize: async () => {
        try {
          if (localStorage.getItem('refresh_token')) {
            await api.refreshToken();
            const dashboard = await api.getProfileDashboard();
            set({profile: dashboard.profile, displayName: dashboard.profile?.displayName ?? '',
              ...dashboard.preferences, profileVisibility: dashboard.visibility ?? {}, authenticated: true,
              fullyConnected: true});
            await get().refreshHomeRooms();
            startNotificationStream();
          }
        } catch (error) { set({authenticated: false, profile: null, error: String(error)}); }
        finally { set({initializing: false}); }
      },
      login: async (username, password) => {
        set({busy: true, error: null});
        try {
          await api.login(username, password);
          const dashboard = await api.getProfileDashboard();
          set({profile: dashboard.profile, displayName: dashboard.profile?.displayName ?? '',
            ...dashboard.preferences, profileVisibility: dashboard.visibility ?? {}, authenticated: true,
            fullyConnected: true});
          await get().refreshHomeRooms();
          startNotificationStream();
        } finally { set({busy: false}); }
      },
      loginWithProvider: async provider => {
        set({busy: true, error: null});
        try {
          api.acceptSession(await window.xynkDesktop.loginWithProvider(provider));
          const dashboard = await api.getProfileDashboard();
          set({profile: dashboard.profile, displayName: dashboard.profile?.displayName ?? '',
            ...dashboard.preferences, profileVisibility: dashboard.visibility ?? {}, authenticated: true,
            fullyConnected: true});
          await get().refreshHomeRooms();
          startNotificationStream();
        } finally { set({busy: false}); }
      },
      logout: async () => {
        await get().leaveRoom();
        notifications.disconnect();
        api.logout();
        set({profile: null, authenticated: false, rooms: [], visibleRooms: [], fullyConnected: false});
      },
      refreshHomeRooms: async () => {
        const [mine, publicRooms] = await Promise.all([api.getMyRooms(), api.getPublicRooms()]);
        const merged = new Map<string, PartyRoom>();
        for (const room of [...mine, ...publicRooms]) merged.set(room.id, room);
        get().setRooms([...merged.values()]);
      },
      openRoom: async (room, accessKey) => {
        if (roomRefreshTimer) clearInterval(roomRefreshTimer);
        if (!room.joined) await api.openRoom(room.id, accessKey);
        await api.joinLiveRoom(room.id);
        const [watchState, queue, messages, participants] = await Promise.all([
          api.getWatchState(room.id), api.getWatchQueue(room.id), api.getRoomChat(room.id, get().profile?.id || ''),
          api.getLiveParticipants(room.id),
        ]);
        const membership = participants.find(member => member.userId === get().profile?.id);
        const role = membership?.role ?? room.role;
        set({activeRoom: {...room, role}, watchState, messages, error: null, canControlWatch: role === 'HOST',
          activeParticipants: participants,
          canViewVideo: role === 'HOST' || role === 'CO_HOST' || membership?.canViewVideo === true});
        roomVoice.onChange = () => set(state => ({voiceRevision: state.voiceRevision + 1}));
        void roomVoice.connect(room.id).catch(error => set({error: String(error)}));
        get().setQueue(queue);
        roomRefreshTimer = setInterval(async () => {
          if (roomRefreshBusy || get().activeRoom?.id !== room.id) return;
          roomRefreshBusy = true;
          try {
            const [nextWatch, nextQueue, nextMessages, nextParticipants] = await Promise.all([
              api.getWatchState(room.id), api.getWatchQueue(room.id), api.getRoomChat(room.id, get().profile?.id || ''),
              api.getLiveParticipants(room.id),
            ]);
            if (get().activeRoom?.id === room.id) {
              if (nextWatch?.revision !== get().watchState?.revision || nextWatch?.playing !== get().watchState?.playing ||
                  (nextWatch && Math.abs(nextWatch.positionSeconds - (get().watchState?.positionSeconds ?? 0)) > 3)) {
                set({watchState: nextWatch});
              }
              get().setQueue(nextQueue);
              const me = nextParticipants.find((participant: {userId: string}) => participant.userId === get().profile?.id);
              const currentRole = me?.role ?? get().activeRoom?.role ?? room.role;
              set({messages: nextMessages, activeParticipants: nextParticipants,
                activeRoom: get().activeRoom ? {...get().activeRoom!, role: currentRole} : null,
                canControlWatch: currentRole === 'HOST',
                canViewVideo: currentRole === 'HOST' || currentRole === 'CO_HOST' || me?.canViewVideo === true,
                fullyConnected: true, reconnecting: false});
              await api.heartbeatLiveRoom(room.id);
            }
          } catch (error) { set({fullyConnected: false, reconnecting: true, error: String(error)}); }
          finally { roomRefreshBusy = false; }
        }, 3000);
      },
      leaveRoom: async () => {
        if (roomRefreshTimer) { clearInterval(roomRefreshTimer); roomRefreshTimer = null; }
        await roomVoice.disconnect();
        const room = get().activeRoom;
        try { if (room) await api.leaveLiveRoom(room.id); }
        catch { /* The room is already closed locally; the server expires stale presence. */ }
        finally { set({activeRoom: null, watchState: null, queue: [], roomQueue: [], personalQueue: [], messages: [], activeParticipants: [], canControlWatch: false, canViewVideo: false, error: null}); }
      },
      sendMessage: async body => {
        const state = get();
        if (!state.activeRoom || !state.profile || !body.trim()) return;
        await api.sendRoomChat(state.activeRoom.id, body.trim(), state.profile.id, state.replyToMessage?.id);
        set({messages: await api.getRoomChat(state.activeRoom.id, state.profile.id), replyToMessage: null});
      },
      reactToMessage: async (messageId, reaction) => {
        const state = get(); if (!state.activeRoom || !state.profile) return;
        await api.reactToMessage(state.activeRoom.id, messageId, reaction);
        set({messages: await api.getRoomChat(state.activeRoom.id, state.profile.id)});
      },
      selectQueueItem: async item => {
        const room = get().activeRoom; if (!room) return;
        set({watchState: await api.playQueueItem(room.id, item.id)});
        get().setQueue(await api.getWatchQueue(room.id));
      },
      searchVideos: query => api.searchYouTube(query),
      selectYoutubeVideo: async (video, targetRoomId) => {
        const room = targetRoomId ? get().rooms.find(value => value.id === targetRoomId) ?? get().activeRoom : get().activeRoom;
        const target = room ?? await createVideoRoom(video.title);
        if (!room) await get().openRoom(target);
        const item = await api.addToQueue(target.id, {provider: 'YOUTUBE', mediaId: video.videoId, title: video.title, thumbnailUrl: video.thumbnailUrl});
        get().setQueue(await api.getWatchQueue(target.id));
        const current = await api.getWatchState(target.id);
        if (!current?.playing && (await api.getWatchQueueInfo(target.id)).canAdd) {
          set({watchState: await api.playQueueItem(target.id, item.id)});
        }
        void api.recordMedia({mediaId: video.videoId, provider: 'YOUTUBE', title: video.title, thumbnailUrl: video.thumbnailUrl}).catch(() => {});
      },
      selectCrunchyrollVideo: async (episodeId, title, thumbnailUrl, targetRoomId) => {
        let episodeUrl: string;
        if (/^[A-Za-z0-9]+$/.test(episodeId)) {
          episodeUrl = `https://www.crunchyroll.com/watch/${episodeId}`;
        } else {
          const selected = new URL(episodeId);
          if (selected.protocol !== 'https:' || !/(^|\.)crunchyroll\.com$/i.test(selected.hostname) ||
              !/^\/watch\/[A-Za-z0-9]+/.test(selected.pathname)) throw new Error('Invalid Crunchyroll episode');
          episodeUrl = selected.toString();
        }
        const room = targetRoomId ? get().rooms.find(value => value.id === targetRoomId) ?? get().activeRoom : get().activeRoom;
        const target = room ?? await createVideoRoom(title);
        if (!room) await get().openRoom(target);
        const item = await api.addToQueue(target.id, {provider: 'CRUNCHYROLL', mediaId: episodeUrl, title, thumbnailUrl});
        get().setQueue(await api.getWatchQueue(target.id));
        const current = await api.getWatchState(target.id);
        if (!current?.playing && (await api.getWatchQueueInfo(target.id)).canAdd) {
          set({watchState: await api.playQueueItem(target.id, item.id)});
        }
        void api.recordMedia({mediaId: episodeUrl, provider: 'CRUNCHYROLL', title, thumbnailUrl}).catch(() => {});
      },
      selectDirectVideo: async (url, targetRoomId) => {
        const parsed = new URL(url);
        if (parsed.protocol !== 'https:') throw new Error('Select an HTTPS video URL');
        const resolved = await api.resolveWebMedia(parsed.toString());
        if (!['DIRECT_MP4', 'DIRECT_HLS'].includes(resolved.sourceType) || !resolved.sourceUrl.startsWith('https://')) {
          throw new Error('This page does not expose a supported video');
        }
        const room = targetRoomId ? get().rooms.find(value => value.id === targetRoomId) ?? get().activeRoom : get().activeRoom;
        const target = room ?? await createVideoRoom(resolved.title || parsed.hostname);
        if (!room) await get().openRoom(target);
        const item = await api.addToQueue(target.id, {provider: resolved.sourceType, mediaId: parsed.toString(), sourceUrl: resolved.sourceUrl, title: resolved.title || parsed.hostname, thumbnailUrl: resolved.thumbnailUrl});
        get().setQueue(await api.getWatchQueue(target.id));
        const current = await api.getWatchState(target.id);
        if (!current?.playing && (await api.getWatchQueueInfo(target.id)).canAdd) {
          set({watchState: await api.playQueueItem(target.id, item.id)});
        }
        void api.recordMedia({mediaId: parsed.toString(), provider: resolved.sourceType, title: resolved.title || parsed.hostname,
          thumbnailUrl: resolved.thumbnailUrl, sourceUrl: resolved.sourceUrl, sourceType: resolved.sourceType}).catch(() => {});
      },
      createDirectParty: url => get().selectDirectVideo(url),
      // Auth
      initializing: true,
      authenticated: false,
      profile: null,
      setProfile: (p) => set({ profile: p, authenticated: !!p }),
      setAuthenticated: (v) => set({ authenticated: v }),
      setInitializing: (v) => set({ initializing: v }),

      // Rooms
      rooms: [],
      activeRoom: null,
      visibleRooms: [],
      setRooms: (r) => {
        const visible = r.filter(room => {
          if (!get().hideSensitiveContent) return true;
          const text = `${room.name} ${room.mediaTitle ?? ''} ${room.mediaId ?? ''}`.toLowerCase();
          return !['nsfw', 'adult', 'porn', 'xxx'].some(w => text.includes(w));
        });
        set({ rooms: r, visibleRooms: visible });
      },
      setActiveRoom: (r) => set({ activeRoom: r }),
      setVisibleRooms: (r) => set({ visibleRooms: r }),

      // Watch state
      watchState: null,
      setWatchState: (s) => set({ watchState: s }),
      updatePosition: (pos) => set((state) => ({
        watchState: state.watchState ? { ...state.watchState, positionSeconds: pos } : null
      })),
      setPlaying: (v) => set((state) => ({
        watchState: state.watchState ? { ...state.watchState, playing: v } : null
      })),

      // Queue
      queue: [],
      roomQueue: [],
      personalQueue: [],
      setQueue: (q) => {
        const roomQ = q.filter(item => !item.personalQueueItem).sort((a, b) => b.voteCount - a.voteCount);
        const profile = get().profile;
        const personalQ = profile ? q.filter(item => item.addedBy === profile.id && item.personalQueueItem).sort((a, b) => a.personalPosition - b.personalPosition) : [];
        set({ queue: q, roomQueue: roomQ, personalQueue: personalQ });
      },
      addToQueue: item => {
        const queue = get().queue;
        const existing = queue.findIndex(i => i.id === item.id);
        get().setQueue(existing >= 0 ? [...queue.slice(0, existing), item, ...queue.slice(existing + 1)] : [...queue, item]);
      },
      removeFromQueue: id => get().setQueue(get().queue.filter(item => item.id !== id)),
      voteQueueItem: id => {
        const room = get().activeRoom;
        if (room) void api.voteQueueItem(room.id, id).then(queue => get().setQueue(queue))
          .catch(error => set({error: String(error)}));
      },

      // Suggestions
      suggestions: [],
      setSuggestions: (s) => set({ suggestions: s }),

      // Chat
      messages: [],
      setMessages: (m) => set({ messages: m }),
      addMessage: (msg) => set((state) => ({ messages: [...state.messages, msg] })),

      // Media
      canViewVideo: false,
      setCanViewVideo: (v) => set({ canViewVideo: v }),

      // UI
      shelfOpen: false,
      setShelfOpen: (v) => set({ shelfOpen: v }),
      panel: 'chat',
      setPanel: (p) => set({ panel: p }),

      // Preferences
      hideSensitiveContent: true,
      setHideSensitiveContent: (v) => {
        set({ hideSensitiveContent: v });
        // Re-filter visible rooms
        const rooms = get().rooms.filter(room => {
          if (!v) return true;
          const text = `${room.name} ${room.mediaTitle ?? ''} ${room.mediaId ?? ''}`.toLowerCase();
          return !['nsfw', 'adult', 'porn', 'xxx'].some(w => text.includes(w));
        });
        set({ visibleRooms: rooms });
      },
      floatingVideo: true,
      setFloatingVideo: (v) => set({ floatingVideo: v }),
      muteOtherAudio: true,
      setMuteOtherAudio: (v) => set({ muteOtherAudio: v }),

      // Errors
      error: null,
      setError: (e) => set({ error: e }),
    }),
    {
      name: 'xynk-storage',
      partialize: (state) => ({
        hideSensitiveContent: state.hideSensitiveContent,
        floatingVideo: state.floatingVideo,
        muteOtherAudio: state.muteOtherAudio,
      }),
    }
  )
);

function startNotificationStream() {
  notifications.onEvent = event => {
    const state = useWatchPartyStore.getState();
    if (event.type === 'ROOM_INVITE') {
      void state.refreshHomeRooms();
      window.alert(event.body || 'You were invited to a room.');
      return;
    }
    if (!state.activeRoom || event.roomId !== state.activeRoom.id) return;
    if (event.type === 'SCREEN_SHARE_REQUEST' && state.activeRoom.role === 'HOST' && event.senderId) {
      if (window.confirm(`${event.senderName || 'A member'} wants to share their screen. Allow it?`)) {
        void api.setScreenPermission(state.activeRoom.id, event.senderId, true)
          .catch(error => state.setError(String(error)));
      }
    } else if (event.type === 'HOST_MUTE') {
      void roomVoice.muteMicrophone();
    } else if (event.type === 'HOST_UNMUTE_REQUEST') {
      if (!roomVoice.microphoneEnabled && window.confirm('The host asked you to unmute. Turn on your microphone?')) {
        void state.toggleMicrophone();
      }
    } else if (event.type === 'SCREEN_SHARE_APPROVED') {
      window.alert('Host approved screen sharing. Tap Share screen to start.');
    } else if (event.type === 'SCREEN_SHARE_REVOKED' && roomVoice.screenShareEnabled) {
      void state.toggleScreenShare();
    }
  };
  notifications.connect();
}
