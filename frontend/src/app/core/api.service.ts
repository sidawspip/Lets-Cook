import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { AuthService } from './auth.service';

export type AccessPolicy = 'OPEN' | 'INVITE_ONLY' | 'KEY_ONLY' | 'INVITE_OR_KEY' | 'INVITE_AND_KEY';
export type RoomRole = 'HOST' | 'CO_HOST' | 'MODERATOR' | 'MEMBER' | 'VIEWER';

export interface Profile {
  id: string;
  username: string;
  displayName: string;
  email?: string;
  bio?: string;
  avatarUrl?: string;
}
export interface ProfilePreferences { hideSensitiveContent:boolean; hideLocation:boolean; restrictInvites:boolean; floatingVideo:boolean; muteOtherAudio:boolean; hapticFeedback:boolean; autoTranslate:boolean; preferredLanguage:string; quickReaction:string; }
export interface ProfileConnection { provider:string; url:string; }
export interface ProfileVisibility { bio:'PUBLIC'|'FRIENDS'|'PRIVATE';gallery:'PUBLIC'|'FRIENDS'|'PRIVATE';activity:'PUBLIC'|'FRIENDS'|'PRIVATE';stats:'PUBLIC'|'FRIENDS'|'PRIVATE';friends:'PUBLIC'|'FRIENDS'|'PRIVATE';interests:'PUBLIC'|'FRIENDS'|'PRIVATE';connections:'PUBLIC'|'FRIENDS'|'PRIVATE'; }
export interface ProfileDashboard { profile:Profile; preferences:ProfilePreferences; visibility:ProfileVisibility; connections:ProfileConnection[]; interests:string[]; }

export interface Room {
  id: string;
  name: string;
  ownerName?: string;
  description?: string;
  accessPolicy: AccessPolicy;
  role: RoomRole;
  locked: boolean;
  memberCount: number;
  pendingCount: number;
  visibility: 'PUBLIC' | 'PRIVATE' | 'FRIENDS';
  screenSharePolicy: 'HOSTS_ONLY' | 'EVERYONE' | 'SELECTED';
  viewerCount?: number;
  mediaTitle?: string;
  mediaId?: string;
  mediaProvider?: WatchProvider;
  thumbnailUrl?: string;
}

export interface RoomCreated {
  room: Room;
  accessKey?: string;
}

export interface MediaToken {
  url: string;
  token: string;
  roomName: string;
  canPublish: boolean;
}

export interface RoomSearchResult {
  id: string; name: string; description?: string; accessPolicy: AccessPolicy; locked: boolean; memberCount: number; visibility: string;
}

export interface UserSearchResult { id: string; username: string; displayName: string; avatarUrl?: string; }
export interface SearchResult { users: UserSearchResult[]; rooms: RoomSearchResult[]; messages: unknown[]; }
export interface AccessResult { roomId: string; accessGranted: boolean; role: RoomRole; status: string; }
export interface InviteCreated { code: string; path: string; expiresAt?: string; maxUses?: number; }
export interface JoinRequest { userId: string; username: string; displayName: string; avatarUrl?: string; }
export interface Friend { id: string; username: string; displayName: string; avatarUrl?: string; online: boolean; watchTogetherSeconds: number; }
export interface FriendRequest { id: string; userId: string; username: string; displayName: string; }
export interface SocialNotification { id:string; type:'FRIEND_REQUEST'|'DIRECT_MESSAGE'; userId:string; username:string; displayName:string; body?:string; unreadCount:number; createdAt:string; }
export interface DirectMessage { id: string; senderId: string; recipientId: string; body: string; createdAt: string; }
export interface RoomMember { userId: string; username: string; displayName: string; role: RoomRole; canShareScreen: boolean; canAddVideos: boolean; online: boolean; }
export interface LiveParticipant { userId: string; username: string; displayName: string; avatarUrl?: string; role: RoomRole; canShareScreen: boolean; screenShareRequested?: boolean; }
export interface RecentRoomPerson { userId:string; username:string; displayName:string; avatarUrl?:string; roomName:string; lastSeenAt:string; friend:boolean; }
export interface RoomChatMessage { id: string; senderId: string; senderName: string; senderUsername?: string; avatarUrl?: string; body: string; type: 'MESSAGE'|'JOIN'|'LEAVE'|'VIDEO'|string; mediaProvider?: string; mediaId?: string; mediaTitle?: string; createdAt: string; }
export type WatchProvider=
  |'YOUTUBE'|'WEB'|'DIRECT_MP4'|'DIRECT_HLS'
  |'GOOGLE_DRIVE'|'DROPBOX'|'ONEDRIVE'|'BOX'|'NEXTCLOUD'|'INTERNET_ARCHIVE'
  |'X'|'VIMEO'|'NETFLIX'|'PRIME_VIDEO'|'CRUNCHYROLL'|'TWITCH';
