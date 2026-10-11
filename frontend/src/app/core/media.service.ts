import { Injectable, inject, signal } from '@angular/core';
import { HttpErrorResponse } from '@angular/common/http';
import { LocalTrackPublication, Room, RoomEvent, Track } from 'livekit-client';
import { ApiService } from './api.service';

@Injectable({ providedIn: 'root' })
export class MediaService {
  private readonly api = inject(ApiService);
  private room?: Room;
  private surface?: HTMLElement;
  private roomId?: string;

  readonly connected = signal(false);
  readonly sharing = signal(false);
  readonly viewingSharedScreen = signal(false);
  readonly canShare = signal(false);
  readonly microphoneEnabled = signal(false);
  readonly microphoneParticipantIds = signal<string[]>([]);
  readonly activeSpeakerIds = signal<string[]>([]);
  readonly speakerEnabled = signal(false);
  readonly busy = signal(false);
  readonly error = signal('');
  readonly screenCaptureSupported = signal(
    typeof navigator !== 'undefined' && !!navigator.mediaDevices?.getDisplayMedia
  );

  async connect(roomId: string, surface: HTMLElement): Promise<void> {
    if (this.room?.state === 'connected') return;
    this.busy.set(true);
    this.error.set('');
    this.surface = surface;
    try {
      const credentials = await this.api.mediaToken(roomId);
      this.canShare.set(credentials.canPublish);
      const room = new Room({ adaptiveStream: true, dynacast: true });
      room.on(RoomEvent.TrackSubscribed, (track, publication) => {
        if (publication.source === Track.Source.ScreenShare && track.kind === Track.Kind.Video) {
          this.viewingSharedScreen.set(true);
        }
        this.attach(track);
      });
      room.on(RoomEvent.TrackUnsubscribed, (track, publication) => {
        track.detach();
        if (publication.source === Track.Source.ScreenShare && track.kind === Track.Kind.Video) {
          this.viewingSharedScreen.set(false);
          this.surface?.querySelectorAll('.shared-media').forEach(element => element.remove());
        }
      });
      room.on(RoomEvent.LocalTrackUnpublished, publication => {
        if (publication.source === Track.Source.ScreenShare || publication.source === Track.Source.ScreenShareAudio) {
          this.sharing.set(false);
        }
        if (publication.source === Track.Source.Microphone) {
          this.microphoneEnabled.set(false);
          this.setMicrophoneParticipant(room.localParticipant.identity, false);
        }
      });
      room.on(RoomEvent.ActiveSpeakersChanged, speakers => {
        this.activeSpeakerIds.set(speakers.map(participant => participant.identity).filter(Boolean));
      });
      room.on(RoomEvent.TrackPublished, (publication, participant) => {
        if (publication.source === Track.Source.Microphone && !publication.isMuted) this.setMicrophoneParticipant(participant.identity, true);
      });
      room.on(RoomEvent.TrackUnpublished, (publication, participant) => {
        if (publication.source === Track.Source.Microphone) this.setMicrophoneParticipant(participant.identity, false);
      });
      room.on(RoomEvent.TrackMuted, (publication, participant) => {
        if (publication.source === Track.Source.Microphone) this.setMicrophoneParticipant(participant.identity, false);
      });
      room.on(RoomEvent.TrackUnmuted, (publication, participant) => {
        if (publication.source === Track.Source.Microphone) this.setMicrophoneParticipant(participant.identity, true);
      });
      room.on(RoomEvent.ParticipantDisconnected, participant => {
        this.activeSpeakerIds.update(ids => ids.filter(id => id !== participant.identity));
        this.setMicrophoneParticipant(participant.identity, false);
      });
      room.on(RoomEvent.Disconnected, () => {
        this.connected.set(false);
        this.speakerEnabled.set(false);
        this.sharing.set(false);
        this.viewingSharedScreen.set(false);
        this.microphoneEnabled.set(false);
        this.microphoneParticipantIds.set([]);
        this.activeSpeakerIds.set([]);
      });
      this.speakerEnabled.set(true);
      await room.connect(this.publicMediaUrl(credentials.url), credentials.token);
      const microphoneIds=[...room.remoteParticipants.values()]
        .filter(participant=>[...participant.audioTrackPublications.values()].some(publication=>publication.source===Track.Source.Microphone&&!publication.isMuted))
        .map(participant=>participant.identity);
      this.microphoneParticipantIds.set(microphoneIds);
      this.room = room;
      this.roomId = roomId;
      this.connected.set(true);
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
      this.speakerEnabled.set(true);
      try { await this.room?.startAudio(); } catch { this.error.set('Tap again or allow audio playback in the browser.'); }
      return;
    }
    if(!this.room) return;
    const enabled=!this.speakerEnabled();
    this.speakerEnabled.set(enabled);
    this.surface?.querySelectorAll<HTMLMediaElement>('audio.room-audio').forEach(element=>element.muted=!enabled);
    if(enabled) {
      try { await this.room.startAudio(); } catch { this.error.set('Tap again or allow audio playback in the browser.'); }
    }
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
        this.surface?.querySelectorAll('video.shared-media').forEach(element=>element.remove());
      } else {
        const publication: LocalTrackPublication | undefined = await this.room.localParticipant.setScreenShareEnabled(true, {
          audio: true,
          contentHint: 'detail',
          systemAudio: 'include',
          surfaceSwitching: 'include'
        });
        if (publication?.track) this.attach(publication.track);
        this.sharing.set(true);
      }
    } catch (error: unknown) {
      this.error.set(error instanceof Error ? error.message : 'Screen sharing was cancelled or unavailable.');
    } finally {
      this.busy.set(false);
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

  private attach(track: Track): void {
    if (!this.surface) return;
    const element = track.attach();
    if (track.kind === Track.Kind.Video) {
      element.classList.add('shared-media');
      this.surface.querySelectorAll('video').forEach(video => video.remove());
    } else if(track.kind === Track.Kind.Audio) {
      element.classList.add('room-audio');
      element.style.display='none';
      (element as HTMLMediaElement).muted=!this.speakerEnabled();
    }
    this.surface.appendChild(element);
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
