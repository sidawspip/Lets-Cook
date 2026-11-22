import { Room, RoomEvent, Track, RemoteTrack, RemoteTrackPublication, RemoteParticipant } from 'livekit-client';
import { api } from './api';

/** Desktop counterpart of Flutter RoomVoiceService. Provider media is separate. */
export class RoomVoiceService {
  private room?: Room;
  private roomId?: string;
  private listening = true;
  private mutedIdentities = new Set<string>();
  private elements = new Map<string, HTMLMediaElement>();
  onChange: () => void = () => {};

  get connected() { return this.room?.state === 'connected'; }
  get microphoneEnabled() { return this.room?.localParticipant.isMicrophoneEnabled === true; }
  get speakerEnabled() { return this.listening; }
  get screenShareEnabled() { return this.room?.localParticipant.isScreenShareEnabled === true; }
  get localIdentity() { return this.room?.localParticipant.identity || ''; }
  get screenTrack() {
    if (!this.room) return null;
    for (const participant of this.room.remoteParticipants.values()) {
      for (const publication of participant.videoTrackPublications.values()) {
        if (publication.source === Track.Source.ScreenShare && !publication.isMuted && publication.track) return publication.track;
      }
    }
    for (const publication of this.room.localParticipant.videoTrackPublications.values()) {
      if (publication.source === Track.Source.ScreenShare && !publication.isMuted && publication.track) return publication.track;
    }
    return null;
  }
  get members() {
    if (!this.room) return [];
    return [this.room.localParticipant, ...this.room.remoteParticipants.values()].map(p => ({
      identity: p.identity, name: p.name || p.identity,
      microphoneOn: p.isMicrophoneEnabled, speaking: p.isSpeaking,
    }));
  }
  private receive = (track: RemoteTrack, publication: RemoteTrackPublication, participant: RemoteParticipant) => {
    if (track.kind !== Track.Kind.Audio) { this.onChange(); return; }
    const element = track.attach();
    element.dataset.participant = participant.identity;
    element.muted = !this.listening || this.mutedIdentities.has(participant.identity);
    document.body.append(element);
    this.elements.set(publication.trackSid, element);
    this.onChange();
  };
  async connect(roomId: string) {
    if (this.connected && this.roomId === roomId) return;
    await this.disconnect();
    const credentials = await api.getMediaToken(roomId);
    const room = new Room({adaptiveStream: true, dynacast: true});
    this.room = room; this.roomId = roomId;
    room.on(RoomEvent.TrackSubscribed, this.receive);
    room.on(RoomEvent.TrackUnsubscribed, (track, publication) => {
      track.detach().forEach(element => element.remove());
      this.elements.delete(publication.trackSid); this.onChange();
    });
    for (const event of [RoomEvent.ParticipantConnected, RoomEvent.ParticipantDisconnected,
      RoomEvent.ActiveSpeakersChanged, RoomEvent.TrackMuted, RoomEvent.TrackUnmuted,
      RoomEvent.LocalTrackPublished, RoomEvent.LocalTrackUnpublished, RoomEvent.Reconnected]) {
      room.on(event, () => this.onChange());
    }
    room.on(RoomEvent.Disconnected, () => this.onChange());
    await room.connect(credentials.url, credentials.token);
    this.onChange();
  }
  async toggleMicrophone(roomId: string) {
    await this.connect(roomId);
    this.setListening(true);
    await this.room!.startAudio();
    await this.room!.localParticipant.setMicrophoneEnabled(!this.room!.localParticipant.isMicrophoneEnabled);
    this.onChange();
  }
  async muteMicrophone() {
    if (this.room?.localParticipant.isMicrophoneEnabled) {
      await this.room.localParticipant.setMicrophoneEnabled(false);
      this.onChange();
    }
  }
  setListening(enabled: boolean) {
    this.listening = enabled;
    for (const element of this.elements.values()) {
      element.muted = !enabled || this.mutedIdentities.has(element.dataset.participant || '');
    }
    this.onChange();
  }
  toggleListeningTo(identity: string) {
    if (this.mutedIdentities.has(identity)) this.mutedIdentities.delete(identity);
    else this.mutedIdentities.add(identity);
    this.setListening(this.listening);
  }
  isListeningTo(identity: string) { return this.listening && !this.mutedIdentities.has(identity); }
  toggleListening() { this.setListening(!this.listening); }
  async shareScreen(roomId: string, permitted: boolean) {
    if (!permitted) throw new Error('Host screen-sharing approval is required.');
    await this.connect(roomId);
    await this.room!.localParticipant.setScreenShareEnabled(!this.room!.localParticipant.isScreenShareEnabled);
    this.onChange();
  }
  async disconnect() {
    const room = this.room; this.room = undefined; this.roomId = undefined;
    await room?.disconnect();
    this.elements.forEach(element => element.remove()); this.elements.clear();
    this.onChange();
  }
}
export const roomVoice = new RoomVoiceService();