export interface WatchState { roomId:string;provider:WatchProvider;sourceType:string;mediaId:string;sourceUrl?:string;thumbnailUrl?:string;title?:string;playing:boolean;positionSeconds:number;durationSeconds?:number;playbackRate:number;revision:number;updatedAt:string;serverTime:string;transitionUntil?:string; }
export interface YoutubeResult { videoId:string; title:string; channelTitle:string; thumbnailUrl:string; }
export interface YoutubeSearch { configured:boolean; results:YoutubeResult[]; message?:string; nextPageToken?:string; previousPageToken?:string; }
export interface ResolvedWebMedia { pageUrl:string; sourceUrl:string; sourceType:'DIRECT_MP4'|'DIRECT_HLS'; title:string; siteName:string; thumbnailUrl?:string; }
export interface WatchQueueItem { id:string; provider:WatchProvider; mediaId:string; title:string; thumbnailUrl?:string; addedBy:string; addedByName:string; personalPosition:number; personalQueueItem:boolean; voteCount:number; votedByMe:boolean; createdAt:string; }
export interface WatchQueue { mode:'HOSTS_ONLY'|'PERMISSION'|'VOTE'; transitionSeconds:number; canAdd:boolean; nextItemId?:string; skipVotes:number; skipRequired:number; skipVotedByMe:boolean; items:WatchQueueItem[]; }
export interface SkipVoteResult { skipped:boolean; votes:number; required:number; state?:WatchState; }
export interface PublicRoom { id:string;name:string;ownerName?:string;description?:string;accessPolicy:AccessPolicy;viewerCount:number;mediaTitle?:string;mediaId?:string;mediaProvider?:string;thumbnailUrl?:string;positionSeconds?:number;durationSeconds?:number;viewerAvatars:string[];joined:boolean; }
export interface MediaLibraryItem { mediaId:string;provider:string;title:string;thumbnailUrl?:string;sourceUrl?:string;sourceType?:string;sensitive:boolean;playCount:number;watchSeconds:number;liked:boolean;inGallery:boolean;lastWatchedAt:string; }
export interface MediaLibraryDashboard { history:MediaLibraryItem[];gallery:MediaLibraryItem[];likes:MediaLibraryItem[];categories:Record<string,number>;watchTogetherSeconds:number;friendCount:number;hideSensitiveContent:boolean; }

@Injectable({ providedIn: 'root' })
export class ApiService {
  private readonly http = inject(HttpClient);
  private readonly auth = inject(AuthService);
  private readonly baseUrl = window.location.protocol === 'https:'
    ? '/api'
    : `http://${window.location.hostname}:8080/api`;

  async profile(): Promise<Profile> {
    return firstValueFrom(this.http.get<Profile>(`${this.baseUrl}/me/profile`, { headers: await this.headers() }));
  }

  async rooms(): Promise<Room[]> {
    return firstValueFrom(this.http.get<Room[]>(`${this.baseUrl}/rooms`, { headers: await this.headers() }));
  }
  async publicRooms():Promise<PublicRoom[]> { return firstValueFrom(this.http.get<PublicRoom[]>(`${this.baseUrl}/rooms/public-live`,{headers:await this.headers()})); }

  async createRoom(input: {
    name: string;
    description: string;
    accessPolicy: AccessPolicy;
    approvalRequired: boolean;
    maxMembers: number;
    visibility?: string;
    ephemeral?: boolean;
  }): Promise<RoomCreated> {
    return firstValueFrom(this.http.post<RoomCreated>(`${this.baseUrl}/rooms`, input, { headers: await this.headers() }));
  }

  async search(query: string): Promise<SearchResult> {
    return firstValueFrom(this.http.get<SearchResult>(`${this.baseUrl}/search`, {
      params: { q: query }, headers: await this.headers()
    }));
  }

  async unlockRoom(roomId: string, accessKey: string): Promise<AccessResult> {
    return firstValueFrom(this.http.post<AccessResult>(`${this.baseUrl}/rooms/${roomId}/unlock`,
      { accessKey }, { headers: await this.headers() }));
  }

