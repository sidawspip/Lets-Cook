import { Injectable, inject, signal } from '@angular/core';
import { HttpErrorResponse } from '@angular/common/http';
import { createLocalScreenTracks, LocalTrack, LocalTrackPublication, Room, RoomEvent, Track } from 'livekit-client';
import { ApiService } from './api.service';

@Injectable({ providedIn: 'root' })
export class MediaService {
  private readonly api = inject(ApiService);
  private room?: Room;
  private surface?: HTMLElement;
  private roomId?: string;
  private screenTrack?: Track;
  private screenElement?: HTMLVideoElement;
  private screenFrameTimeout?: ReturnType<typeof setTimeout>;

  readonly connected = signal(false);
  readonly sharing = signal(false);
  readonly viewingSharedScreen = signal(false);
  readonly canShare = signal(false);
  readonly microphoneEnabled = signal(false);
  readonly microphoneParticipantIds = signal<string[]>([]);
  readonly activeSpeakerIds = signal<string[]>([]);
  readonly locallyMutedIds = signal<string[]>([]);
  readonly speakerEnabled = signal(false);
  readonly busy = signal(false);
  readonly error = signal('');
  readonly screenCaptureSupported = signal(
    typeof navigator !== 'undefined' && !!navigator.mediaDevices?.getDisplayMedia
  );

  async connect(roomId: string, surface: HTMLElement): Promise<void> {
    if (this.room?.state === 'connected' && this.roomId === roomId) {
      this.surface = surface;
      this.restoreScreenTrack();
      return;
    }
    if (this.room) this.disconnect();
    this.busy.set(true);
    this.error.set('');
    this.surface = surface;
    try {
      const credentials = await this.api.mediaToken(roomId);
      this.canShare.set(credentials.canPublish);
      const room = new Room({ adaptiveStream: true, dynacast: true });
      room.on(RoomEvent.TrackSubscribed, (track, publication, participant) => {
        if (publication.source === Track.Source.ScreenShare && track.kind === Track.Kind.Video) {
          this.attachScreen(track);
        } else {
          this.attach(track, participant.identity, publication.source === Track.Source.ScreenShareAudio);
        }
      });
      room.on(RoomEvent.TrackUnsubscribed, (track, publication) => {
        if (publication.source === Track.Source.ScreenShare && track.kind === Track.Kind.Video) {
          if (this.screenTrack === track) this.clearScreenTrack();
          queueMicrotask(() => this.restoreScreenTrack());
        } else track.detach().forEach(element => element.remove());
      });
      room.on(RoomEvent.Reconnected, () => this.restoreScreenTrack());
      room.on(RoomEvent.ParticipantConnected, () => this.restoreScreenTrack());
      room.on(RoomEvent.ParticipantDisconnected, () => queueMicrotask(() => this.restoreScreenTrack()));
      room.on(RoomEvent.TrackPublished, publication => {
        if (publication.source === Track.Source.ScreenShare) queueMicrotask(() => this.restoreScreenTrack());
      });
      room.on(RoomEvent.TrackUnpublished, publication => {
        if (publication.source === Track.Source.ScreenShare) queueMicrotask(() => this.restoreScreenTrack());
      });
      room.on(RoomEvent.LocalTrackUnpublished, publication => {
        if (publication.source === Track.Source.ScreenShare || publication.source === Track.Source.ScreenShareAudio) {
          this.sharing.set(false);
          if (publication.track && this.screenTrack === publication.track) this.clearScreenTrack();
          queueMicrotask(() => this.restoreScreenTrack());
        }
        if (publication.source === Track.Source.Microphone) {
          this.microphoneEnabled.set(false);
          this.setMicrophoneParticipant(room.localParticipant.identity, false);
        }
      });
      room.on(RoomEvent.LocalTrackPublished, publication => {
        if (publication.source === Track.Source.Microphone && !publication.isMuted) {
          this.microphoneEnabled.set(true);
          this.setMicrophoneParticipant(room.localParticipant.identity, true);
        }
      });
      room.on(RoomEvent.ActiveSpeakersChanged, speakers => {
        this.activeSpeakerIds.set(speakers.map(participant => participant.identity).filter(Boolean));
      });
      room.on(RoomEvent.AudioPlaybackStatusChanged, () => {
        if (!room.canPlaybackAudio && this.speakerEnabled()) {
          this.speakerEnabled.set(false);
          this.applySpeakerState();
          this.error.set('Tap the speaker or microphone to enable room audio.');
        }
      });
      room.on(RoomEvent.TrackPublished, (publication, participant) => {
        if (publication.source === Track.Source.Microphone && !publication.isMuted) this.setMicrophoneParticipant(participant.identity, true);
      });
      room.on(RoomEvent.TrackUnpublished, (publication, participant) => {
        if (publication.source === Track.Source.Microphone) this.setMicrophoneParticipant(participant.identity, false);
      });
      room.on(RoomEvent.TrackMuted, (publication, participant) => {
        if (publication.source === Track.Source.Microphone) {
          this.setMicrophoneParticipant(participant.identity, false);
          if (participant.identity === room.localParticipant.identity) this.microphoneEnabled.set(false);
        }
      });
      room.on(RoomEvent.TrackUnmuted, (publication, participant) => {
        if (publication.source === Track.Source.Microphone) {
          this.setMicrophoneParticipant(participant.identity, true);
          if (participant.identity === room.localParticipant.identity) this.microphoneEnabled.set(true);
        }
      });
      room.on(RoomEvent.ParticipantDisconnected, participant => {
        this.activeSpeakerIds.update(ids => ids.filter(id => id !== participant.identity));
        this.setMicrophoneParticipant(participant.identity, false);
      });
      room.on(RoomEvent.Disconnected, () => {
        this.clearScreenTrack();
        this.connected.set(false);
        this.speakerEnabled.set(false);
        this.sharing.set(false);
        this.viewingSharedScreen.set(false);
        this.microphoneEnabled.set(false);
        this.microphoneParticipantIds.set([]);
        this.activeSpeakerIds.set([]);
      });
      this.speakerEnabled.set(false);
      await room.connect(this.publicMediaUrl(credentials.url), credentials.token);
      const microphoneIds=[...room.remoteParticipants.values()]
        .filter(participant=>[...participant.audioTrackPublications.values()].some(publication=>publication.source===Track.Source.Microphone&&!publication.isMuted))
        .map(participant=>participant.identity);
      this.microphoneParticipantIds.set(microphoneIds);
      this.room = room;
      this.roomId = roomId;
      this.connected.set(true);
      this.restoreScreenTrack();
      await this.enableSpeakerAudio();
    } catch (error: unknown) {
      this.speakerEnabled.set(false);
      if (error instanceof HttpErrorResponse && error.status === 403) {
        this.error.set('You are not an active room member yet. Join with the room key or invite, then wait for host approval if required.');
      } else {
        this.error.set(error instanceof Error ? error.message : 'Could not join the media room.');
      }
      throw error;
    } finally {
      this.busy.set(false);
    }
  }

