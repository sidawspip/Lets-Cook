import type { PartyRoom, Profile, RoomWatchState, QueueItem, VideoSuggestion, ChatMessage, DirectMessage, ViewingActivity, MediaToken, StoredSession } from '../types/models';

const API_BASE = import.meta.env.VITE_API_BASE || 'https://xynk.in/api';
const AUTH_BASE = import.meta.env.VITE_AUTH_BASE || 'https://xynk.in';

class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message);
    this.name = 'ApiError';
  }
}

let refreshInFlight: Promise<StoredSession> | null = null;

async function fetchJson<T>(path: string, options: RequestInit = {}): Promise<T> {
  const request = () => {
    const token = localStorage.getItem('access_token');
    return fetch(`${API_BASE}${path}`, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...options.headers,
      },
    });
  };
  let res = await request();
  if (res.status === 401 && localStorage.getItem('refresh_token')) {
    refreshInFlight ??= api.refreshToken().finally(() => { refreshInFlight = null; });
    try { await refreshInFlight; res = await request(); }
    catch { /* Preserve the original authorization failure. */ }
  }
  if (res.status === 401) {
    localStorage.removeItem('access_token');
    localStorage.removeItem('refresh_token');
    window.location.hash = '#/login';
    throw new ApiError(401, 'Session expired');
  }

  if (!res.ok) {
    let msg = `Request failed (${res.status})`;
    try {
      const err = await res.json();
      msg = err.detail || err.message || err.error || msg;
    } catch {}
    throw new ApiError(res.status, msg);
  }

  if (res.status === 204) return undefined as T;
  const body = await res.text();
  if (!body.trim()) return undefined as T;
  return JSON.parse(body) as T;
}