  async createInvite(roomId: string): Promise<InviteCreated> {
    return firstValueFrom(this.http.post<InviteCreated>(`${this.baseUrl}/rooms/${roomId}/invites`,
      { role: 'MEMBER', maxUses: 20 }, { headers: await this.headers() }));
  }

  async acceptInvite(code: string, accessKey?: string): Promise<AccessResult> {
    return firstValueFrom(this.http.post<AccessResult>(`${this.baseUrl}/invites/${encodeURIComponent(code)}/accept`,
      { accessKey: accessKey || null }, { headers: await this.headers() }));
  }

  async deleteRoom(roomId: string): Promise<void> {
    await firstValueFrom(this.http.delete<void>(`${this.baseUrl}/rooms/${roomId}`, { headers: await this.headers() }));
  }

  async joinRequests(roomId: string): Promise<JoinRequest[]> {
    return firstValueFrom(this.http.get<JoinRequest[]>(`${this.baseUrl}/rooms/${roomId}/requests`, { headers: await this.headers() }));
  }
  async decideJoinRequest(roomId: string, userId: string, approve: boolean): Promise<void> {
    await firstValueFrom(this.http.post<void>(`${this.baseUrl}/rooms/${roomId}/requests/${userId}/${approve ? 'approve' : 'reject'}`, {}, { headers: await this.headers() }));
  }
  async friends(): Promise<Friend[]> { return firstValueFrom(this.http.get<Friend[]>(`${this.baseUrl}/social/friends`, { headers: await this.headers() })); }
  async friendRequests(): Promise<FriendRequest[]> { return firstValueFrom(this.http.get<FriendRequest[]>(`${this.baseUrl}/social/friend-requests`, { headers: await this.headers() })); }
  async notifications(): Promise<SocialNotification[]> { return firstValueFrom(this.http.get<SocialNotification[]>(`${this.baseUrl}/social/notifications`, { headers: await this.headers() })); }
  async sendFriendRequest(userId: string): Promise<void> { await firstValueFrom(this.http.post<void>(`${this.baseUrl}/social/friend-requests/${userId}`, {}, { headers: await this.headers() })); }
  async decideFriendRequest(requestId: string, accept: boolean): Promise<void> { await firstValueFrom(this.http.post<void>(`${this.baseUrl}/social/friend-requests/${requestId}/${accept ? 'accept' : 'reject'}`, {}, { headers: await this.headers() })); }
  async messages(friendId: string): Promise<DirectMessage[]> { return firstValueFrom(this.http.get<DirectMessage[]>(`${this.baseUrl}/social/messages/${friendId}`, { headers: await this.headers() })); }
  async sendMessage(friendId: string, body: string): Promise<DirectMessage> { return firstValueFrom(this.http.post<DirectMessage>(`${this.baseUrl}/social/messages/${friendId}`, { body }, { headers: await this.headers() })); }
  async roomMembers(roomId: string): Promise<RoomMember[]> { return firstValueFrom(this.http.get<RoomMember[]>(`${this.baseUrl}/rooms/${roomId}/members`, { headers: await this.headers() })); }
  async setScreenPermission(roomId: string, userId: string, allowed: boolean): Promise<void> { await firstValueFrom(this.http.post<void>(`${this.baseUrl}/rooms/${roomId}/members/${userId}/screen-permission`, { allowed }, { headers: await this.headers() })); }
  async requestScreenShare(roomId: string): Promise<void> { await firstValueFrom(this.http.post<void>(`${this.baseUrl}/rooms/${roomId}/screen-share-request`, {}, { headers: await this.headers() })); }
  async hostMicAction(roomId:string,userId:string,action:'MUTE'|'REQUEST_UNMUTE'):Promise<void>{await firstValueFrom(this.http.post<void>(`${this.baseUrl}/rooms/${roomId}/members/${userId}/microphone-action`,{action},{headers:await this.headers()}));}
  async kickMember(roomId: string, userId: string): Promise<void> { await firstValueFrom(this.http.delete<void>(`${this.baseUrl}/rooms/${roomId}/members/${userId}`, { headers: await this.headers() })); }
  async inviteUser(roomId:string,userId:string):Promise<void>{await firstValueFrom(this.http.post<void>(`${this.baseUrl}/rooms/${roomId}/invite-user/${userId}`,{},{headers:await this.headers()}));}
  async setLeadership(roomId:string,userId:string,action:'CO_HOST'|'MEMBER'|'TRANSFER'):Promise<void>{await firstValueFrom(this.http.post<void>(`${this.baseUrl}/rooms/${roomId}/members/${userId}/leadership/${action}`,{},{headers:await this.headers()}));}
  async updateRoom(roomId: string, input: object): Promise<void> { await firstValueFrom(this.http.patch<void>(`${this.baseUrl}/rooms/${roomId}/settings`, input, { headers: await this.headers() })); }
  async updateProfile(input: {displayName: string; bio: string}): Promise<Profile> { return firstValueFrom(this.http.patch<Profile>(`${this.baseUrl}/me/profile`, input, { headers: await this.headers() })); }
  async profileDashboard():Promise<ProfileDashboard>{return firstValueFrom(this.http.get<ProfileDashboard>(`${this.baseUrl}/me/profile/dashboard`,{headers:await this.headers()}));}
  async updateProfilePreferences(input:ProfilePreferences):Promise<ProfilePreferences>{return firstValueFrom(this.http.patch<ProfilePreferences>(`${this.baseUrl}/me/profile/preferences`,input,{headers:await this.headers()}));}
  async updateProfileConnections(input:ProfileConnection[]):Promise<void>{await firstValueFrom(this.http.put<void>(`${this.baseUrl}/me/profile/connections`,input,{headers:await this.headers()}));}
  async updateProfileInterests(input:string[]):Promise<void>{await firstValueFrom(this.http.put<void>(`${this.baseUrl}/me/profile/interests`,input,{headers:await this.headers()}));}
  async updateProfileVisibility(input:ProfileVisibility):Promise<ProfileVisibility>{return firstValueFrom(this.http.patch<ProfileVisibility>(`${this.baseUrl}/me/profile/visibility`,input,{headers:await this.headers()}));}
  async uploadAvatar(file: File): Promise<Profile> {
    const form = new FormData(); form.append('file',file);
    return firstValueFrom(this.http.post<Profile>(`${this.baseUrl}/me/avatar`,form,{headers:await this.headers()}));
  }
  async liveJoin(roomId: string): Promise<void> { await firstValueFrom(this.http.post<void>(`${this.baseUrl}/rooms/${roomId}/live/join`, {}, { headers: await this.headers() })); }
  async liveHeartbeat(roomId: string): Promise<void> { await firstValueFrom(this.http.post<void>(`${this.baseUrl}/rooms/${roomId}/live/heartbeat`, {}, { headers: await this.headers() })); }
  async liveLeave(roomId: string): Promise<void> { await firstValueFrom(this.http.delete<void>(`${this.baseUrl}/rooms/${roomId}/live/leave`, { headers: await this.headers() })); }
  async liveParticipants(roomId: string): Promise<LiveParticipant[]> { return firstValueFrom(this.http.get<LiveParticipant[]>(`${this.baseUrl}/rooms/${roomId}/live/participants`, { headers: await this.headers() })); }
  async recentRoomPeople(roomId:string):Promise<RecentRoomPerson[]> { return firstValueFrom(this.http.get<RecentRoomPerson[]>(`${this.baseUrl}/rooms/${roomId}/live/recent-people`,{headers:await this.headers()})); }
  async roomChat(roomId: string): Promise<RoomChatMessage[]> { return firstValueFrom(this.http.get<RoomChatMessage[]>(`${this.baseUrl}/rooms/${roomId}/live/messages`, { headers: await this.headers() })); }
  async sendRoomChat(roomId: string, body: string): Promise<RoomChatMessage> { return firstValueFrom(this.http.post<RoomChatMessage>(`${this.baseUrl}/rooms/${roomId}/live/messages`, {body}, { headers: await this.headers() })); }
  async shareRoomVideo(roomId:string,item:{provider:string;mediaId:string;title:string}):Promise<RoomChatMessage>{return firstValueFrom(this.http.post<RoomChatMessage>(`${this.baseUrl}/rooms/${roomId}/live/messages/video`,item,{headers:await this.headers()}));}
  async watchState(roomId:string):Promise<WatchState|null> { return firstValueFrom(this.http.get<WatchState|null>(`${this.baseUrl}/rooms/${roomId}/watch`,{headers:await this.headers()})); }
  async updateWatch(roomId:string,state:Partial<WatchState>&Pick<WatchState,'provider'|'mediaId'|'playing'|'positionSeconds'|'playbackRate'>):Promise<WatchState> { return firstValueFrom(this.http.put<WatchState>(`${this.baseUrl}/rooms/${roomId}/watch`,state,{headers:await this.headers()})); }
  async heartbeatWatch(roomId:string):Promise<WatchState> { return firstValueFrom(this.http.post<WatchState>(`${this.baseUrl}/rooms/${roomId}/watch/heartbeat`,{},{headers:await this.headers()})); }
  async searchYoutube(query:string,pageToken?:string):Promise<YoutubeSearch> {
    const params:Record<string,string>={q:query};if(pageToken)params['pageToken']=pageToken;
    return firstValueFrom(this.http.get<YoutubeSearch>(`${this.baseUrl}/youtube/search`,{params,headers:await this.headers()}));
  }
  async resolveWebMedia(pageUrl:string):Promise<ResolvedWebMedia> { return firstValueFrom(this.http.post<ResolvedWebMedia>(`${this.baseUrl}/media/resolve-web`,{pageUrl},{headers:await this.headers()})); }
  async watchQueue(roomId:string):Promise<WatchQueue> { return firstValueFrom(this.http.get<WatchQueue>(`${this.baseUrl}/rooms/${roomId}/watch/queue`,{headers:await this.headers()})); }
  async addToWatchQueue(roomId:string,item:{provider:WatchProvider;mediaId:string;sourceUrl?:string;title:string;thumbnailUrl?:string}):Promise<WatchQueueItem> { return firstValueFrom(this.http.post<WatchQueueItem>(`${this.baseUrl}/rooms/${roomId}/watch/queue`,item,{headers:await this.headers()})); }
  async voteWatchQueue(roomId:string,queueId:string):Promise<void> { await firstValueFrom(this.http.post<void>(`${this.baseUrl}/rooms/${roomId}/watch/queue/${queueId}/vote`,{},{headers:await this.headers()})); }
  async removeWatchQueue(roomId:string,queueId:string):Promise<void> { await firstValueFrom(this.http.delete<void>(`${this.baseUrl}/rooms/${roomId}/watch/queue/${queueId}`,{headers:await this.headers()})); }
  async playNext(roomId:string,queueId?:string):Promise<WatchState> { return firstValueFrom(this.http.post<WatchState>(`${this.baseUrl}/rooms/${roomId}/watch/queue/next`,{queueId:queueId??null},{headers:await this.headers()})); }
  async reorderWatchQueue(roomId:string,queueIds:string[]):Promise<void> { await firstValueFrom(this.http.put<void>(`${this.baseUrl}/rooms/${roomId}/watch/queue/reorder`,{queueIds},{headers:await this.headers()})); }
  async voteToSkip(roomId:string):Promise<SkipVoteResult> { return firstValueFrom(this.http.post<SkipVoteResult>(`${this.baseUrl}/rooms/${roomId}/watch/skip-vote`,{},{headers:await this.headers()})); }
  async updateWatchSettings(roomId:string,mode:string,transitionSeconds:number):Promise<void> { await firstValueFrom(this.http.patch<void>(`${this.baseUrl}/rooms/${roomId}/watch/settings`,{mode,transitionSeconds},{headers:await this.headers()})); }
  async setVideoPermission(roomId:string,userId:string,allowed:boolean):Promise<void> { await firstValueFrom(this.http.post<void>(`${this.baseUrl}/rooms/${roomId}/members/${userId}/video-permission`,{allowed},{headers:await this.headers()})); }

