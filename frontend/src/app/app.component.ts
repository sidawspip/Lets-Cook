import { CommonModule } from '@angular/common';
import { Component, ElementRef, HostListener, OnDestroy, OnInit, ViewChild, inject, signal } from '@angular/core';
import { HttpErrorResponse } from '@angular/common/http';
import { FormsModule } from '@angular/forms';
import { ApiService, AccessPolicy, Profile, ProfilePreferences, ProfileConnection, ProfileVisibility, Room, RoomSearchResult, JoinRequest, Friend, FriendRequest, SocialNotification, UserSearchResult, DirectMessage, RoomMember, LiveParticipant, RecentRoomPerson, RoomChatMessage, WatchState, YoutubeResult, WatchQueue, WatchQueueItem, PublicRoom, MediaLibraryDashboard, MediaLibraryItem } from './core/api.service';
import { AuthService } from './core/auth.service';
import { MediaService } from './core/media.service';
import { YoutubePlayer, YoutubePlayerService } from './core/youtube-player.service';
import { WatchSyncService } from './core/watch-sync.service';
import { NotificationStreamService, PushEvent } from './core/notification-stream.service';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './app.component.html'
})
export class AppComponent implements OnInit, OnDestroy {
  readonly auth = inject(AuthService);
  private readonly api = inject(ApiService);
  private readonly youtube = inject(YoutubePlayerService);
  private readonly watchSync = inject(WatchSyncService);
  private readonly notificationStream=inject(NotificationStreamService);
  readonly media = inject(MediaService);
  @ViewChild('videoSurface') private videoSurface?: ElementRef<HTMLDivElement>;
  @ViewChild('youtubeSurface') private youtubeSurface?: ElementRef<HTMLDivElement>;
  @ViewChild('peopleSearch') private peopleSearch?: ElementRef<HTMLInputElement>;

  readonly profile = signal<Profile | null>(null);
  readonly rooms = signal<Room[]>([]);
  readonly publicRooms = signal<PublicRoom[]>([]);
  readonly showPublicHome = signal(true);
  readonly newPartyStep = signal<'providers'|'youtube'|'direct'|'web'|null>(null);
  readonly confirmLeaveForHome = signal(false);
  readonly selectedRoom = signal<Room | null>(null);
  readonly loading = signal(false);
  readonly error = signal('');
  readonly showCreate = signal(false);
  readonly newAccessKey = signal('');
  readonly searchResults = signal<RoomSearchResult[]>([]);
  readonly searching = signal(false);
  readonly showJoin = signal(false);
  readonly showDiscover = signal(false);
  readonly joinRoom = signal<RoomSearchResult | null>(null);
  readonly joinMessage = signal('');
  readonly inviteLink = signal('');
  readonly showDeleteConfirm = signal(false);
  readonly showRequests = signal(false);
  readonly showRoomInvitePeople = signal(false);
  readonly roomInviteMessage = signal('');
  readonly roomRequests = signal<JoinRequest[]>([]);
  readonly socialView = signal<'friends' | 'messages' | null>(null);
  readonly mainView = signal<'room' | 'friends' | 'messages' | 'notifications'>('room');
  readonly pendingRoomSwitch = signal<Room | null>(null);
  readonly watchPicker = signal<'sharing' | 'streaming' | null>(null);
  readonly roomExperience = signal<'sharing'|'youtube'>('sharing');
  readonly youtubeResults = signal<YoutubeResult[]>([]);
  readonly youtubeMessage = signal('');
  readonly youtubeSearching = signal(false);
  readonly youtubeSearchAttempted = signal(false);
  readonly youtubeNextPageToken = signal<string|null>(null);
  readonly youtubePreviousPageToken = signal<string|null>(null);
  readonly youtubeSearchPage = signal(1);
  readonly youtubeState = signal<WatchState|null>(null);
  readonly youtubeLaunchOverlay = signal(false);
  readonly watchQueue = signal<WatchQueue|null>(null);
  readonly transitionCountdown = signal(0);
  readonly activeWatchAvailable = signal(false);
  readonly watchSideTab = signal<'chat'|'inbox'|'recent'|'people'|'queue'>('chat');
  readonly showVideoBrowser = signal(false);
  readonly companionCollapsed = signal(false);
  readonly companionWidth = signal(360);
  readonly sidebarCollapsed = signal(false);
  readonly friends = signal<Friend[]>([]);
  readonly friendRequests = signal<FriendRequest[]>([]);
  readonly notifications = signal<SocialNotification[]>([]);
  readonly peopleResults = signal<UserSearchResult[]>([]);
  readonly chatFriend = signal<Friend | null>(null);
  readonly messages = signal<DirectMessage[]>([]);
  readonly messageSending = signal(false);
  readonly showRoomMenu = signal(false);
  readonly showRoomSettings = signal(false);
  readonly showProfile = signal(false);
  readonly mediaLibraryView = signal<'history'|'likes'|null>(null);
  readonly mediaLibrary = signal<MediaLibraryDashboard|null>(null);
  readonly mediaLibraryLoading = signal(false);
  readonly roomMembers = signal<RoomMember[]>([]);
  readonly theaterMode = signal(false);
  readonly participantsCollapsed = signal(false);
  readonly participantsDrawerOpen = signal(false);
  readonly deviceNotificationsEnabled = signal(typeof Notification !== 'undefined' && Notification.permission === 'granted');
  readonly pushToast=signal<PushEvent|null>(null);
  readonly liveParticipants = signal<LiveParticipant[]>([]);
  readonly recentRoomPeople = signal<RecentRoomPerson[]>([]);
  readonly youtubeSuggestions = signal<YoutubeResult[]>([]);
  readonly showVideoShelf = signal(false);
  readonly showPlaybackSettings = signal(false);
  readonly qualityLevels = signal<string[]>([]);
  readonly captionTracks = signal<Array<{languageCode:string;languageName?:string;name?:string}>>([]);
  readonly selectedQuality = signal('auto');
  readonly selectedCaption = signal('off');
  readonly playerPosition = signal(0);
  readonly playerDuration = signal(0);
  readonly playerMuted = signal(false);
  readonly playerVolume = signal(70);
  readonly playbackNeedsGesture = signal(false);
  readonly webControlsVisible = signal(true);
  readonly roomChatMessages = signal<RoomChatMessage[]>([]);
  readonly roomLikedMediaIds = signal<Set<string>>(new Set());
  readonly roomSessionActive = signal(false);
  readonly participantMenu = signal<string | null>(null);
  readonly avatarPreview = signal('');
  readonly profileError = signal('');

  searchQuery = '';
  joinKey = '';
  inviteCode = '';
  peopleQuery = '';
  messageText = '';
  roomName = '';
  roomDescription = '';
  accessPolicy: AccessPolicy = 'INVITE_OR_KEY';
  approvalRequired = false;
  maxMembers = 25;
  visibility = 'PUBLIC';
  settingsName = '';
  settingsDescription = '';
  settingsVisibility = 'PUBLIC';
  settingsAccessPolicy: AccessPolicy = 'INVITE_OR_KEY';
  settingsApproval = false;
  settingsSharePolicy = 'HOSTS_ONLY';
  profileName = '';
  profileBio = '';
  profileAvatar = '';
  profilePreferences:ProfilePreferences={hideSensitiveContent:false,hideLocation:false,restrictInvites:false,floatingVideo:true,muteOtherAudio:true,hapticFeedback:true,autoTranslate:false,preferredLanguage:'en',quickReaction:'❤️'};
  profileInterests='';
  profileConnections:ProfileConnection[]=[];
  profileVisibility:ProfileVisibility={bio:'PUBLIC',gallery:'PUBLIC',activity:'FRIENDS',stats:'PUBLIC',friends:'FRIENDS',interests:'PUBLIC',connections:'PUBLIC'};
  newConnectionProvider='';
  newConnectionUrl='';
  private avatarFile?: File;
  roomChatText = '';
  youtubeQuery=''; youtubeUrl='';
  webSearchQuery='';
  private youtubePlayer?:YoutubePlayer;
  private directPlayer?:HTMLVideoElement;
  private hls?:{destroy():void};
  private youtubePlayerId='';
  private applyingYoutubeState=false;
  private optimisticPlaybackState:boolean|null=null;
  private playbackCommandSequence=0;
  private playbackCommandTimer?:ReturnType<typeof setTimeout>;
  private lastYoutubeHardSyncAt=0;
  private youtubeSearchTimer?:ReturnType<typeof setTimeout>;
  private autoOpenedWatchKey='';
  private suggestionsForId='';
  private handledEndedMediaKey='';
  private videoHoldTimer?:ReturnType<typeof setTimeout>;
  private webControlsTimer?:ReturnType<typeof setTimeout>;
  private readonly pollingTimers:Array<ReturnType<typeof setInterval>>=[];
  private socialRefreshInFlight=false;
  private readonly seenNotificationIds=new Set<string>();
  private readonly recordedMediaIds=new Set<string>();
  private messageRefreshInFlight=false;
  private resolvedWebTitle='';
  private readonly activeRoomStorageKey='lets-cook.active-room';

  async ngOnInit(): Promise<void> {
    if (this.auth.authenticated()) {
      await this.load();
      await this.restoreActiveRoomSession();
      const invite = location.pathname.match(/^\/invite\/([^/]+)/)?.[1] ?? new URLSearchParams(location.search).get('invite');
      if (invite) { this.inviteCode = invite; this.showJoin.set(true); }
      void this.refreshSocial();
      void this.notificationStream.connect(event=>this.receivePushEvent(event));
      this.pollingTimers.push(
        setInterval(() => { if (this.auth.authenticated()) void this.refreshSocial(false); }, 5000),
        setInterval(() => { if (this.auth.authenticated()) void this.refreshActiveConversation(); }, 2000),
        setInterval(() => { if (this.auth.authenticated()) void this.refreshRooms(); }, 10000),
        setInterval(() => { if (this.auth.authenticated()) void this.refreshPublicRooms(); }, 5000),
        setInterval(() => { if (this.auth.authenticated() && this.roomSessionActive()) { const room=this.selectedRoom();if(room)void this.api.liveHeartbeat(room.id);void this.refreshLiveRoom(); } }, 3000),
        setInterval(() => { if (this.auth.authenticated() && this.roomExperience()==='youtube') void this.syncYoutube(); }, 20000),
        setInterval(() => { if (this.auth.authenticated() && this.roomExperience()==='youtube') void this.refreshWatchQueue(); }, 2500),
        setInterval(() => { if (this.auth.authenticated() && this.roomExperience()==='youtube' && this.canControlWatch()) void this.heartbeatRoomWatch(); }, 5000),
        setInterval(() => { if (this.auth.authenticated() && this.roomExperience()==='sharing') void this.discoverActiveWatch(); }, 2000),
        setInterval(()=>this.refreshPlayerTelemetry(),500)
      );
      void this.discoverActiveWatch();
      void this.refreshPublicRooms();
    }
  }