  async toggleMicrophone(roomId: string, surface: HTMLElement): Promise<void> {
    this.busy.set(true); this.error.set('');
    try {
      if (!window.isSecureContext) throw new Error('Microphone access requires HTTPS. Open the Cloudflare HTTPS URL on your phone.');
      if (!navigator.mediaDevices?.getUserMedia) throw new Error('This browser does not provide microphone access. Use current Chrome or Safari and allow microphone permission.');
      if (!this.connected()) await this.connect(roomId,surface);
      if(!this.room) throw new Error('Voice chat is not connected.');
      const enabled=!this.microphoneEnabled();
      await this.room.localParticipant.setMicrophoneEnabled(enabled);
      this.microphoneEnabled.set(enabled);
      this.setMicrophoneParticipant(this.room.localParticipant.identity,enabled);
      if (enabled && (!this.speakerEnabled() || !this.room.canPlaybackAudio)) await this.enableSpeakerAudio();
    } catch(error:unknown) {
      const name=error instanceof DOMException?error.name:'';
      if(name==='NotAllowedError'||name==='PermissionDeniedError')this.error.set('Microphone permission was blocked. Allow microphone access for this site in your phone browser, then tap the mic again.');
      else if(name==='NotFoundError')this.error.set('No microphone was found on this device.');
      else this.error.set(error instanceof Error?error.message:'Microphone access was denied or unavailable.');
      throw error;
    } finally { this.busy.set(false); }
  }

  async toggleSpeaker(roomId: string, surface: HTMLElement): Promise<void> {
    if(!this.connected()) {
      await this.connect(roomId,surface);
      if(this.speakerEnabled())return;
    }
    if(!this.room) return;
    if(this.speakerEnabled()) { this.speakerEnabled.set(false);this.applySpeakerState();return; }
    await this.enableSpeakerAudio();
  }