export const api = {
  // Auth
  acceptSession(session: StoredSession): void {
    localStorage.setItem('access_token', session.accessToken);
    localStorage.setItem('refresh_token', session.refreshToken);
    localStorage.setItem('token_expires', session.expiresAt);
  },
  async login(username: string, password: string): Promise<StoredSession> {
    const params = new URLSearchParams({
      client_id: import.meta.env.VITE_CLIENT_ID || 'lets-cook-mobile',
      grant_type: 'password',
      username,
      password,
      scope: 'openid profile email offline_access',
    });

    const res = await fetch(`${AUTH_BASE}/realms/xynk/protocol/openid-connect/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params.toString(),
    });

    if (!res.ok) throw new ApiError(res.status, 'Invalid credentials');
    const json = await res.json();
    const session: StoredSession = {
      accessToken: json.access_token,
      refreshToken: json.refresh_token,
      expiresAt: new Date(Date.now() + (json.expires_in || 300) * 1000).toISOString(),
    };
    this.acceptSession(session);
    return session;
  },

  async refreshToken(): Promise<StoredSession> {
    const refreshToken = localStorage.getItem('refresh_token');
    if (!refreshToken) throw new ApiError(401, 'No refresh token');

    const params = new URLSearchParams({
      client_id: import.meta.env.VITE_CLIENT_ID || 'lets-cook-mobile',
      grant_type: 'refresh_token',
      refresh_token: refreshToken,
    });

    const res = await fetch(`${AUTH_BASE}/realms/xynk/protocol/openid-connect/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params.toString(),
    });

    if (!res.ok) throw new ApiError(401, 'Token refresh failed');
    const json = await res.json();
    const session: StoredSession = {
      accessToken: json.access_token,
      refreshToken: json.refresh_token || localStorage.getItem('refresh_token')!,
      expiresAt: new Date(Date.now() + (json.expires_in || 300) * 1000).toISOString(),
    };
    this.acceptSession(session);
    return session;
  },

  logout() {
    localStorage.clear();
  },

  // Profile
  async getProfile(): Promise<any> {
    return fetchJson('/me/profile');
  },

  async updateBasicProfile(displayName: string, bio: string): Promise<any> {
    return fetchJson('/me/profile', {method: 'PATCH', body: JSON.stringify({displayName, bio})});
  },

  async uploadAvatar(file: File): Promise<any> {
    const body = new FormData();
    body.append('file', file);
    const response = await fetch(`${API_BASE}/me/avatar`, {
      method: 'POST', headers: {Authorization: `Bearer ${localStorage.getItem('access_token') || ''}`}, body,
    });
    if (!response.ok) throw new ApiError(response.status, `Avatar upload failed (${response.status})`);
    return response.json();
  },

  async updateProfile(prefs: Record<string, unknown>) {
    return fetchJson('/me/profile/preferences', { method: 'PATCH', body: JSON.stringify(prefs) });
  },

  async getProfileDashboard(): Promise<any> {
    return fetchJson('/me/profile/dashboard');
  },
  async getMediaDashboard(): Promise<any> {
    return fetchJson('/me/media');
  },
  async recordMedia(media: {mediaId: string; provider: string; title: string; thumbnailUrl?: string; sourceUrl?: string; sourceType?: string; watchSeconds?: number}): Promise<any> {
    return fetchJson('/me/media/history', {method: 'POST', body: JSON.stringify(media)});
  },
  async setMediaLike(mediaId: string, enabled: boolean): Promise<void> {
    return fetchJson('/me/media/like', {method: 'PUT', body: JSON.stringify({mediaId, enabled})});
  },
  async setMediaGallery(mediaId: string, enabled: boolean): Promise<void> {
    return fetchJson('/me/media/gallery', {method: 'PUT', body: JSON.stringify({mediaId, enabled})});
  },
  async removeHistory(mediaId: string): Promise<void> {
    return fetchJson(`/me/media/history?mediaId=${encodeURIComponent(mediaId)}`, {method: 'DELETE'});
  },

  async updateProfileVisibility(visibility: Record<string, string>): Promise<any> {
    return fetchJson('/me/profile/visibility', {method: 'PATCH', body: JSON.stringify(visibility)});
  },

  // Rooms
  async createRoom(name: string): Promise<any> {
    return fetchJson('/rooms', {
      method: 'POST',
      body: JSON.stringify({
        name,
        description: 'A Xynk watch party',
        accessPolicy: 'OPEN',
        approvalRequired: false,
        maxMembers: 50,
        visibility: 'PUBLIC',
        ephemeral: true,
      }),
    });
  },

  async getPublicRooms(): Promise<any[]> {
    return fetchJson('/rooms/public-live');
  },

  async getMyRooms(): Promise<any[]> {
    return fetchJson('/rooms');
  },

  async openRoom(roomId: string, accessKey?: string) {
    return fetchJson(`/rooms/${roomId}/unlock`, {
      method: 'POST',
      body: JSON.stringify({ accessKey: accessKey?.trim() || '' }),
    });
  },

  async joinLiveRoom(roomId: string) {
    return fetchJson(`/rooms/${roomId}/live/join`, { method: 'POST', body: '{}' });
  },

  async heartbeatLiveRoom(roomId: string): Promise<void> {
    return fetchJson(`/rooms/${roomId}/live/heartbeat`, {method: 'POST'});
  },

  async leaveLiveRoom(roomId: string) {
    return fetchJson(`/rooms/${roomId}/live/leave`, { method: 'DELETE' });
  },

  async getWatchState(roomId: string): Promise<any> {
    return fetchJson(`/rooms/${roomId}/watch`);
  },
  async getMembers(roomId: string): Promise<any[]> {
    return fetchJson(`/rooms/${roomId}/members`);
  },
  async requestVideoAccess(roomId: string): Promise<void> {
    return fetchJson(`/rooms/${roomId}/watch/access-request`, {method: 'POST', body: '{}'});
  },
  async updateWatch(roomId: string, state: RoomWatchState): Promise<RoomWatchState> {
    const {provider, sourceType, mediaId, sourceUrl, title, playing, positionSeconds, durationSeconds, playbackRate} = state;
    return fetchJson(`/rooms/${roomId}/watch`, {method: 'PUT',
      body: JSON.stringify({provider, sourceType, mediaId, sourceUrl, title, playing, positionSeconds, durationSeconds, playbackRate})});
  },

  async getWatchQueue(roomId: string): Promise<any[]> {
    const data = await fetchJson<any>(`/rooms/${roomId}/watch/queue`);
    return data.items || [];
  },

  async getWatchQueueInfo(roomId: string): Promise<any> {
    return fetchJson(`/rooms/${roomId}/watch/queue`);
  },

  async updateWatchSettings(roomId: string, mode: string) {
    return fetchJson(`/rooms/${roomId}/watch/settings`, {
      method: 'PATCH',
      body: JSON.stringify({ mode, transitionSeconds: 8 }),
    });
  },

  async playQueueItem(roomId: string, queueId: string): Promise<any> {
    return fetchJson(`/rooms/${roomId}/watch/queue/next`, {
      method: 'POST',
      body: JSON.stringify({ queueId }),
    });
  },
  async playHighestVoted(roomId: string): Promise<RoomWatchState> {
    return fetchJson(`/rooms/${roomId}/watch/queue/next`, {method: 'POST'});
  },

  async addToQueue(roomId: string, video: { provider: string; mediaId: string; title: string; thumbnailUrl?: string; sourceUrl?: string }): Promise<any> {
    return fetchJson(`/rooms/${roomId}/watch/queue`, {
      method: 'POST',
      body: JSON.stringify({
        provider: video.provider,
        mediaId: video.mediaId,
        title: video.title,
        thumbnailUrl: video.thumbnailUrl,
        sourceUrl: video.sourceUrl,
        personalQueueItem: false,
      }),
    });
  },

  async voteQueueItem(roomId: string, queueId: string): Promise<any[]> {
    const data = await fetchJson<any>(`/rooms/${roomId}/watch/queue/${queueId}/vote`, { method: 'POST' });
    return data.items || [];
  },
  async voteToSkip(roomId: string): Promise<{skipped: boolean; votes: number; required: number; state?: RoomWatchState}> {
    return fetchJson(`/rooms/${roomId}/watch/skip-vote`, {method: 'POST'});
  },

  async getLiveParticipants(roomId: string): Promise<any[]> {
    return fetchJson(`/rooms/${roomId}/live/participants`);
  },

  async requestScreenShare(roomId: string): Promise<void> {
    return fetchJson(`/rooms/${roomId}/screen-share-request`, {method: 'POST'});
  },

  async getRoomChat(roomId: string, myId: string): Promise<any[]> {
    const messages = await fetchJson<ChatMessage[]>(`/rooms/${roomId}/live/messages`);
    return messages.map(message => ({...message, isMine: message.senderId === myId}));
  },

  async sendRoomChat(roomId: string, body: string, myId: string, replyToId?: string): Promise<any> {
    return fetchJson(`/rooms/${roomId}/live/messages`, {
      method: 'POST',
      body: JSON.stringify({ body, replyToId }),
    });
  },

  async reactToMessage(roomId: string, messageId: string, reaction: string): Promise<any> {
    return fetchJson(`/rooms/${roomId}/live/messages/${messageId}/reactions`, {
      method: 'POST',
      body: JSON.stringify({ reaction }),
    });
  },

  async shareRoomVideo(roomId: string, myId: string, video: { provider: string; mediaId: string; title: string }): Promise<any> {
    return fetchJson(`/rooms/${roomId}/live/messages/video`, {
      method: 'POST',
      body: JSON.stringify(video),
    });
  },

  async searchYouTube(query: string): Promise<any[]> {
    const data = await fetchJson<any>(`/youtube/search?q=${encodeURIComponent(query)}`);
    return (data.results || []).map((result: any) => ({...result, provider: 'YOUTUBE'}));
  },

  async resolveWebMedia(pageUrl: string): Promise<{sourceUrl: string; sourceType: string; title: string; thumbnailUrl?: string}> {
    return fetchJson('/media/resolve-web', {method: 'POST', body: JSON.stringify({pageUrl})});
  },

  // Crunchyroll
  async crunchyrollAuth(): Promise<{ accessToken: string; playbackToken: string }> {
    return fetchJson('/crunchyroll/auth');
  },

  async crunchyrollPlayback(videoId: string): Promise<{ url: string; token: string }> {
    return fetchJson(`/crunchyroll/playback/${videoId}`);
  },

  async crunchyrollLicense(challenge: string, videoId: string, playbackToken: string): Promise<string> {
    const data = await fetchJson<{ license: string }>('/crunchyroll/license', {
      method: 'POST',
      body: JSON.stringify({ challenge, videoId, playbackToken }),
    });
    return data.license;
  },

  // Media tokens
  async getMediaToken(roomId: string): Promise<MediaToken> {
    return fetchJson(`/rooms/${roomId}/media-token`, {method: 'POST', body: '{}'});
  },
  async setScreenPermission(roomId: string, userId: string, allowed: boolean): Promise<void> {
    return fetchJson(`/rooms/${roomId}/members/${encodeURIComponent(userId)}/screen-permission`, {method: 'POST', body: JSON.stringify({allowed})});
  },
  async hostMicAction(roomId: string, userId: string, action: 'MUTE' | 'REQUEST_UNMUTE'): Promise<void> {
    return fetchJson(`/rooms/${roomId}/members/${encodeURIComponent(userId)}/microphone-action`, {method: 'POST', body: JSON.stringify({action})});
  },
  async kickRoomMember(roomId: string, userId: string): Promise<void> {
    return fetchJson(`/rooms/${roomId}/members/${encodeURIComponent(userId)}`, {method: 'DELETE'});
  },
  async setRoomLeadership(roomId: string, userId: string, action: 'TRANSFER' | 'CO_HOST' | 'MEMBER'): Promise<void> {
    return fetchJson(`/rooms/${roomId}/members/${encodeURIComponent(userId)}/leadership/${action}`, {method: 'POST'});
  },
  async updateVideoPermission(roomId: string, userId: string, allowed: boolean): Promise<void> {
    return fetchJson(`/rooms/${roomId}/members/${encodeURIComponent(userId)}/video-permission`, {method: 'POST', body: JSON.stringify({allowed})});
  },
  async updateVideoAccess(roomId: string, userId: string, allowed: boolean): Promise<void> {
    return fetchJson(`/rooms/${roomId}/members/${encodeURIComponent(userId)}/video-access`, {method: 'POST', body: JSON.stringify({allowed})});
  },
  async inviteUserToRoom(roomId: string, userId: string): Promise<void> {
    return fetchJson(`/rooms/${roomId}/invite-user/${encodeURIComponent(userId)}`, {method: 'POST', body: '{}'});
  },
  async updateRoomAudience(roomId: string, visibility: string, accessPolicy: string): Promise<void> {
    return fetchJson(`/rooms/${roomId}/settings`, {method: 'PATCH', body: JSON.stringify({visibility, accessPolicy, approvalRequired: false})});
  },

  // Direct messages
  async getDirectMessages(friendId: string): Promise<DirectMessage[]> {
    return fetchJson(`/social/messages/${friendId}`);
  },

  async sendDirectMessage(friendId: string, body: string): Promise<DirectMessage> {
    return fetchJson(`/social/messages/${friendId}`, {
      method: 'POST',
      body: JSON.stringify({ body }),
    });
  },

  // Friends
  async getFriends(): Promise<any[]> {
    return fetchJson('/social/friends');
  },

  async getFriendRequests(): Promise<any[]> {
    return fetchJson('/social/friend-requests');
  },

  async decideFriendRequest(requestId: string, accept: boolean): Promise<void> {
    return fetchJson(`/social/friend-requests/${encodeURIComponent(requestId)}/${accept ? 'accept' : 'reject'}`, { method: 'POST' });
  },

  async publicProfile(userId: string): Promise<Record<string, unknown>> {
    return fetchJson(`/me/profile/view/${encodeURIComponent(userId)}`);
  },

  async sendFriendRequest(userId: string) {
    return fetchJson(`/social/friend-requests/${encodeURIComponent(userId)}`, { method: 'POST' });
  },
  async removeFriend(userId: string): Promise<void> {
    return fetchJson(`/social/friends/${encodeURIComponent(userId)}`, {method: 'DELETE'});
  },
};

export { ApiError };