  ngOnDestroy():void{this.notificationStream.disconnect();for(const timer of this.pollingTimers)clearInterval(timer);if(this.youtubeSearchTimer)clearTimeout(this.youtubeSearchTimer);if(this.playbackCommandTimer)clearTimeout(this.playbackCommandTimer);if(this.videoHoldTimer)clearTimeout(this.videoHoldTimer);if(this.webControlsTimer)clearTimeout(this.webControlsTimer);}

  @HostListener('document:visibilitychange')
  onDocumentVisibilityChange():void{
    if(document.hidden||!this.auth.authenticated()||this.roomExperience()!=='youtube'||!this.selectedRoom())return;
    // Browsers may suspend either the YouTube iframe or a native video while
    // the window is minimized. Reconcile the existing player with the room
    // state on restore without recreating the element or losing local UI state.
    requestAnimationFrame(()=>{void this.syncYoutube();void this.refreshWatchQueue();});
  }

  async refreshRooms(): Promise<void> {
    try {
      const currentId = this.selectedRoom()?.id;
      const rooms = await this.api.rooms();
      this.rooms.set(rooms);
      this.selectedRoom.set(rooms.find(room => room.id === currentId) ?? rooms[0] ?? null);
      if(this.roomExperience()==='sharing') void this.discoverActiveWatch();
    } catch { /* keep the current room visible during a transient refresh failure */ }
  }
  async refreshPublicRooms():Promise<void>{try{this.publicRooms.set(await this.api.publicRooms());}catch{/* retry on next refresh */}}

  async searchRooms(): Promise<void> {
    const query = this.searchQuery.trim();
    if (query.length < 2) { this.searchResults.set([]); return; }
    this.searching.set(true);
    try { this.searchResults.set((await this.api.search(query)).rooms); }
    catch { this.error.set('Room search failed. Please try again.'); }
    finally { this.searching.set(false); }
  }

  async openJoin(room: RoomSearchResult): Promise<void> {
    const existingRoom = this.rooms().find(item => item.id === room.id);
    if (existingRoom) {
      this.selectRoom(existingRoom);
      this.showDiscover.set(false);
      this.searchResults.set([]);
      this.searchQuery = '';
      return;
    }
    if(room.visibility==='PUBLIC'||room.visibility==='FRIENDS'){
      try{const result=await this.api.unlockRoom(room.id,'');await this.load();const joined=this.rooms().find(item=>item.id===result.roomId);if(joined)this.selectRoom(joined);this.showDiscover.set(false);this.searchResults.set([]);this.searchQuery='';}catch{this.error.set('You do not have access to this room.');}return;
    }
    this.joinRoom.set(room); this.joinKey = ''; this.inviteCode = ''; this.joinMessage.set('');
    this.showDiscover.set(false); this.showJoin.set(true); this.searchResults.set([]);
  }

  closeJoin(): void {
    this.showJoin.set(false); this.joinRoom.set(null); this.joinMessage.set('');
    if (location.pathname.startsWith('/invite/')) history.replaceState({}, '', '/');
  }

  async submitJoin(): Promise<void> {
    const room = this.joinRoom();
    if (!room && !this.inviteCode.trim()) return;
    this.loading.set(true); this.joinMessage.set('');
    try {
      const result = this.inviteCode.trim()
        ? await this.api.acceptInvite(this.extractInviteCode(this.inviteCode), this.joinKey.trim() || undefined)
        : await this.api.unlockRoom(room!.id, this.joinKey.trim());
      if (!result.accessGranted) {
        this.joinMessage.set('Request sent. A host must approve you before the room appears.');
        return;
      }
      await this.load();
      this.selectedRoom.set(this.rooms().find(item => item.id === result.roomId) ?? this.selectedRoom());
      this.autoOpenedWatchKey='';void this.discoverActiveWatch();
      this.closeJoin(); this.searchQuery = '';
    } catch (error: unknown) {
      this.joinMessage.set('Could not join. Check the room key or invite link and try again.');
    } finally { this.loading.set(false); }
  }

