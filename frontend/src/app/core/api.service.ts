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

export interface Room {
  id: string;
  name: string;
  description?: string;
  accessPolicy: AccessPolicy;
  role: RoomRole;
  locked: boolean;
  memberCount: number;
  pendingCount: number;
  visibility: 'PUBLIC' | 'PRIVATE' | 'FRIENDS';
  screenSharePolicy: 'HOSTS_ONLY' | 'EVERYONE' | 'SELECTED';
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
export interface Friend { id: string; username: string; displayName: string; avatarUrl?: string; online: boolean; }
export interface FriendRequest { id: string; userId: string; username: string; displayName: string; }
export interface DirectMessage { id: string; senderId: string; recipientId: string; body: string; createdAt: string; }
export interface RoomMember { userId: string; username: string; displayName: string; role: RoomRole; canShareScreen: boolean; canAddVideos: boolean; online: boolean; }
export interface LiveParticipant { userId: string; username: string; displayName: string; avatarUrl?: string; role: RoomRole; canShareScreen: boolean; }
export interface RecentRoomPerson { userId:string; username:string; displayName:string; avatarUrl?:string; roomName:string; lastSeenAt:string; friend:boolean; }
export interface RoomChatMessage { id: string; senderId: string; senderName: string; avatarUrl?: string; body: string; createdAt: string; }
export interface WatchState { provider:'YOUTUBE'; mediaId:string; title?:string; playing:boolean; positionSeconds:number; playbackRate:number; updatedAt:string; transitionUntil?:string; }
export interface YoutubeResult { videoId:string; title:string; channelTitle:string; thumbnailUrl:string; }
export interface YoutubeSearch { configured:boolean; results:YoutubeResult[]; message?:string; nextPageToken?:string; previousPageToken?:string; }
export type WatchProvider = 'YOUTUBE'|'NETFLIX'|'CRUNCHYROLL'|'TWITCH';
export interface WatchQueueItem { id:string; provider:WatchProvider; mediaId:string; title:string; thumbnailUrl?:string; addedBy:string; addedByName:string; personalPosition:number; voteCount:number; votedByMe:boolean; createdAt:string; }
export interface WatchQueue { mode:'HOSTS_ONLY'|'PERMISSION'|'VOTE'; transitionSeconds:number; canAdd:boolean; nextItemId?:string; skipVotes:number; skipRequired:number; skipVotedByMe:boolean; items:WatchQueueItem[]; }
export interface SkipVoteResult { skipped:boolean; votes:number; required:number; state?:WatchState; }
export interface PublicRoom { id:string;name:string;description?:string;accessPolicy:AccessPolicy;viewerCount:number;mediaTitle?:string;mediaId?:string;viewerAvatars:string[];joined:boolean; }

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
  async sendFriendRequest(userId: string): Promise<void> { await firstValueFrom(this.http.post<void>(`${this.baseUrl}/social/friend-requests/${userId}`, {}, { headers: await this.headers() })); }
  async decideFriendRequest(requestId: string, accept: boolean): Promise<void> { await firstValueFrom(this.http.post<void>(`${this.baseUrl}/social/friend-requests/${requestId}/${accept ? 'accept' : 'reject'}`, {}, { headers: await this.headers() })); }
  async messages(friendId: string): Promise<DirectMessage[]> { return firstValueFrom(this.http.get<DirectMessage[]>(`${this.baseUrl}/social/messages/${friendId}`, { headers: await this.headers() })); }
  async sendMessage(friendId: string, body: string): Promise<DirectMessage> { return firstValueFrom(this.http.post<DirectMessage>(`${this.baseUrl}/social/messages/${friendId}`, { body }, { headers: await this.headers() })); }
  async roomMembers(roomId: string): Promise<RoomMember[]> { return firstValueFrom(this.http.get<RoomMember[]>(`${this.baseUrl}/rooms/${roomId}/members`, { headers: await this.headers() })); }
  async setScreenPermission(roomId: string, userId: string, allowed: boolean): Promise<void> { await firstValueFrom(this.http.post<void>(`${this.baseUrl}/rooms/${roomId}/members/${userId}/screen-permission`, { allowed }, { headers: await this.headers() })); }
  async kickMember(roomId: string, userId: string): Promise<void> { await firstValueFrom(this.http.delete<void>(`${this.baseUrl}/rooms/${roomId}/members/${userId}`, { headers: await this.headers() })); }
  async inviteUser(roomId:string,userId:string):Promise<void>{await firstValueFrom(this.http.post<void>(`${this.baseUrl}/rooms/${roomId}/invite-user/${userId}`,{},{headers:await this.headers()}));}
  async setLeadership(roomId:string,userId:string,action:'CO_HOST'|'MEMBER'|'TRANSFER'):Promise<void>{await firstValueFrom(this.http.post<void>(`${this.baseUrl}/rooms/${roomId}/members/${userId}/leadership/${action}`,{},{headers:await this.headers()}));}
  async updateRoom(roomId: string, input: object): Promise<void> { await firstValueFrom(this.http.patch<void>(`${this.baseUrl}/rooms/${roomId}/settings`, input, { headers: await this.headers() })); }
  async updateProfile(input: {displayName: string; bio: string}): Promise<Profile> { return firstValueFrom(this.http.patch<Profile>(`${this.baseUrl}/me/profile`, input, { headers: await this.headers() })); }
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
  async watchState(roomId:string):Promise<WatchState|null> { return firstValueFrom(this.http.get<WatchState|null>(`${this.baseUrl}/rooms/${roomId}/watch`,{headers:await this.headers()})); }
  async updateWatch(roomId:string,state:Omit<WatchState,'updatedAt'>):Promise<WatchState> { return firstValueFrom(this.http.put<WatchState>(`${this.baseUrl}/rooms/${roomId}/watch`,state,{headers:await this.headers()})); }
  async heartbeatWatch(roomId:string):Promise<WatchState> { return firstValueFrom(this.http.post<WatchState>(`${this.baseUrl}/rooms/${roomId}/watch/heartbeat`,{},{headers:await this.headers()})); }
  async searchYoutube(query:string,pageToken?:string):Promise<YoutubeSearch> {
    const params:Record<string,string>={q:query};if(pageToken)params['pageToken']=pageToken;
    return firstValueFrom(this.http.get<YoutubeSearch>(`${this.baseUrl}/youtube/search`,{params,headers:await this.headers()}));
  }
  async watchQueue(roomId:string):Promise<WatchQueue> { return firstValueFrom(this.http.get<WatchQueue>(`${this.baseUrl}/rooms/${roomId}/watch/queue`,{headers:await this.headers()})); }
  async addToWatchQueue(roomId:string,item:{provider:WatchProvider;mediaId:string;title:string;thumbnailUrl?:string}):Promise<WatchQueueItem> { return firstValueFrom(this.http.post<WatchQueueItem>(`${this.baseUrl}/rooms/${roomId}/watch/queue`,item,{headers:await this.headers()})); }
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

  private async headers(): Promise<HttpHeaders> {
    return new HttpHeaders({ Authorization: `Bearer ${await this.auth.token()}` });
  }
}