  async mediaToken(roomId: string): Promise<MediaToken> {
    return firstValueFrom(this.http.post<MediaToken>(`${this.baseUrl}/rooms/${roomId}/media-token`, {}, {
      headers: await this.headers()
    }));
  }

  async mediaLibrary():Promise<MediaLibraryDashboard>{return firstValueFrom(this.http.get<MediaLibraryDashboard>(`${this.baseUrl}/me/media`,{headers:await this.headers()}));}
  async recordMedia(input:{mediaId:string;provider:string;title:string;thumbnailUrl?:string;sourceUrl?:string;sourceType?:string;watchSeconds?:number}):Promise<MediaLibraryItem>{return firstValueFrom(this.http.post<MediaLibraryItem>(`${this.baseUrl}/me/media/history`,input,{headers:await this.headers()}));}
  async removeMediaHistory(mediaId:string):Promise<void>{await firstValueFrom(this.http.delete<void>(`${this.baseUrl}/me/media/history`,{params:{mediaId},headers:await this.headers()}));}
  async setMediaLike(mediaId:string,enabled:boolean):Promise<void>{await firstValueFrom(this.http.put<void>(`${this.baseUrl}/me/media/like`,{mediaId,enabled},{headers:await this.headers()}));}

  private async headers(): Promise<HttpHeaders> {
    return new HttpHeaders({ Authorization: `Bearer ${await this.auth.token()}` });
  }
}