  private extractInviteCode(value: string): string {
    const trimmed = value.trim();
    const match = trimmed.match(/\/invite\/([^/?#]+)/);
    return decodeURIComponent(match?.[1] ?? trimmed);
  }

  async shareInvite(): Promise<void> {
    const room = this.selectedRoom();
    if (!room) return;
    try {
      const invite = await this.api.createInvite(room.id);
      const link = `${location.origin}${invite.path}`;
      await navigator.clipboard.writeText(link);
      this.inviteLink.set(link);
      setTimeout(() => this.inviteLink.set(''), 5000);
    } catch { this.error.set('Only a host or co-host can create invite links.'); }
  }

  async deleteSelectedRoom(): Promise<void> {
    const room = this.selectedRoom();
    if (!room) return;
    this.loading.set(true); this.error.set('');
    try {
      this.media.disconnect();
      await this.api.deleteRoom(room.id);
      this.rooms.update(items => items.filter(item => item.id !== room.id));
      this.selectedRoom.set(this.rooms()[0] ?? null);
      this.showDeleteConfirm.set(false);
    } catch { this.error.set('The room could not be deleted. Only its original owner can delete it.'); }
    finally { this.loading.set(false); }
  }

  async openRoomRequests(): Promise<void> {
    const room = this.selectedRoom(); if (!room) return;
    this.roomRequests.set(await this.api.joinRequests(room.id)); this.showRequests.set(true);
  }

  async decideRoomRequest(request: JoinRequest, approve: boolean): Promise<void> {
    const room = this.selectedRoom(); if (!room) return;
    await this.api.decideJoinRequest(room.id, request.userId, approve);
    this.roomRequests.update(items => items.filter(item => item.userId !== request.userId));
    await this.load();
  }

  async openSocial(view: 'friends' | 'messages'): Promise<void> {
    this.mainView.set(view); await this.refreshSocial();
    if (view === 'messages' && !this.chatFriend() && this.friends().length) await this.loadMessages(this.friends()[0]);
  }

  async openNotifications():Promise<void>{this.mainView.set('notifications');await this.refreshSocial();}
  async enableDeviceNotifications():Promise<void>{
    if(typeof Notification==='undefined'){this.error.set('Device notifications are not supported by this browser.');return;}
    const permission=await Notification.requestPermission();this.deviceNotificationsEnabled.set(permission==='granted');
    if(permission!=='granted')this.error.set('Notifications are blocked. Allow them in the browser site settings.');
  }
  notificationCount():number{return this.notifications().reduce((total,item)=>total+(item.type==='DIRECT_MESSAGE'?item.unreadCount:1),0);}
  async openNotification(item:SocialNotification):Promise<void>{
    if(item.type==='FRIEND_REQUEST'){this.mainView.set('friends');return;}
    const friend=this.friends().find(candidate=>candidate.id===item.userId);
    if(friend)await this.loadMessages(friend);
  }
  focusPeopleSearch():void{this.peopleQuery='';this.peopleResults.set([]);setTimeout(()=>this.peopleSearch?.nativeElement.focus());}
  private receivePushEvent(event:PushEvent):void{
    this.pushToast.set(event);setTimeout(()=>{if(this.pushToast()===event)this.pushToast.set(null);},10000);
    if(this.deviceNotificationsEnabled()){
      const alert=new Notification(event.type==='ROOM_INVITE'?`${event.senderName} invited you`:`Message from ${event.senderName}`,{body:event.body,tag:`${event.type}:${event.roomId||event.senderId}`});
      alert.onclick=()=>{window.focus();void this.openPushEvent(event);alert.close();};
    }
    if(event.type==='DIRECT_MESSAGE')void this.refreshNotifications();
  }
  async openPushEvent(event:PushEvent):Promise<void>{
    this.pushToast.set(null);
    if(event.type==='ROOM_INVITE'&&event.roomId){await this.refreshRooms();const room=this.rooms().find(candidate=>candidate.id===event.roomId);if(room)this.selectRoom(room);return;}
    await this.refreshSocial(false);const friend=this.friends().find(candidate=>candidate.id===event.senderId);if(friend)await this.loadMessages(friend);
  }

  showHome(): void { if(this.roomSessionActive())this.exitRoomSession();this.mainView.set('room');this.showPublicHome.set(true);void this.refreshPublicRooms(); }
  requestHome():void { if(this.roomSessionActive()){this.confirmLeaveForHome.set(true);return;}this.showHome(); }
  confirmHomeLeave():void { this.confirmLeaveForHome.set(false);this.showHome(); }

  async refreshSocial(showErrors = true): Promise<void> {
    if(this.socialRefreshInFlight)return;
    this.socialRefreshInFlight=true;
    try {
      const [friends, requests, notifications] = await Promise.all([this.api.friends(), this.api.friendRequests(), this.api.notifications()]);
      this.friends.set(friends); this.friendRequests.set(requests); this.notifications.set(notifications);
      if (this.chatFriend() && this.mainView() === 'messages') await this.refreshMessages(this.chatFriend()!);
    } catch { if (showErrors) this.error.set('Could not refresh friends and presence.'); }
    finally{this.socialRefreshInFlight=false;}
  }

  async searchPeople(): Promise<void> {
    if (this.peopleQuery.trim().length < 2) { this.peopleResults.set([]); return; }
    this.peopleResults.set((await this.api.search(this.peopleQuery.trim())).users);
  }

  async addFriend(user: UserSearchResult): Promise<void> {
    try { await this.api.sendFriendRequest(user.id); this.peopleResults.update(items => items.filter(item => item.id !== user.id)); }
    catch { this.error.set('A friend request already exists for this user.'); }
  }

  async decideFriend(request: FriendRequest, accept: boolean): Promise<void> {
    await this.api.decideFriendRequest(request.id, accept); await this.refreshSocial();
  }

  async loadMessages(friend: Friend): Promise<void> {
    this.mainView.set('messages'); this.chatFriend.set(friend); this.error.set('');
    try{await this.refreshMessages(friend);await this.refreshNotifications();}
    catch{this.error.set('Could not open this conversation. Please try again.');}
  }
  private async refreshMessages(friend:Friend):Promise<void>{this.messages.set(await this.api.messages(friend.id));}
  private async refreshActiveConversation():Promise<void>{
    const friend=this.chatFriend();if(!friend||this.mainView()!=='messages'||this.messageRefreshInFlight)return;
    this.messageRefreshInFlight=true;try{await this.refreshMessages(friend);await this.refreshNotifications();}catch{/* transient polling failures retry */}finally{this.messageRefreshInFlight=false;}
  }
  private async refreshNotifications():Promise<void>{try{
    const items=await this.api.notifications();
    items.forEach(item=>this.seenNotificationIds.add(item.id));this.notifications.set(items);
  }catch{/* retry on the next social refresh */}}
  formatTogether(seconds:number):string{const safe=Math.max(0,Math.floor(seconds||0));if(safe>=3600){const hours=Math.floor(safe/3600),minutes=Math.floor((safe%3600)/60);return minutes?`${hours}h ${minutes}m`:`${hours}h`;}return safe>=60?`${Math.floor(safe/60)}m`:'<1m';}
  async loadRoomInbox(friend:Friend):Promise<void>{this.chatFriend.set(friend);this.messages.set(await this.api.messages(friend.id));}

  async sendMessage(): Promise<void> {
    const friend=this.chatFriend(), body=this.messageText.trim(); if(!friend || !body || this.messageSending()) return;
    this.messageSending.set(true);this.error.set('');
    try{const sent=await this.api.sendMessage(friend.id,body);this.messages.update(items=>[...items,sent]);this.messageText='';}
    catch{this.error.set('Message could not be sent. Check your connection and try again.');}
    finally{this.messageSending.set(false);}
  }

  async openRoomSettings(): Promise<void> {
    const room=this.selectedRoom(); if(!room) return;
    this.settingsName=room.name; this.settingsDescription=room.description??''; this.settingsVisibility=room.visibility;
    this.settingsAccessPolicy=room.accessPolicy; this.settingsSharePolicy=room.screenSharePolicy;
    this.roomMembers.set(await this.api.roomMembers(room.id)); this.showRoomMenu.set(false); this.showRoomSettings.set(true);
  }

  async saveRoomSettings(): Promise<void> {
    const room=this.selectedRoom(); if(!room) return;
    await this.api.updateRoom(room.id,{name:this.settingsName,description:this.settingsDescription,visibility:this.settingsVisibility,
      accessPolicy:this.settingsVisibility==='PUBLIC'?'OPEN':'INVITE_ONLY',approvalRequired:false,screenSharePolicy:this.settingsSharePolicy});
    await this.api.updateProfilePreferences(this.profilePreferences);
    await this.refreshRooms(); this.showRoomSettings.set(false);
  }

  async toggleMemberSharing(member: RoomMember): Promise<void> {
    const room=this.selectedRoom(); if(!room) return;
    await this.api.setScreenPermission(room.id,member.userId,!member.canShareScreen);
    this.roomMembers.update(items=>items.map(item=>item.userId===member.userId?{...item,canShareScreen:!item.canShareScreen}:item));
  }

  async toggleParticipantSharing(person: LiveParticipant): Promise<void> {
    const room=this.selectedRoom(); if(!room) return;
    try {
      await this.api.setScreenPermission(room.id,person.userId,!person.canShareScreen);
      this.liveParticipants.update(items=>items.map(item=>item.userId===person.userId
        ? {...item,canShareScreen:!item.canShareScreen}:item));
      this.participantMenu.set(null);
    } catch { this.error.set('Could not update this member’s screen-sharing permission.'); }
  }

  async kickParticipant(person: LiveParticipant): Promise<void> {
    const room=this.selectedRoom(); if(!room || person.role==='HOST') return;
    try {
      await this.api.kickMember(room.id,person.userId);
      this.liveParticipants.update(items=>items.filter(item=>item.userId!==person.userId));
      this.roomMembers.update(items=>items.filter(item=>item.userId!==person.userId));
      this.participantMenu.set(null);
      await this.refreshRooms();
    } catch { this.error.set('Could not remove this member from the room.'); }
  }

  toggleTheater(): void { this.theaterMode.update(value=>!value); }
  async toggleFullscreen(): Promise<void> {
    const surface=this.videoSurface?.nativeElement; if(!surface) return;
    if(document.fullscreenElement) await document.exitFullscreen(); else await surface.requestFullscreen();
  }

  async openProfile(): Promise<void> {
    const profile=this.profile(); if(!profile) return;
    this.profileName=profile.displayName; this.profileBio=profile.bio??''; this.profileAvatar=profile.avatarUrl??'';
    this.avatarFile=undefined; this.avatarPreview.set(profile.avatarUrl??''); this.profileError.set(''); this.showProfile.set(true);
    try{const dashboard=await this.api.profileDashboard();this.profilePreferences=dashboard.preferences;this.profileVisibility=dashboard.visibility;this.profileConnections=dashboard.connections;this.profileInterests=dashboard.interests.join(', ');}catch{this.profileError.set('Some profile settings could not be loaded.');}
  }
  addProfileConnection():void{const provider=this.newConnectionProvider.trim().toUpperCase(),url=this.newConnectionUrl.trim();if(!provider||!url.startsWith('https://')){this.profileError.set('Enter a service name and HTTPS profile URL.');return;}this.profileConnections=[...this.profileConnections.filter(x=>x.provider!==provider),{provider,url}];this.newConnectionProvider='';this.newConnectionUrl='';}
  removeProfileConnection(provider:string):void{this.profileConnections=this.profileConnections.filter(x=>x.provider!==provider);}
  chooseAvatar(event: Event): void {
    const input=event.target as HTMLInputElement;
    const file=input.files?.[0]; if(!file) return;
    if(!['image/jpeg','image/png','image/webp','image/gif'].includes(file.type) || file.size>5*1024*1024) {
      this.profileError.set('Choose a JPG, PNG, WebP, or GIF image up to 5 MB.'); input.value=''; return;
    }
    this.avatarFile=file; this.avatarPreview.set(URL.createObjectURL(file));
  }
  async saveProfile(): Promise<void> {
    this.loading.set(true); this.profileError.set('');
    try {
      let updated=await this.api.updateProfile({displayName:this.profileName,bio:this.profileBio});
      if(this.avatarFile) updated=await this.api.uploadAvatar(this.avatarFile);
      await Promise.all([this.api.updateProfilePreferences(this.profilePreferences),this.api.updateProfileVisibility(this.profileVisibility),this.api.updateProfileConnections(this.profileConnections),this.api.updateProfileInterests(this.profileInterests.split(',').map(x=>x.trim()).filter(Boolean))]);
      this.profile.set(updated); this.profileAvatar=updated.avatarUrl??''; this.avatarFile=undefined; this.showProfile.set(false);
    } catch { this.profileError.set('Could not upload the image. Use JPG, PNG, WebP, or GIF up to 5 MB.'); }
    finally { this.loading.set(false); }
  }

  async refreshLiveRoom(): Promise<void> {
    const room=this.selectedRoom(); if(!room || !this.roomSessionActive()) return;
    try {
      const [participants,messages,recent]=await Promise.all([this.api.liveParticipants(room.id),this.api.roomChat(room.id),this.api.recentRoomPeople(room.id)]);
      this.liveParticipants.set(participants); this.roomChatMessages.set(messages);this.recentRoomPeople.set(recent);
      const queue=this.watchQueue();if(queue)this.removeQueuedSuggestions(queue);
    } catch (error: unknown) {
      if (error instanceof HttpErrorResponse && error.status === 403) {
        this.media.disconnect();
        this.roomSessionActive.set(false);
        this.liveParticipants.set([]); this.roomChatMessages.set([]);
        this.error.set('The host removed you from this room. Use a new invite or the room key to request access again.');
        await this.refreshRooms();
      }
      /* Other polling failures are transient. */
    }
  }

  async sendRoomMessage(): Promise<void> {
    const room=this.selectedRoom(),body=this.roomChatText.trim(); if(!room||!body)return;
    if(!this.roomSessionActive())await this.enterRoomSession();if(!this.roomSessionActive()){this.error.set('Could not join the room chat.');return;}
    try { const message=await this.api.sendRoomChat(room.id,body);this.roomChatMessages.update(items=>[...items,message]);this.roomChatText=''; }
    catch { this.error.set('Could not send this room message. Please try again.'); }
  }

  async load(): Promise<void> {
    this.loading.set(true);
    this.error.set('');
    try {
      const [profile, rooms] = await Promise.all([this.api.profile(), this.api.rooms()]);
      this.profile.set(profile);
      this.rooms.set(rooms);
      this.selectedRoom.set(rooms[0] ?? null);
    } catch (error: unknown) {
      this.error.set(error instanceof Error ? error.message : 'Could not load the workspace.');
    } finally {
      this.loading.set(false);
    }
  }

  async createRoom(): Promise<void> {
    if (!this.roomName.trim()) return;
    this.loading.set(true);
    this.error.set('');
    try {
      const result = await this.api.createRoom({
        name: this.roomName.trim(),
        description: this.roomDescription.trim(),
        accessPolicy: this.visibility==='PUBLIC'?'OPEN':'INVITE_ONLY',
        approvalRequired: false,
        maxMembers: this.maxMembers,
        visibility: this.visibility
      });
      this.rooms.update(rooms => [result.room, ...rooms]);
      this.selectedRoom.set(result.room);
      this.newAccessKey.set(result.accessKey ?? 'This room uses invite-only access.');
      this.roomName = '';
      this.roomDescription = '';
    } catch (error: unknown) {
      this.error.set(error instanceof Error ? error.message : 'Could not create the room.');
    } finally {
      this.loading.set(false);
    }
  }

  async inviteFriendToRoom(friend:Friend):Promise<void>{const room=this.selectedRoom();if(!room)return;try{await this.api.inviteUser(room.id,friend.id);this.roomInviteMessage.set(`${friend.displayName} can now see and join this room.`);await this.refreshRooms();}catch{this.roomInviteMessage.set('Could not invite this user.');}}

  closeCreate(): void {
    this.showCreate.set(false);
    this.newAccessKey.set('');
  }

  copyKey(): void {
    void navigator.clipboard.writeText(this.newAccessKey());
  }

  selectRoom(room: Room): void {
    this.showPublicHome.set(false);
    if (this.selectedRoom()?.id === room.id) { this.mainView.set('room');setTimeout(()=>void this.joinMedia());return; }
    if(this.roomSessionActive()) { this.pendingRoomSwitch.set(room); return; }
    this.switchRoom(room);
  }

  confirmRoomSwitch(): void {
    const room=this.pendingRoomSwitch(); if(!room) return;
    this.media.disconnect();
    this.liveParticipants.set([]); this.roomChatMessages.set([]);
    this.pendingRoomSwitch.set(null); this.switchRoom(room);
  }

  private switchRoom(room:Room):void {
    const previous=this.selectedRoom();if(previous&&this.roomSessionActive())void this.api.liveLeave(previous.id);
    this.roomSessionActive.set(false);this.liveParticipants.set([]);this.roomChatMessages.set([]);
    this.selectedRoom.set(room); this.mainView.set('room');this.autoOpenedWatchKey='';this.activeWatchAvailable.set(false);setTimeout(()=>{void this.joinMedia();void this.discoverActiveWatch();});
  }

  async openPublicParty(party:PublicRoom):Promise<void>{
    let room=this.rooms().find(item=>item.id===party.id);
    if(!room){try{await this.api.unlockRoom(party.id,'');await this.load();room=this.rooms().find(item=>item.id===party.id);}catch{this.error.set('Could not join this public party.');return;}}
    if(room)this.selectRoom(room);
  }

  async startInstantParty(mode:'sharing'|'youtube'):Promise<void>{
    if(mode==='youtube'){this.youtubeResults.set([]);this.youtubeMessage.set('');this.youtubeQuery='';this.newPartyStep.set('providers');return;}
    this.loading.set(true);this.error.set('');
    try{const display=this.profile()?.displayName||'New';if(this.roomSessionActive())this.exitRoomSession();const result=await this.api.createRoom({name:`${display}'s party ${Date.now().toString().slice(-5)}`,description:'Live screen-sharing party',accessPolicy:'OPEN',approvalRequired:false,maxMembers:50,visibility:'PUBLIC',ephemeral:true});this.rooms.update(items=>[result.room,...items]);this.selectedRoom.set(result.room);this.roomSessionActive.set(false);this.showPublicHome.set(false);await this.enterRoomSession();this.roomExperience.set('sharing');this.watchPicker.set('sharing');}
    catch{this.error.set('Could not start the live party.');}finally{this.loading.set(false);}
  }

  selectNewPartyProvider(provider:'YOUTUBE'|'DIRECT'|'WEB'|'NETFLIX'|'CRUNCHYROLL'|'TWITCH'):void{
    if(provider==='DIRECT'){this.newPartyStep.set('direct');this.youtubeUrl='';this.youtubeMessage.set('');return;}
    if(provider==='WEB'){this.newPartyStep.set('web');this.youtubeUrl='';this.youtubeMessage.set('');return;}
    if(provider!=='YOUTUBE')return;this.newPartyStep.set('youtube');this.youtubeResults.set([]);this.youtubeMessage.set('');
  }

  async createPartyFromVideo(video:YoutubeResult):Promise<void>{
    this.loading.set(true);this.error.set('');
    try{const display=this.profile()?.displayName||'New';if(this.roomSessionActive())this.exitRoomSession();const result=await this.api.createRoom({name:`${display}'s party ${Date.now().toString().slice(-5)}`,description:video.title,accessPolicy:'OPEN',approvalRequired:false,maxMembers:50,visibility:'PUBLIC',ephemeral:true});this.rooms.update(items=>[result.room,...items]);this.selectedRoom.set(result.room);this.mainView.set('room');this.roomSessionActive.set(false);this.youtubeState.set(null);this.watchQueue.set(null);this.showPublicHome.set(false);this.newPartyStep.set(null);this.roomExperience.set('youtube');this.showVideoBrowser.set(false);this.watchSideTab.set('chat');await this.enterRoomSession();await this.refreshWatchQueue();const queued=await this.api.addToWatchQueue(result.room.id,{provider:'YOUTUBE',mediaId:video.videoId,title:video.title,thumbnailUrl:video.thumbnailUrl});await this.refreshWatchQueue();await this.startQueueItem(queued);}
    catch{this.error.set('Could not create and start this party.');this.newPartyStep.set('youtube');}finally{this.loading.set(false);}
  }
  async createPartyFromDirect():Promise<void>{
    const parsed=this.directMedia(this.youtubeUrl);if(!parsed){this.youtubeMessage.set('Paste a public HTTPS .mp4 or .m3u8 URL.');return;}const direct={...parsed,title:this.resolvedWebTitle||parsed.title};this.resolvedWebTitle='';
    this.loading.set(true);this.error.set('');
    try{const display=this.profile()?.displayName||'New';if(this.roomSessionActive())this.exitRoomSession();const result=await this.api.createRoom({name:`${display}'s party ${Date.now().toString().slice(-5)}`,description:direct.title,accessPolicy:'OPEN',approvalRequired:false,maxMembers:50,visibility:'PUBLIC',ephemeral:true});this.rooms.update(items=>[result.room,...items]);this.selectedRoom.set(result.room);this.mainView.set('room');this.roomSessionActive.set(false);this.youtubeState.set(null);this.watchQueue.set(null);this.showPublicHome.set(false);this.newPartyStep.set(null);this.roomExperience.set('youtube');this.showVideoBrowser.set(false);this.watchSideTab.set('chat');await this.enterRoomSession();await this.refreshWatchQueue();const queued=await this.api.addToWatchQueue(result.room.id,{provider:direct.provider,mediaId:direct.url,title:direct.title});await this.refreshWatchQueue();await this.startQueueItem(queued);}
    catch{this.error.set('Could not create and start this party.');this.newPartyStep.set('direct');}finally{this.loading.set(false);}
  }
  async resolveWebAndCreateParty():Promise<void>{
    const pageUrl=this.youtubeUrl.trim();if(!pageUrl.startsWith('https://')){this.youtubeMessage.set('Paste a public HTTPS webpage URL.');return;}
    this.loading.set(true);this.youtubeMessage.set('Resolving the selected webpage…');
    try{const media=await this.api.resolveWebMedia(pageUrl);this.youtubeUrl=media.sourceUrl;this.resolvedWebTitle=[media.title,media.siteName].filter(Boolean).join(' · ');this.youtubeMessage.set('');await this.createPartyFromDirect();}
    catch(e){this.youtubeMessage.set(e instanceof HttpErrorResponse?(e.error?.detail||'This page does not expose a public MP4 or HLS stream.'):'This webpage could not be resolved.');this.loading.set(false);}
  }

  async changeLeadership(person:LiveParticipant,action:'CO_HOST'|'MEMBER'|'TRANSFER'):Promise<void>{const room=this.selectedRoom();if(!room)return;try{await this.api.setLeadership(room.id,person.userId,action);this.participantMenu.set(null);await this.refreshRooms();await this.refreshLiveRoom();}catch(e){this.error.set(e instanceof HttpErrorResponse&&e.status===409?'This room already has 3 co-hosts.':'Could not change this member’s role.');}}

  isJoinedRoom(roomId: string): boolean {
    return this.rooms().some(room => room.id === roomId);
  }
  roomsByVisibility(visibility:'PUBLIC'|'FRIENDS'|'PRIVATE'):Room[]{return this.rooms().filter(room=>room.visibility===visibility);}

  async joinMedia(): Promise<void> {
    await this.enterRoomSession();
  }

  async joinRealtimeMedia(): Promise<void> {
    const room=this.selectedRoom();
    if(!room||!this.videoSurface)return;
    await this.enterRoomSession();
    try { await this.media.connect(room.id,this.videoSurface.nativeElement);await this.refreshLiveRoom(); }
    catch { /* MediaService exposes the public endpoint or permission error. */ }
  }

  async toggleScreenShare(): Promise<void> {
    const room = this.selectedRoom();
    if (room && this.videoSurface) { this.watchPicker.set(null); await this.media.toggleScreenShare(room.id, this.videoSurface.nativeElement); }
  }
  async switchToYoutubeInRoom():Promise<void> {
    const room=this.selectedRoom();
    if(!room||!this.canControlWatch())return;
    if(this.media.sharing()&&this.videoSurface){
      await this.media.toggleScreenShare(room.id,this.videoSurface.nativeElement);
    }
    await this.openYoutube();
    this.showVideoBrowser.set(true);
    this.watchSideTab.set('chat');
  }
  chooseSharingInRoom():void {
    if(!this.canControlWatch())return;
    this.roomExperience.set('sharing');
    this.watchPicker.set('sharing');
    this.rememberActiveRoom();
  }
  async stopScreenSharing():Promise<void> {
    const room=this.selectedRoom();
    if(!room||!this.videoSurface||!this.media.sharing())return;
    await this.media.toggleScreenShare(room.id,this.videoSurface.nativeElement);
  }
  async toggleMicrophone(): Promise<void> {
    const room=this.selectedRoom();
    if(!room||!this.videoSurface)return;
    try { await this.media.toggleMicrophone(room.id,this.videoSurface.nativeElement); }
    catch { /* MediaService exposes a useful mobile/network error in the room UI. */ }
  }
  async toggleSpeaker(): Promise<void> {
    const room=this.selectedRoom();if(!room||!this.videoSurface)return;
    try { await this.media.toggleSpeaker(room.id,this.videoSurface.nativeElement); }
    catch { /* MediaService exposes the public endpoint or autoplay error. */ }
  }
  canControlWatch():boolean { return this.selectedRoom()?.role==='HOST'; }
  partyArtwork():string {
    const state=this.youtubeState();
    return state?.provider==='YOUTUBE'&&state.mediaId
      ? `url("https://i.ytimg.com/vi/${encodeURIComponent(state.mediaId)}/hqdefault.jpg")`
      : 'none';
  }
  startCompanionResize(event:PointerEvent):void{
    if(this.companionCollapsed())return;event.preventDefault();const startX=event.clientX,startWidth=this.companionWidth();
    const move=(next:PointerEvent)=>this.companionWidth.set(Math.max(270,Math.min(560,startWidth+startX-next.clientX)));
    const stop=()=>{window.removeEventListener('pointermove',move);window.removeEventListener('pointerup',stop);};
    window.addEventListener('pointermove',move);window.addEventListener('pointerup',stop,{once:true});
  }
  async openYoutube():Promise<void> {
    this.watchPicker.set(null);this.roomExperience.set('youtube');this.youtubeMessage.set('');
    this.rememberActiveRoom();
    this.showVideoBrowser.set(!this.youtubeState());setTimeout(()=>{void this.ensureRoomPresence();void this.connectWatchEvents();void this.syncYoutube(true);void this.refreshWatchQueue();});
  }
  private async connectWatchEvents():Promise<void>{const room=this.selectedRoom();if(!room)return;await this.watchSync.connect(room.id,event=>{if(event.state.revision<(this.youtubeState()?.revision??0))return;this.youtubeState.set(event.state);this.clearOptimisticPlaybackState();void this.syncYoutube(true);});}
  showWebControls():void{this.webControlsVisible.set(true);if(this.webControlsTimer)clearTimeout(this.webControlsTimer);if(this.youtubeState()?.playing)this.webControlsTimer=setTimeout(()=>this.webControlsVisible.set(false),3000);}
  private async discoverActiveWatch():Promise<void> {
    const room=this.selectedRoom();if(!room||this.mainView()!=='room')return;
    try {
      const state=await this.api.watchState(room.id);if(!state){this.activeWatchAvailable.set(false);return;}
      const fresh=Date.now()-new Date(state.updatedAt).getTime()<15000;
      const transitioning=!!state.transitionUntil&&new Date(state.transitionUntil).getTime()>Date.now();
      const live=(state.playing&&fresh)||transitioning;this.activeWatchAvailable.set(live);
      const key=`${room.id}:${state.mediaId}`;
      if(live&&this.roomExperience()==='sharing'&&this.autoOpenedWatchKey!==key){
        this.autoOpenedWatchKey=key;this.youtubeState.set(state);this.watchPicker.set(null);this.roomExperience.set('youtube');this.rememberActiveRoom();
        this.youtubeMessage.set('Joined the room’s live playback.');this.showVideoBrowser.set(false);setTimeout(()=>{void this.ensureRoomPresence();void this.connectWatchEvents();void this.syncYoutube(true);void this.refreshWatchQueue();});
      }
    } catch { /* the user may still be waiting for room approval */ }
  }
  showSharing():void { this.roomExperience.set('sharing');this.rememberActiveRoom(); }
  async searchYoutube(queryFromInput?:string,pageToken?:string,pageDelta=0):Promise<void> {
    const query=(queryFromInput??this.youtubeQuery).trim();this.youtubeQuery=query;
    if(query.length<2){this.youtubeMessage.set('Enter at least 2 characters.');return;}
    this.youtubeSearching.set(true);this.youtubeSearchAttempted.set(true);this.youtubeMessage.set('');
    try {
      const response=await this.api.searchYoutube(query,pageToken);this.youtubeResults.set(response.results.map(video=>({...video,thumbnailUrl:this.youtubePreview(video.videoId)})));
      this.youtubeNextPageToken.set(response.nextPageToken??null);this.youtubePreviousPageToken.set(response.previousPageToken??null);
      this.youtubeSearchPage.set(pageToken?Math.max(1,this.youtubeSearchPage()+pageDelta):1);
      this.youtubeMessage.set(response.message??(response.results.length?'':`No videos found for “${query}”.`));
    }
    catch(e) {
      if(!pageToken){this.youtubeResults.set([]);this.youtubeNextPageToken.set(null);this.youtubePreviousPageToken.set(null);this.youtubeSearchPage.set(1);}
      this.youtubeMessage.set(e instanceof HttpErrorResponse?`YouTube search failed (${e.status || 'network error'}).`:'YouTube search could not be completed.');
    }
    finally { this.youtubeSearching.set(false); }
  }
  searchYoutubeWhileTyping(value:string):void {
    this.youtubeQuery=value;
    if(this.youtubeSearchTimer)clearTimeout(this.youtubeSearchTimer);
    if(value.trim().length<2){this.youtubeResults.set([]);return;}
    this.youtubeSearchTimer=setTimeout(()=>void this.searchYoutube(value),450);
  }
  @HostListener('input',['$event'])
  handleYoutubeSearchInput(event:Event):void {
    const input=event.target as HTMLInputElement|null;
    if(input?.placeholder==='Search YouTube videos')this.searchYoutubeWhileTyping(input.value);
  }
  nextYoutubePage():void{const token=this.youtubeNextPageToken();if(token&&!this.youtubeSearching())void this.searchYoutube(this.youtubeQuery,token,1);}
  previousYoutubePage():void{const token=this.youtubePreviousPageToken();if(token&&!this.youtubeSearching())void this.searchYoutube(this.youtubeQuery,token,-1);}
  async playYoutubeInput():Promise<void> {
    const direct=this.directMedia(this.youtubeUrl);if(direct){if(this.newPartyStep()==='direct'){await this.createPartyFromDirect();return;}const room=this.selectedRoom();if(!room||!this.watchQueue()?.canAdd)return;try{const queued=await this.api.addToWatchQueue(room.id,{provider:direct.provider,mediaId:direct.url,title:direct.title});this.youtubeUrl='';await this.refreshWatchQueue();if(!this.youtubeState()&&this.canControlWatch())await this.startQueueItem(queued);else this.youtubeMessage.set('Direct media added to Up next.');}catch{this.youtubeMessage.set('Could not add that direct media URL.');}return;}
    const id=this.youtubeId(this.youtubeUrl);if(!id){this.youtubeMessage.set('Paste a valid YouTube, HTTPS MP4, or HLS URL.');return;}
    const video={videoId:id,title:'YouTube video',channelTitle:'',thumbnailUrl:''};if(this.newPartyStep()==='youtube')await this.createPartyFromVideo(video);else await this.queueYoutube(video);
  }
  async resolveWebIntoRoom():Promise<void>{
    const room=this.selectedRoom();if(!room||!this.watchQueue()?.canAdd)return;const pageUrl=this.youtubeUrl.trim();
    if(!pageUrl.startsWith('https://')){this.youtubeMessage.set('Paste a public HTTPS webpage URL.');return;}
    this.youtubeSearching.set(true);this.youtubeMessage.set('Resolving the selected webpage…');
    try{const media=await this.api.resolveWebMedia(pageUrl);const title=[media.title,media.siteName].filter(Boolean).join(' · ');const queued=await this.api.addToWatchQueue(room.id,{provider:media.sourceType,mediaId:media.sourceUrl,title:title||'Web video'});this.youtubeUrl='';await this.refreshWatchQueue();if(!this.youtubeState()&&this.canControlWatch())await this.startQueueItem(queued);else this.youtubeMessage.set('Web video added to Up next.');}
    catch(e){this.youtubeMessage.set(e instanceof HttpErrorResponse?(e.error?.detail||'This page does not expose a public MP4 or HLS stream.'):'This webpage could not be resolved.');}
    finally{this.youtubeSearching.set(false);}
  }
  openWebSearch(engine:'GOOGLE'|'DUCKDUCKGO'):void{
    const query=this.webSearchQuery.trim();
    const url=engine==='DUCKDUCKGO'
      ? `https://duckduckgo.com/?q=${encodeURIComponent(query)}`
      : `https://www.google.com/search?q=${encodeURIComponent(query)}`;
    window.open(url,'_blank','noopener,noreferrer');
    this.youtubeMessage.set('Open a result, copy its webpage URL, then paste it here to play it in the room.');
  }
  async chooseYoutube(video:YoutubeResult):Promise<void> {
    if(this.newPartyStep()==='youtube'){await this.createPartyFromVideo(video);return;}
    await this.queueYoutube(video);
  }
  async queueYoutube(video:YoutubeResult,quickPick=false):Promise<void> {
    const room=this.selectedRoom();if(!room||!this.watchQueue()?.canAdd)return;
    if(quickPick&&this.myQueueItems().length){this.youtubeMessage.set('You already have a room pick. Use search to add more videos to your personal queue.');this.showVideoShelf.set(false);return;}
    this.showVideoBrowser.set(false);this.watchSideTab.set('chat');
    try { const queued=await this.api.addToWatchQueue(room.id,{provider:'YOUTUBE',mediaId:video.videoId,title:video.title,thumbnailUrl:video.thumbnailUrl});this.youtubeSuggestions.update(items=>items.filter(item=>item.videoId!==video.videoId));this.youtubeResults.set([]);this.youtubeUrl='';await this.refreshWatchQueue();if(!this.youtubeState()&&this.canControlWatch()){this.youtubeMessage.set('Starting video…');await this.startQueueItem(queued);}else this.youtubeMessage.set('Added to Up next.'); }
    catch(e){this.youtubeMessage.set(e instanceof HttpErrorResponse&&e.status===403?'The host has not allowed you to add videos.':'Could not add this video.');this.showVideoBrowser.set(true);}
  }
  async refreshWatchQueue():Promise<void> {
    const room=this.selectedRoom();if(!room)return;try{const queue=await this.api.watchQueue(room.id);queue.items=queue.items.map(item=>item.provider==='YOUTUBE'?{...item,thumbnailUrl:this.youtubePreview(item.mediaId)}:item);this.watchQueue.set(queue);this.removeQueuedSuggestions(queue);}catch{}
  }
  private playedRoomMediaIds():Set<string>{return new Set(this.roomChatMessages().filter(message=>message.type==='VIDEO'&&message.mediaId).map(message=>message.mediaId!));}
  private playedRoomMediaTitles():Set<string>{return new Set(this.roomChatMessages().filter(message=>message.type==='VIDEO'&&message.mediaTitle).map(message=>this.normalizedRoomMediaTitle(message.mediaTitle!)).filter(Boolean));}
  private normalizedRoomMediaTitle(title:string):string{return title.toLowerCase().replace(/\[[^\]]*\]|\([^)]*\)/g,' ').replace(/\b(official|video|audio|lyrics?|lyrical|hd|4k|8k|full song)\b/g,' ').replace(/[^a-z0-9]+/g,' ').replace(/\s+/g,' ').trim();}
  private removeQueuedSuggestions(queue:WatchQueue):void{const unavailable=this.playedRoomMediaIds();for(const item of queue.items)if(item.provider==='YOUTUBE')unavailable.add(item.mediaId);const current=this.youtubeState()?.mediaId;if(current)unavailable.add(current);const playedTitles=this.playedRoomMediaTitles();this.youtubeSuggestions.update(items=>items.filter(item=>!unavailable.has(item.videoId)&&!playedTitles.has(this.normalizedRoomMediaTitle(item.title))));}
  myQueueItems():WatchQueueItem[]{const id=this.profile()?.id;return (this.watchQueue()?.items.filter(item=>item.addedBy===id&&item.personalQueueItem!==false)??[]).sort((a,b)=>a.personalPosition-b.personalPosition);}
  isSpeaking(userId:string):boolean{return this.media.activeSpeakerIds().includes(userId);}
  hasMicrophone(userId:string):boolean{return this.media.microphoneParticipantIds().includes(userId);}
  closeRoom():void{this.participantsDrawerOpen.set(false);this.showHome();}
  isRoomHost(userId:string):boolean{return this.liveParticipants().some(person=>person.userId===userId&&person.role==='HOST');}
  featuredVoiceParticipant():LiveParticipant|null{const speakers=this.media.activeSpeakerIds();return speakers.map(id=>this.liveParticipants().find(person=>person.userId===id)).find((person):person is LiveParticipant=>!!person)??null;}
  voiceParticipants():LiveParticipant[]{
    const microphones=new Set(this.media.microphoneParticipantIds()),speakers=new Set(this.media.activeSpeakerIds());
    return this.liveParticipants().filter(person=>microphones.has(person.userId)).sort((a,b)=>Number(speakers.has(b.userId))-Number(speakers.has(a.userId))||(a.role==='HOST'?-1:b.role==='HOST'?1:0));
  }
  visibleVoiceParticipants():LiveParticipant[]{return this.voiceParticipants().slice(0,6);}
  voiceParticipantOverflow():number{return Math.max(0,this.voiceParticipants().length-6);}
  orderedLiveParticipants():LiveParticipant[]{const active=new Set(this.media.activeSpeakerIds());return [...this.liveParticipants()].sort((a,b)=>Number(active.has(b.userId))-Number(active.has(a.userId))||(a.role==='HOST'?-1:b.role==='HOST'?1:0)||a.displayName.localeCompare(b.displayName));}
  roomQueueItems():WatchQueueItem[]{const unique=new Map<string,WatchQueueItem>();for(const item of this.watchQueue()?.items??[]){const key=`${item.provider}:${item.mediaId}`;if(!unique.has(key))unique.set(key,item);}return [...unique.values()].map(item=>item.provider==='YOUTUBE'?{...item,thumbnailUrl:this.youtubePreview(item.mediaId)}:item).sort((a,b)=>b.voteCount-a.voteCount||new Date(a.createdAt).getTime()-new Date(b.createdAt).getTime());}
  nextQueueItem():WatchQueueItem|null{const queue=this.watchQueue();return queue?.items.find(item=>item.id===queue.nextItemId)??queue?.items[0]??null;}
  showUpNext():void{this.companionCollapsed.set(false);this.showVideoBrowser.set(false);this.watchSideTab.set('queue');}
  beginVideoHold():void{this.cancelVideoHold();this.showVideoShelf.update(value=>!value);}
  cancelVideoHold():void{if(this.videoHoldTimer){clearTimeout(this.videoHoldTimer);this.videoHoldTimer=undefined;}}
  rankedShelfItems():WatchQueueItem[]{
    const queued=this.roomQueueItems();
    const current=this.youtubeState();if(!current)return queued;
    return [{id:'__playing__',provider:current.provider,mediaId:current.mediaId,title:current.title||'Current video',thumbnailUrl:current.provider==='YOUTUBE'?this.youtubePreview(current.mediaId):undefined,addedBy:'',addedByName:'NOW PLAYING',personalPosition:-1,personalQueueItem:false,voteCount:0,votedByMe:false,createdAt:current.updatedAt},...queued];
  }
  private youtubePreview(mediaId:string):string{return `https://i.ytimg.com/an_webp/${encodeURIComponent(mediaId)}/mqdefault_6s.webp`;}
  roomVideoThumbnail(message:RoomChatMessage):string{
    if(message.type!=='VIDEO'||!message.mediaId)return '';
    return message.mediaProvider==='YOUTUBE'
      ? `https://i.ytimg.com/vi/${encodeURIComponent(message.mediaId)}/mqdefault.jpg`
      : '';
  }
  isCurrentRoomVideo(message:RoomChatMessage):boolean{return message.type==='VIDEO'&&!!message.mediaId&&message.mediaId===this.youtubeState()?.mediaId;}
  isRoomVideoLiked(message:RoomChatMessage):boolean{return !!message.mediaId&&this.roomLikedMediaIds().has(message.mediaId);}
  async openRoomVideoMessage(message:RoomChatMessage):Promise<void>{
    if(!this.selectedRoom()||!message.mediaId)return;
    const provider=(message.mediaProvider??'YOUTUBE').toUpperCase();
    this.showVideoShelf.set(false);this.watchPicker.set(null);this.roomExperience.set('youtube');this.showVideoBrowser.set(true);
    if(provider==='YOUTUBE'){
      this.youtubeUrl=`https://www.youtube.com/watch?v=${encodeURIComponent(message.mediaId)}`;
      this.youtubeQuery=message.mediaTitle??'';
      if(this.youtubeQuery.trim().length>=2)await this.searchYoutube(this.youtubeQuery);
      this.youtubeMessage.set('Opened this video in the YouTube provider.');
    }else{
      this.youtubeUrl=message.mediaId;
      this.webSearchQuery=message.mediaTitle??'';
      this.youtubeMessage.set(`Opened this video in ${this.providerBadge(provider)}.`);
    }
  }
  async toggleRoomVideoLike(message:RoomChatMessage,event:Event):Promise<void>{event.stopPropagation();if(!message.mediaId)return;const enabled=!this.roomLikedMediaIds().has(message.mediaId);await this.api.setMediaLike(message.mediaId,enabled);this.roomLikedMediaIds.update(items=>{const next=new Set(items);if(enabled)next.add(message.mediaId!);else next.delete(message.mediaId!);return next;});}
  async skipFromRoomVideo(message:RoomChatMessage,event:Event):Promise<void>{event.stopPropagation();if(this.isCurrentRoomVideo(message))await this.voteSkip();}
  private async refreshRoomVideoLikes():Promise<void>{try{const library=await this.api.mediaLibrary();this.roomLikedMediaIds.set(new Set(library.likes.map(item=>item.mediaId)));}catch{/* Like buttons remain available and retry on interaction. */}}
  roomPreview(room:PublicRoom):string{if((room.mediaProvider??'YOUTUBE')==='YOUTUBE'&&room.mediaId)return `url("${this.youtubePreview(room.mediaId)}")`;if(room.thumbnailUrl)return `url("${room.thumbnailUrl.replaceAll('"','%22')}")`;return '';}
  shelfPreview(provider:string,mediaId:string,thumbnailUrl?:string):string{if(provider==='YOUTUBE')return `https://i.ytimg.com/an_webp/${encodeURIComponent(mediaId)}/mqdefault_6s.webp`;return thumbnailUrl??'';}
  shelfProvider(provider:string):string{return provider==='YOUTUBE'?'▶ YT':provider.startsWith('DIRECT')?'◉ WEB':provider==='CRUNCHYROLL'?'▣ CR':provider;}
  providerBadge(provider:string|undefined,title='',mediaId=''):string{
    const normalized=(provider??'WEB').toUpperCase();
    const label=normalized==='YOUTUBE'?'YouTube':normalized==='WEB'||normalized.startsWith('DIRECT_')?'Web':normalized==='GOOGLE_DRIVE'||normalized==='DRIVE'?'Drive':normalized==='CRUNCHYROLL'?'Crunchyroll':normalized==='TWITCH'?'Twitch':normalized==='PHOTOS'?'Photos':normalized.toLowerCase().replaceAll('_',' ').replace(/\b\w/g,value=>value.toUpperCase());
    const sensitive=/nsfw|adult|porn|xxx|xhamster|xvideos|pornhub|femdom|nude|sex/i.test(`${title} ${mediaId}`);
    return sensitive?`NSFW · ${label}`:label;
  }
  roomProviderBadge(room:PublicRoom):string{return this.providerBadge(room.mediaProvider,room.mediaTitle??room.name,room.mediaId??'');}
  previewFallback(event:Event,fallback?:string):void{const image=event.target as HTMLImageElement;if(fallback&&image.src!==fallback)image.src=fallback;else image.style.visibility='hidden';}
  openPlaybackSettings():void{this.showPlaybackSettings.update(value=>!value);if(!this.showPlaybackSettings()||!this.youtubePlayer)return;this.youtubePlayer.loadModule?.('captions');setTimeout(()=>{const qualities=this.youtubePlayer?.getAvailableQualityLevels?.()??[];this.qualityLevels.set(qualities);const tracks=this.youtubePlayer?.getOption?.('captions','tracklist');this.captionTracks.set(Array.isArray(tracks)?tracks:[]);this.applyCaptionPreference();},250);}
  setVideoQuality(quality:string):void{this.selectedQuality.set(quality);if(quality!=='auto')this.youtubePlayer?.setPlaybackQuality?.(quality);}
  setCaptionLanguage(languageCode:string):void{this.selectedCaption.set(languageCode);this.applyCaptionPreference();}
  private applyCaptionPreference():void{const player=this.youtubePlayer;if(!player)return;const languageCode=this.selectedCaption();if(languageCode==='off'){player.unloadModule?.('captions');return;}player.loadModule?.('captions');player.setOption?.('captions','track',{languageCode});}
  async addRecentFriend(person:RecentRoomPerson):Promise<void>{try{await this.api.sendFriendRequest(person.userId);this.recentRoomPeople.update(items=>items.map(item=>item.userId===person.userId?{...item,friend:true}:item));}catch{this.error.set('A friend request already exists for this user.');}}
  async selectRoomQueueItem(item:WatchQueueItem):Promise<void>{if(item.id==='__playing__'){this.showVideoShelf.set(false);return;}if(this.watchQueue()?.mode==='VOTE')await this.voteQueue(item);}
  async selectRoomSuggestion(video:YoutubeResult):Promise<void>{await this.queueYoutube(video,true);}
  async voteQueue(item:WatchQueueItem):Promise<void>{const room=this.selectedRoom();if(item.id==='__playing__'){this.showVideoShelf.set(false);return;}if(!room)return;await this.api.voteWatchQueue(room.id,item.id);await this.refreshWatchQueue();}
  async voteSkip():Promise<void>{const room=this.selectedRoom();if(!room||!this.youtubeState())return;try{const result=await this.api.voteToSkip(room.id);if(result.skipped){this.youtubeMessage.set(result.state?.playing?'Skip passed. Setting up the next video…':'Skip passed. Add a video to continue.');if(result.state)this.youtubeState.set(result.state);await this.refreshWatchQueue();await this.syncYoutube(true);}else{this.youtubeMessage.set(`Skip vote added · ${result.votes}/${result.required}`);await this.refreshWatchQueue();}}catch(e){this.youtubeMessage.set(e instanceof HttpErrorResponse&&e.status===409?'Add a video to the room queue before skipping.':'Could not submit the skip vote.');}}
  async movePersonalQueue(item:WatchQueueItem,direction:-1|1):Promise<void>{const room=this.selectedRoom(),items=this.myQueueItems(),index=items.findIndex(x=>x.id===item.id),target=index+direction;if(!room||index<0||target<0||target>=items.length)return;[items[index],items[target]]=[items[target],items[index]];this.watchQueue.update(queue=>queue?{...queue,items:queue.items.map(x=>{const position=items.findIndex(i=>i.id===x.id);return position<0?x:{...x,personalPosition:position};})}:queue);try{await this.api.reorderWatchQueue(room.id,items.map(x=>x.id));await this.refreshWatchQueue();}catch{this.youtubeMessage.set('Could not reorder your queue.');await this.refreshWatchQueue();}}
  async removeQueue(item:WatchQueueItem):Promise<void>{const room=this.selectedRoom();if(!room)return;await this.api.removeWatchQueue(room.id,item.id);await this.refreshWatchQueue();}
  async startQueueItem(item?:WatchQueueItem):Promise<void>{if(item?.id==='__playing__'){this.showVideoShelf.set(false);return;}const room=this.selectedRoom();if(!room||!this.canControlWatch())return;try{this.youtubeMessage.set('Starting video…');const state=await this.api.playNext(room.id,item?.id);this.handledEndedMediaKey='';this.youtubeState.set(state);this.showVideoShelf.set(false);await this.refreshWatchQueue();await this.syncYoutube(true);}catch(e){this.youtubeMessage.set(e instanceof HttpErrorResponse&&e.status===409?'That provider is queued as a placeholder and is not integrated yet.':'Could not start the next video.');}}
  async changeQueueMode(mode:string):Promise<void>{const room=this.selectedRoom();if(!room)return;await this.api.updateWatchSettings(room.id,mode,10);await this.refreshWatchQueue();}
  async toggleVideoPermission(member:RoomMember):Promise<void>{const room=this.selectedRoom();if(!room)return;await this.api.setVideoPermission(room.id,member.userId,!member.canAddVideos);this.roomMembers.set(await this.api.roomMembers(room.id));await this.refreshWatchQueue();}
  async addPlaceholder(provider:'NETFLIX'|'CRUNCHYROLL'|'TWITCH'):Promise<void>{const room=this.selectedRoom(),title=this.youtubeQuery.trim();if(!room||!title||!this.watchQueue()?.canAdd){this.youtubeMessage.set('Enter a title in the search box first.');return;}await this.api.addToWatchQueue(room.id,{provider,mediaId:title,title});this.youtubeMessage.set(`${provider} title added as an upcoming placeholder.`);await this.refreshWatchQueue();
  }
  private async syncYoutube(force=false):Promise<void> {
    const room=this.selectedRoom();if(!room)return;
    try { const state=await this.api.watchState(room.id);if(!state)return;void this.rememberMedia(state);if(this.optimisticPlaybackState!==null&&this.canControlWatch())return;this.youtubeState.set(state);if(state.provider==='WEB'){this.clearCustomPlayerForWeb();this.youtubeUrl=state.sourceUrl||state.mediaId;this.youtubeMessage.set('Open this Web page in the in-app browser and choose its playable video.');this.showVideoBrowser.set(true);return;}if(state.provider!=='YOUTUBE'){await this.ensureDirectPlayer(state,force);return;}this.destroyDirectPlayer();if(this.suggestionsForId!==state.mediaId){this.suggestionsForId=state.mediaId;void this.loadYoutubeSuggestions(state);}await this.ensureYoutubePlayer(state.mediaId,force);
      const remaining=state.transitionUntil?Math.max(0,Math.ceil((new Date(state.transitionUntil).getTime()-Date.now())/1000)):0;this.transitionCountdown.set(remaining);if(remaining>0){this.applyingYoutubeState=true;this.youtubePlayer?.pauseVideo();setTimeout(()=>this.applyingYoutubeState=false,250);return;}
      if(!this.youtubePlayer)return;
      if(this.canControlWatch()){
        if(state.playing&&this.youtubePlayer.getPlayerState()!==1){this.applyingYoutubeState=true;this.youtubePlayer.seekTo(Math.max(0,state.positionSeconds),true);this.youtubePlayer.playVideo();setTimeout(()=>{this.applyingYoutubeState=false;if(this.youtubePlayer?.getPlayerState()!==1)this.playbackNeedsGesture.set(true);else this.playbackNeedsGesture.set(false);},700);}
        else if(state.playing)this.playbackNeedsGesture.set(false);
        return;
      }
      const target=Math.max(0,state.positionSeconds),current=this.youtubePlayer.getCurrentTime(),playerState=this.youtubePlayer.getPlayerState();this.applyingYoutubeState=true;
      if(!state.playing&&this.youtubePlayer.getPlayerState()===0)this.showVideoBrowser.set(true);
      // Avoid re-seeking for ordinary network jitter. Small repeated seeks make
      // the YouTube iframe discard its buffer and look frozen to viewers.
      const drift=Math.abs(current-target),now=Date.now();
      if((force||drift>3.5)&&(force||now-this.lastYoutubeHardSyncAt>5000)){
        this.youtubePlayer.seekTo(target,true);this.lastYoutubeHardSyncAt=now;
      }
      if(state.playing){
        this.youtubePlayer.playVideo();
        if(playerState!==1)setTimeout(()=>{if(this.youtubePlayer?.getPlayerState()!==1)this.playbackNeedsGesture.set(true);},700);
        else this.playbackNeedsGesture.set(false);
      }else{this.youtubePlayer.pauseVideo();this.playbackNeedsGesture.set(false);}
      if(Math.abs(this.youtubePlayer.getPlaybackRate()-state.playbackRate)>.01)this.youtubePlayer.setPlaybackRate(state.playbackRate);setTimeout(()=>this.applyingYoutubeState=false,350);
    } catch { /* keep current player during a transient sync failure */ }
  }
  private async ensureDirectPlayer(state:WatchState,force=false):Promise<void>{
    const surface=this.youtubeSurface?.nativeElement;if(!surface){setTimeout(()=>void this.ensureDirectPlayer(state,force),50);return;}
    if(!state.sourceUrl)return;
    if(!this.directPlayer){this.youtubePlayer?.destroy();this.youtubePlayer=undefined;surface.replaceChildren();this.directPlayer=document.createElement('video');this.directPlayer.className='direct-media-surface';this.directPlayer.playsInline=true;this.directPlayer.preload='auto';this.directPlayer.onended=()=>void this.onDirectMediaEnded();this.directPlayer.onloadstart=()=>this.youtubeLaunchOverlay.set(true);this.directPlayer.onwaiting=()=>this.youtubeLaunchOverlay.set(true);this.directPlayer.onstalled=()=>this.youtubeLaunchOverlay.set(true);this.directPlayer.onloadeddata=()=>this.youtubeLaunchOverlay.set(false);this.directPlayer.oncanplay=()=>this.youtubeLaunchOverlay.set(false);this.directPlayer.onplaying=()=>this.youtubeLaunchOverlay.set(false);surface.appendChild(this.directPlayer);}
    const player=this.directPlayer;if(force||player.dataset['mediaId']!==state.mediaId){this.youtubeLaunchOverlay.set(true);this.hls?.destroy();this.hls=undefined;if(state.provider==='DIRECT_HLS'&&!player.canPlayType('application/vnd.apple.mpegurl')){const {default:Hls}=await import('hls.js');if(Hls.isSupported()){const hls=new Hls();hls.loadSource(state.sourceUrl);hls.attachMedia(player);this.hls=hls;}else throw new Error('HLS is not supported by this browser.');}else{player.src=state.sourceUrl;player.load();}player.dataset['mediaId']=state.mediaId;}
    const target=Math.max(0,state.positionSeconds);if(force||Math.abs(player.currentTime-target)>2)player.currentTime=target;
    player.playbackRate=state.playbackRate||1;player.volume=this.playerVolume()/100;player.muted=this.playerMuted();
    if(state.playing){try{await player.play();this.playbackNeedsGesture.set(false);}catch{this.playbackNeedsGesture.set(true);}}else player.pause();
    this.playerDuration.set(Number.isFinite(player.duration)?player.duration:(state.durationSeconds??0));this.playerPosition.set(player.currentTime||target);if(player.readyState>=3)this.youtubeLaunchOverlay.set(false);
  }
  private async onDirectMediaEnded():Promise<void>{await this.advanceAfterPlaybackEnded();}
  private clearCustomPlayerForWeb():void{
    this.destroyDirectPlayer();
    this.youtubePlayer?.destroy();this.youtubePlayer=undefined;this.youtubePlayerId='';
    this.youtubeSurface?.nativeElement.replaceChildren();
    this.youtubeLaunchOverlay.set(false);
  }
  private destroyDirectPlayer():void{this.hls?.destroy();this.hls=undefined;if(!this.directPlayer)return;this.directPlayer.pause();this.directPlayer.removeAttribute('src');this.directPlayer.remove();this.directPlayer=undefined;}
  async resumeSynchronizedPlayback():Promise<void>{
    const room=this.selectedRoom(),player=this.youtubePlayer;if(!room)return;if(this.directPlayer){try{await this.directPlayer.play();this.playbackNeedsGesture.set(false);}catch{}return;}if(!player)return;
    try{const state=await this.api.watchState(room.id);if(!state)return;player.seekTo(Math.max(0,state.positionSeconds),true);player.setVolume(this.playerVolume());player.unMute();player.playVideo();this.playerMuted.set(false);this.playbackNeedsGesture.set(false);this.lastYoutubeHardSyncAt=Date.now();}
    catch{this.youtubeMessage.set('Could not resume synchronized playback.');}
  }
  private async ensureYoutubePlayer(videoId:string,force=false):Promise<void> {
    const surface=this.youtubeSurface?.nativeElement;if(!surface){setTimeout(()=>void this.ensureYoutubePlayer(videoId,force),50);return;}
    if(this.youtubePlayer&&!force&&this.youtubePlayerId===videoId)return;
    this.youtubeLaunchOverlay.set(true);
    this.youtubePlayer?.destroy();this.youtubePlayerId=videoId;
    this.youtubePlayer=await this.youtube.create(surface,videoId,state=>void this.onYoutubePlayerState(state),this.youtubeState()?.playing??false);
    this.youtubePlayer.setVolume(this.playerVolume());this.youtubePlayer.unMute();this.playerMuted.set(false);
    this.applyCaptionPreference();
  }
  private async loadYoutubeSuggestions(state:WatchState):Promise<void>{try{const response=await this.api.searchYoutube(state.title||state.mediaId);const unavailable=this.playedRoomMediaIds();for(const item of this.watchQueue()?.items??[])unavailable.add(item.mediaId);unavailable.add(state.mediaId);const playedTitles=this.playedRoomMediaTitles();this.youtubeSuggestions.set(response.results.filter(video=>!unavailable.has(video.videoId)&&!playedTitles.has(this.normalizedRoomMediaTitle(video.title))).slice(0,8).map(video=>({...video,thumbnailUrl:this.youtubePreview(video.videoId)})));}catch{this.youtubeSuggestions.set([]);}}
  private async onYoutubePlayerState(playerState:number):Promise<void> {
    if(playerState===1)this.youtubeLaunchOverlay.set(false);
    if(this.optimisticPlaybackState!==null&&playerState===(this.optimisticPlaybackState?1:2)){
      this.clearOptimisticPlaybackState();
      return;
    }
    if(this.applyingYoutubeState||!this.canControlWatch()||![0,1,2].includes(playerState))return;
    if(playerState===0){
      await this.advanceAfterPlaybackEnded();
      return;
    }
    if(playerState===2)await this.publishYoutubePosition(false);else if(playerState===1&&!this.youtubeState()?.playing)await this.publishYoutubePosition(true);
  }
  private async advanceAfterPlaybackEnded():Promise<void>{const state=this.youtubeState();if(!state||!this.canControlWatch())return;const mediaKey=`${state.provider}:${state.mediaId}`;if(this.handledEndedMediaKey===mediaKey)return;this.handledEndedMediaKey=mediaKey;await this.refreshWatchQueue();if(this.watchQueue()?.items.length){this.youtubeMessage.set('Starting the highest-voted video…');await this.startQueueItem();return;}this.showVideoShelf.set(true);this.showPlaybackSettings.set(false);if(this.watchSync.publish('STOP',state,{positionSeconds:0}))this.youtubeState.set({...state,playing:false,positionSeconds:0});else await this.publishYoutubePosition(false);this.youtubeMessage.set('Video ended. Search for what to play next.');}
  async toggleRoomPlayback():Promise<void>{
    const player=this.youtubePlayer,direct=this.directPlayer;if((!player&&!direct)||!this.canControlWatch())return;
    const current=this.optimisticPlaybackState??(direct?!direct.paused:player!.getPlayerState()===1),playing=!current;
    const command=++this.playbackCommandSequence;
    this.optimisticPlaybackState=playing;
    this.youtubeState.update(state=>state?{...state,playing}:state);
    if(this.playbackCommandTimer)clearTimeout(this.playbackCommandTimer);
    this.playbackCommandTimer=setTimeout(()=>this.clearOptimisticPlaybackState(command),1800);
    if(direct){if(playing)void direct.play();else direct.pause();}else if(playing)player!.playVideo();else player!.pauseVideo();
    const position=direct?.currentTime??player!.getCurrentTime();const state=this.youtubeState();if(state&&this.watchSync.publish(playing?'PLAY':'PAUSE',state,{positionSeconds:position}))return;
    await this.publishYoutubePosition(playing,command);
  }
  private clearOptimisticPlaybackState(command?:number):void{
    if(command!==undefined&&command!==this.playbackCommandSequence)return;
    if(this.playbackCommandTimer)clearTimeout(this.playbackCommandTimer);
    this.playbackCommandTimer=undefined;this.optimisticPlaybackState=null;
  }
  async seekRoom(delta:number):Promise<void>{const player=this.youtubePlayer,direct=this.directPlayer,state=this.youtubeState();if((!player&&!direct)||!state||!this.canControlWatch())return;const position=Math.max(0,(direct?.currentTime??player!.getCurrentTime())+delta);if(direct)direct.currentTime=position;else player!.seekTo(position,true);if(!this.watchSync.publish('SEEK',state,{positionSeconds:position}))await this.publishYoutubePosition(direct?!direct.paused:player!.getPlayerState()===1);}
  async seekRoomTo(value:number|string):Promise<void>{const player=this.youtubePlayer,direct=this.directPlayer,state=this.youtubeState();if((!player&&!direct)||!state||!this.canControlWatch())return;const position=Math.max(0,Number(value));if(direct)direct.currentTime=position;else player!.seekTo(position,true);this.playerPosition.set(position);if(!this.watchSync.publish('SEEK',state,{positionSeconds:position}))await this.publishYoutubePosition(direct?!direct.paused:player!.getPlayerState()===1);}
  toggleLocalMute():void{const direct=this.directPlayer;if(direct){direct.muted=!direct.muted;this.playerMuted.set(direct.muted);return;}const player=this.youtubePlayer;if(!player)return;if(player.isMuted()){player.unMute();this.playerMuted.set(false);}else{player.mute();this.playerMuted.set(true);}}
  changeLocalVolume(value:number|string):void{const volume=Math.max(0,Math.min(100,Number(value)));if(this.directPlayer){this.directPlayer.volume=volume/100;this.directPlayer.muted=volume===0;this.playerVolume.set(volume);this.playerMuted.set(volume===0);return;}const player=this.youtubePlayer;if(!player)return;player.setVolume(volume);if(volume>0&&player.isMuted())player.unMute();this.playerVolume.set(volume);this.playerMuted.set(volume===0);}
  async toggleYoutubeFullscreen():Promise<void>{const surface=this.youtubeSurface?.nativeElement.closest('.youtube-watch');if(!surface)return;if(document.fullscreenElement)await document.exitFullscreen();else await surface.requestFullscreen();}
  formatPlayerTime(seconds:number):string{const safe=Math.max(0,Math.floor(seconds||0)),minutes=Math.floor(safe/60),remaining=safe%60;return `${minutes}:${remaining.toString().padStart(2,'0')}`;}
  private refreshPlayerTelemetry():void{if(this.directPlayer){this.playerPosition.set(this.directPlayer.currentTime||0);this.playerDuration.set(Number.isFinite(this.directPlayer.duration)?this.directPlayer.duration:0);this.playerMuted.set(this.directPlayer.muted);this.playerVolume.set(Math.round(this.directPlayer.volume*100));return;}const player=this.youtubePlayer;if(!player)return;try{this.playerPosition.set(player.getCurrentTime()||0);this.playerDuration.set(player.getDuration()||0);this.playerMuted.set(player.isMuted());this.playerVolume.set(player.getVolume());}catch{/* player may be switching videos */}}
  private async heartbeatRoomWatch():Promise<void>{const room=this.selectedRoom();if(!room||!this.youtubeState())return;try{this.youtubeState.set(await this.api.heartbeatWatch(room.id));}catch{/* next heartbeat retries */}}
  private async enterRoomSession():Promise<void>{const room=this.selectedRoom();if(!room)return;if(this.roomSessionActive()){this.rememberActiveRoom();return;}try{await this.api.liveJoin(room.id);this.roomSessionActive.set(true);this.rememberActiveRoom();await this.refreshLiveRoom();void this.refreshRoomVideoLikes();}catch{this.roomSessionActive.set(false);}}
  private async ensureRoomPresence():Promise<void>{await this.enterRoomSession();}
  private async publishYoutubePosition(playing?:boolean,command?:number):Promise<void> {
    const room=this.selectedRoom(),state=this.youtubeState(),player=this.youtubePlayer;if(!room||!state||!player||!this.canControlWatch())return;
    if(this.optimisticPlaybackState!==null&&command===undefined)return;
    if(state.transitionUntil&&new Date(state.transitionUntil).getTime()>Date.now())return;
    if(state.transitionUntil&&player.getPlayerState()!==1)return;
    try {
      const updated=await this.api.updateWatch(room.id,{provider:'YOUTUBE',mediaId:state.mediaId,title:state.title,playing:playing??player.getPlayerState()===1,positionSeconds:player.getCurrentTime(),playbackRate:player.getPlaybackRate()||1});
      if(command===undefined||command===this.playbackCommandSequence)this.youtubeState.set(updated);
    } catch {
      this.youtubeMessage.set('Could not synchronize playback.');
      if(command!==undefined&&command===this.playbackCommandSequence){this.youtubeState.update(current=>current?{...current,playing:!playing}:current);this.clearOptimisticPlaybackState(command);}
    }
  }
  private youtubeId(value:string):string|null { const v=value.trim();if(/^[\w-]{11}$/.test(v))return v;try{const u=new URL(v);if(u.hostname==='youtu.be')return u.pathname.slice(1).split('/')[0]||null;if(u.hostname.includes('youtube.com'))return u.searchParams.get('v')??u.pathname.match(/\/(?:embed|shorts)\/([\w-]{11})/)?.[1]??null;}catch{}return null; }
  private directMedia(value:string):{provider:'DIRECT_MP4'|'DIRECT_HLS';url:string;title:string}|null{try{const url=new URL(value.trim());if(url.protocol!=='https:')return null;const path=url.pathname.toLowerCase();if(path.endsWith('.m3u8'))return{provider:'DIRECT_HLS',url:url.toString(),title:path.split('/').pop()||'HLS stream'};if(path.endsWith('.mp4'))return{provider:'DIRECT_MP4',url:url.toString(),title:path.split('/').pop()||'Video'};}catch{}return null;}
  leaveMedia(): void { this.media.disconnect(); }
  private rememberActiveRoom():void{const room=this.selectedRoom();if(!room||!this.roomSessionActive())return;try{sessionStorage.setItem(this.activeRoomStorageKey,JSON.stringify({roomId:room.id,experience:this.roomExperience()}));}catch{/* storage may be unavailable in privacy-restricted browsers */}}
  private forgetActiveRoom():void{try{sessionStorage.removeItem(this.activeRoomStorageKey);}catch{/* storage may be unavailable */}}
  private async restoreActiveRoomSession():Promise<void>{
    let saved:{roomId?:string;experience?:'sharing'|'youtube'}|null=null;
    try{saved=JSON.parse(sessionStorage.getItem(this.activeRoomStorageKey)??'null');}catch{this.forgetActiveRoom();}
    if(!saved?.roomId)return;
    const room=this.rooms().find(item=>item.id===saved?.roomId);if(!room){this.forgetActiveRoom();return;}
    this.selectedRoom.set(room);this.mainView.set('room');this.showPublicHome.set(false);this.roomExperience.set(saved.experience==='youtube'?'youtube':'sharing');
    await this.enterRoomSession();
    if(saved.experience==='youtube'){
      try{const state=await this.api.watchState(room.id);if(state){this.youtubeState.set(state);this.showVideoBrowser.set(false);await this.connectWatchEvents();await this.refreshWatchQueue();await this.syncYoutube(true);}else{this.roomExperience.set('sharing');this.rememberActiveRoom();}}catch{/* normal refresh loops will retry */}
    }else await this.discoverActiveWatch();
  }
  async openMediaLibrary(view:'history'|'likes'):Promise<void>{
    this.mediaLibraryView.set(view);this.mediaLibraryLoading.set(true);
    try{this.mediaLibrary.set(await this.api.mediaLibrary());}catch{this.error.set('Could not load your media library.');this.mediaLibraryView.set(null);}finally{this.mediaLibraryLoading.set(false);}
  }
  libraryItems():MediaLibraryItem[]{const library=this.mediaLibrary();return this.mediaLibraryView()==='likes'?(library?.likes??[]):(library?.history??[]);}
  async toggleLibraryLike(item:MediaLibraryItem):Promise<void>{
    const enabled=!item.liked;await this.api.setMediaLike(item.mediaId,enabled);
    const library=this.mediaLibrary();if(!library)return;
    const update=(entry:MediaLibraryItem)=>entry.mediaId===item.mediaId?{...entry,liked:enabled}:entry;
    this.mediaLibrary.set({...library,history:library.history.map(update),gallery:library.gallery.map(update),likes:enabled?[{...item,liked:true},...library.likes.filter(entry=>entry.mediaId!==item.mediaId)]:library.likes.filter(entry=>entry.mediaId!==item.mediaId)});
  }
  async removeLibraryHistory(item:MediaLibraryItem):Promise<void>{await this.api.removeMediaHistory(item.mediaId);const library=this.mediaLibrary();if(library)this.mediaLibrary.set({...library,history:library.history.filter(entry=>entry.mediaId!==item.mediaId)});}
  async playLibraryItem(item:MediaLibraryItem):Promise<void>{
    this.mediaLibraryView.set(null);
    const provider=item.provider==='YOUTUBE'?'YOUTUBE':item.provider==='DIRECT_MP4'?'DIRECT_MP4':item.provider==='DIRECT_HLS'?'DIRECT_HLS':null;
    const room=this.selectedRoom();
    if(room&&this.roomSessionActive()&&this.watchQueue()?.canAdd&&provider){
      try{const queued=await this.api.addToWatchQueue(room.id,{provider,mediaId:item.mediaId,title:item.title,thumbnailUrl:item.thumbnailUrl});await this.refreshWatchQueue();this.roomExperience.set('youtube');if(!this.youtubeState()&&this.canControlWatch())await this.startQueueItem(queued);else this.youtubeMessage.set('Saved video added to Up next.');return;}catch{this.error.set('Could not add that saved video to this room.');return;}
    }
    if(item.provider==='YOUTUBE'){await this.createPartyFromVideo({videoId:item.mediaId,title:item.title,channelTitle:'History',thumbnailUrl:item.thumbnailUrl??''});return;}
    const url=item.sourceUrl||item.mediaId;if(!this.directMedia(url)){this.error.set('This saved provider cannot be played directly yet.');return;}
    this.youtubeUrl=url;this.resolvedWebTitle=item.title;await this.createPartyFromDirect();
  }
  private async rememberMedia(state:WatchState):Promise<void>{
    if(this.recordedMediaIds.has(state.mediaId))return;this.recordedMediaIds.add(state.mediaId);
    try{await this.api.recordMedia({mediaId:state.mediaId,provider:state.provider,title:state.title||'Untitled video',thumbnailUrl:state.thumbnailUrl,sourceUrl:state.sourceUrl});}
    catch{this.recordedMediaIds.delete(state.mediaId);}
  }
  private exitRoomSession():void{const room=this.selectedRoom();this.watchSync.disconnect();this.media.disconnect();if(room&&this.roomSessionActive())void this.api.liveLeave(room.id);this.forgetActiveRoom();this.roomSessionActive.set(false);this.liveParticipants.set([]);this.roomChatMessages.set([]);}
}