  private async enableSpeakerAudio():Promise<void>{
    if(!this.room)return;
    try {
      await this.room.startAudio();
      this.speakerEnabled.set(this.room.canPlaybackAudio);
      this.error.set(this.room.canPlaybackAudio?'':'Tap again or allow audio playback in the browser.');
    } catch {
      this.speakerEnabled.set(false);
      this.error.set('Tap again or allow audio playback in the browser.');
    }
    this.applySpeakerState();
  }

  private applySpeakerState():void{
    this.surface?.querySelectorAll<HTMLMediaElement>('audio.room-audio').forEach(element=>
      element.muted=!this.speakerEnabled()||this.locallyMutedIds().includes(element.dataset['participantId']??''));
  }

  async toggleScreenShare(roomId: string, surface: HTMLElement): Promise<void> {
    if (!this.screenCaptureSupported()) {
      this.error.set('This mobile browser does not expose screen capture. You can still join as a viewer.');
      return;
    }
    if (this.connected() && !this.canShare()) {
      // Publish permissions are embedded in the LiveKit token. Reconnect once so
      // a permission that the host just granted is reflected in a fresh token.
      await this.reconnectForUpdatedPermission(roomId, surface);
      if (!this.canShare()) {
        this.error.set('The host has not allowed you to share your screen.');
        return;
      }
    }
    if (!this.connected()) await this.connect(roomId, surface);
    if (!this.room) return;
    this.busy.set(true);
    this.error.set('');
    try {
      if (this.sharing()) {
        await this.room.localParticipant.setScreenShareEnabled(false);
        this.sharing.set(false);
        this.clearScreenTrack();
        this.restoreScreenTrack();
      } else {
        const publication: LocalTrackPublication | undefined = await this.room.localParticipant.setScreenShareEnabled(true, {
          audio: true,
          contentHint: 'detail',
          systemAudio: 'include',
          surfaceSwitching: 'include'
        });
        if (publication?.track) this.attachScreen(publication.track);
        this.sharing.set(true);
      }
    } catch (error: unknown) {
      this.error.set(error instanceof Error ? error.message : 'Screen sharing was cancelled or unavailable.');
    } finally {
      this.busy.set(false);
    }
  }

  async prepareScreenShare(): Promise<LocalTrack[]> {
    if (!this.screenCaptureSupported()) throw new Error('Screen sharing is unavailable in this browser.');
    // Capture must start directly from the click, before any network request
    // consumes the browser's user activation.
    return createLocalScreenTracks({ audio: true });
  }

  async publishPreparedScreenShare(roomId: string, surface: HTMLElement, tracks: LocalTrack[]): Promise<void> {
    try {
      if (!this.connected()) await this.connect(roomId, surface);
      if (!this.room || !this.canShare()) throw new Error('Screen sharing is not permitted in this room.');
      for (const track of tracks) {
        const source = track.kind === Track.Kind.Video ? Track.Source.ScreenShare : Track.Source.ScreenShareAudio;
        const publication = await this.room.localParticipant.publishTrack(track, { source });
        if (source === Track.Source.ScreenShare && publication.track) this.attachScreen(publication.track);
      }
      this.sharing.set(true);
    } catch (error) {
      tracks.forEach(track => track.stop());
      this.error.set(error instanceof Error ? error.message : 'Could not start screen sharing.');
      throw error;
    }
  }

  private async reconnectForUpdatedPermission(roomId: string, surface: HTMLElement): Promise<void> {
    const restoreMicrophone=this.microphoneEnabled();
    this.roomId = undefined;
    this.room?.disconnect();
    this.room = undefined;
    this.connected.set(false);
    this.speakerEnabled.set(false);
    this.sharing.set(false);
    this.viewingSharedScreen.set(false);
    this.canShare.set(false);
    this.microphoneEnabled.set(false);
    this.microphoneParticipantIds.set([]);
    this.activeSpeakerIds.set([]);
    this.surface?.replaceChildren();
    await this.connect(roomId, surface);
    const reconnectedRoom=this.currentRoom();
    if(restoreMicrophone && reconnectedRoom) {
      await reconnectedRoom.localParticipant.setMicrophoneEnabled(true);
      this.microphoneEnabled.set(true);
    }
  }

  disconnect(): void {
    this.clearScreenTrack();
    this.roomId = undefined;
    this.room?.disconnect();
    this.room = undefined;
    this.surface?.replaceChildren();
    this.connected.set(false);
    this.speakerEnabled.set(false);
    this.sharing.set(false);
    this.viewingSharedScreen.set(false);
    this.canShare.set(false);
    this.microphoneEnabled.set(false);
    this.microphoneParticipantIds.set([]);
    this.activeSpeakerIds.set([]);
  }

  toggleLocalListener(identity:string):void {
    this.locallyMutedIds.update(ids=>ids.includes(identity)?ids.filter(id=>id!==identity):[...ids,identity]);
    this.surface?.querySelectorAll<HTMLMediaElement>('audio.room-audio').forEach(element=>{
      if(element.dataset['participantId']===identity)element.muted=!this.speakerEnabled()||this.locallyMutedIds().includes(identity);
    });
  }

  setSharedAudioDucking(speaking:boolean):void {
    this.surface?.querySelectorAll<HTMLMediaElement>('audio.room-audio[data-screen-audio="true"]').forEach(element=>element.volume=speaking?.65:1);
  }

  private attach(track: Track, participantId='', screenAudio=false): void {
    if (!this.surface) return;
    const element = track.attach();
    if(track.kind === Track.Kind.Audio) {
      element.classList.add('room-audio');
      element.style.display='none';
      element.dataset['participantId']=participantId;
      if(screenAudio)element.dataset['screenAudio']='true';
      (element as HTMLMediaElement).muted=!this.speakerEnabled()||this.locallyMutedIds().includes(participantId);
    }
    this.surface.appendChild(element);
  }

  private attachScreen(track: Track): void {
    if (!this.surface || track.kind !== Track.Kind.Video) return;
    if (this.screenTrack === track && this.screenElement?.parentElement === this.surface) {
      if (!this.screenElement.srcObject) track.attach(this.screenElement);
      return;
    }
    this.clearScreenTrack();
    const element = track.attach() as HTMLVideoElement;
    element.classList.add('shared-media');
    element.playsInline = true;
    this.screenTrack = track;
    this.screenElement = element;
    this.surface.querySelectorAll('video.shared-media').forEach(video => video.remove());
    this.surface.appendChild(element);
    const showFrames = () => {
      if (this.screenElement !== element) return;
      this.viewingSharedScreen.set(true);
      if (this.error().startsWith('The shared screen is connected')) this.error.set('');
      if (this.screenFrameTimeout) clearTimeout(this.screenFrameTimeout);
      this.screenFrameTimeout = undefined;
    };
    element.addEventListener('loadeddata', showFrames, { once: true });
    if (element.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) showFrames();
    else this.screenFrameTimeout = setTimeout(() => {
      if (this.screenElement !== element || this.viewingSharedScreen()) return;
      track.attach(element);
      this.error.set('The shared screen is connected but no frames arrived. Ask the sharer to restart and choose Share entire screen.');
    }, 8000);
  }

  private clearScreenTrack(): void {
    if (this.screenFrameTimeout) clearTimeout(this.screenFrameTimeout);
    this.screenFrameTimeout = undefined;
    if (this.screenTrack && this.screenElement) this.screenTrack.detach(this.screenElement);
    this.screenElement?.remove();
    this.screenElement = undefined;
    this.screenTrack = undefined;
    this.viewingSharedScreen.set(false);
  }

  private restoreScreenTrack(): void {
    const track = [...(this.room?.remoteParticipants.values() ?? [])]
      .flatMap(participant => [...participant.videoTrackPublications.values()])
      .find(publication => publication.source === Track.Source.ScreenShare && !publication.isMuted)?.track;
    if (track) this.attachScreen(track);
    else if (!this.sharing()) this.clearScreenTrack();
  }

  private currentRoom(): Room|undefined { return this.room; }

  private setMicrophoneParticipant(identity:string, enabled:boolean):void {
    if(!identity)return;
    this.microphoneParticipantIds.update(ids=>enabled
      ? (ids.includes(identity)?ids:[...ids,identity])
      : ids.filter(id=>id!==identity));
  }

  private publicMediaUrl(configuredUrl: string): string {
    const url = new URL(configuredUrl);
    const localEndpoint = url.hostname === 'localhost' || url.hostname === '127.0.0.1';

    // The Nginx gateway proxies local LiveKit signaling at /livekit for an HTTPS
    // Cloudflare UAT page. A separately configured public LiveKit endpoint must
    // remain untouched so its globally reachable ICE/TURN servers are used.
    if (window.location.protocol === 'https:' && localEndpoint) {
      return `wss://${window.location.host}/livekit`;
    }
    if (localEndpoint && window.location.hostname !== 'localhost') {
      url.hostname = window.location.hostname;
    }
    if (window.location.protocol === 'https:' && url.protocol === 'ws:') {
      url.protocol = 'wss:';
    }
    return url.toString();
  }
}
