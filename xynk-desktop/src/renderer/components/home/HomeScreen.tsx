import { useEffect, useState } from 'react';
import { Search, Settings, Users, Plus, Globe, Lock, ChevronDown, Play } from 'lucide-react';
import { useWatchPartyStore } from '../../stores/watchPartyStore';
import { useUIStore } from '../../stores/uiStore';
import { MediaPreview } from '../ui/MediaPreview';
import { WaveLoader } from '../ui/WaveLoader';
import { LogoMark } from '../ui/LogoMark';
import { ProfilePrivacySheet } from './ProfilePrivacySheet';
import { FriendsScreen } from './FriendsScreen';
import { MediaDiscoveryScreen } from '../media-discovery/MediaDiscoveryScreen';
import { _time, _looksSensitive, _timeDetailed, _providerLabel, _publicDisplayName, _publicHandle } from '../../lib/formatters';
import { PartyRoom } from '../../types/models';

export function HomeScreen() {
  const {
    rooms,
    visibleRooms,
    initializing,
    busy,
    error,
    profile,
    displayName,
    checkingVideoAccess,
    canControlWatch,
    canViewVideo,
    refreshHomeRooms,
    setHideSensitiveContent,
    setProfilePreference,
    saveProfilePreferences,
    profileVisibility,
    setProfileVisibility,
    logout,
  } = useWatchPartyStore();

  const { isProfileSheetOpen, setProfileSheetOpen, isFriendsOpen, setFriendsOpen, discoveryQuery, setDiscoveryQuery } = useUIStore();
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
    const timer = setInterval(() => refreshHomeRooms(), 10000);
    return () => clearInterval(timer);
  }, [refreshHomeRooms]);

  if (!mounted) return <LaunchScreen />;

  const invited = visibleRooms.filter(r => r.joined);
  const publicRooms = visibleRooms.filter(r => !r.joined);

  return (
    <div className="home-screen h-dvh overflow-hidden app-surface relative flex flex-col">
      <div className="home-shell relative flex-1 flex flex-col">
        {/* Header */}
        <header className="home-header flex items-center justify-between">
          <button onClick={() => setProfileSheetOpen(true)} className="icon-button hover:bg-white/10 transition-colors" aria-label="Open settings">
            <Settings className="w-7 h-7 text-white" />
          </button>

          <div className="flex items-center gap-2.5"><LogoMark size={32} /><h1 className="text-xl font-bold tracking-wide">XYNK</h1></div>

          <button onClick={() => setFriendsOpen(true)} className="icon-button hover:bg-white/10 transition-colors" aria-label="Open friends">
            <Users className="w-7 h-7 text-white" />
          </button>
        </header>

        {/* Search */}
        <div className="home-search-region">
          <form className="relative" onSubmit={event => { event.preventDefault(); const value = new FormData(event.currentTarget).get("videoSearch")?.toString().trim(); if (value) setDiscoveryQuery(value); }}>
            <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-white/70" />
            <input
              type="search" name="videoSearch" aria-label="Search YouTube or paste a video URL"
              placeholder="Search YouTube or paste a video URL"
              className="home-search w-full px-12 py-3 pl-12 bg-white/10 rounded-2xl border border-white/20 focus:border-white/70 focus:ring-2 focus:ring-white/20 text-white placeholder:text-white/70 transition-all"
            />
            <button type="submit" aria-label="Search videos" className="search-action icon-button absolute right-1 top-1/2 -translate-y-1/2"><Play size={18} fill="currentColor" /></button>
          </form>
        </div>

        {/* Rooms List */}
        <main className="home-rooms flex-1 min-h-0 overflow-y-auto">
          <div className="home-room-content">
            {error && <div role="alert" className="mb-3 p-3 rounded-xl border border-red-400/40 bg-red-500/10 text-red-200 text-sm">{error}</div>}
            <ConnectionBanner />
            {!profile && <SensitiveContentToggle />}

            <SectionTitle icon={Lock} label="Invited" count={invited.length} />
            {invited.length > 0 ? <RoomGrid rooms={invited} /> : <p className="room-grid rounded-2xl border border-white/10 p-4 text-sm text-xynk-muted">Rooms you join will appear here.</p>}

            <SectionTitle icon={Globe} label="Public" count={publicRooms.length} />
            {publicRooms.length === 0 ? <EmptyRoomCard /> : <RoomGrid rooms={publicRooms} />}
          </div>
        </main>

        {/* FAB */}
        <FloatingActionButton
          onClick={() => setDiscoveryQuery('')}
          disabled={busy}
        >
          <Plus className="w-8 h-8" />
        </FloatingActionButton>

        {/* Modals */}
        {isProfileSheetOpen && <ProfilePrivacySheet onClose={() => setProfileSheetOpen(false)} />}
        {isFriendsOpen && <FriendsScreen onClose={() => setFriendsOpen(false)} />}
        {discoveryQuery !== null && <MediaDiscoveryScreen query={discoveryQuery} onClose={() => setDiscoveryQuery(null)} onSelect={() => setDiscoveryQuery(null)} />}
      </div>
    </div>
  );
}

function LaunchScreen() {
  return (
    <div className="fixed inset-0 flex items-center justify-center bg-xynk-ink z-50">
      <div className="flex flex-col items-center gap-6">
        <LogoMark size={72} />
        <h1 className="font-black tracking-[0.12em] text-5xl text-white">XYNK</h1>
        <WaveLoader label="Loading your party" size={52} />
      </div>
    </div>
  );
}

function ConnectionBanner() {
  const { fullyConnected, reconnecting } = useWatchPartyStore();
  const [expanded, setExpanded] = useState(false);

  return (
    <button
      onClick={() => setExpanded(!expanded)}
      className="glass-surface w-full p-4 rounded-2xl text-left transition-colors mb-6"
      aria-expanded={expanded}
    >
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className={`connection-dot w-2.5 h-2.5 rounded-full transition-colors ${reconnecting ? 'bg-yellow-400 animate-pulse' : fullyConnected ? 'bg-xynk-mint' : 'bg-white/40'}`} />
          <span className="text-sm font-bold tracking-wide text-white">
            {reconnecting ? 'RECONNECTING' : fullyConnected ? 'STAY CONNECTED' : 'CONNECTING'}
          </span>
        </div>
        <ChevronDown className={`w-5 h-5 text-white/70 transition-transform ${expanded ? 'rotate-180' : ''}`} />
      </div>
      {expanded && (
        <div className="connection-copy mt-3 text-sm text-white/80">
          XYNK keeps your room connected while this window is open. If the connection is interrupted, it automatically rejoins and syncs the video when you return.
        </div>
      )}
    </button>
  );
}

function SensitiveContentToggle() {
  const { hideSensitiveContent, setHideSensitiveContent, savingProfilePreferences } = useWatchPartyStore();
  const saving = savingProfilePreferences.has('hideSensitiveContent');

  return (
    <div className="p-3 rounded-2xl bg-white/5 border border-white/10 mb-4 flex items-center gap-3">
      <div className={`w-9 h-9 rounded-xl flex items-center justify-center ${hideSensitiveContent ? 'bg-red-500/20' : 'bg-green-500/20'}`}>
        {hideSensitiveContent ? (
          <svg className="w-5 h-5 text-red-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-4.47 0-8.26-3.62-9-8.23M1 1l22 22"/></svg>
        ) : (
          <svg className="w-5 h-5 text-green-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
        )}
      </div>
      <div className="flex-1">
        <p className="font-semibold text-white">Hide sensitive content</p>
        <p className="text-xs text-white/60">Hide sensitive rooms and blur them in history</p>
      </div>
      {saving ? (
        <div className="w-9 h-9 rounded-full border-2 border-xynk-lime/50 border-t-xynk-lime animate-spin" />
      ) : (
        <button
          type="button"
          role="switch"
          aria-label="Hide sensitive content"
          aria-checked={hideSensitiveContent}
          onClick={() => setHideSensitiveContent(!hideSensitiveContent)}
          className="icon-button"
        ><span className="settings-switch" aria-hidden="true" /></button>
      )}
    </div>
  );
}

function SectionTitle({ icon: Icon, label, count }: { icon: React.ComponentType<{className?: string}>; label: string; count: number }) {
  return (
    <div className="flex items-center gap-2 mb-3">
      <Icon className="w-5 h-5 text-white" />
      <span className="font-semibold text-white">{label}</span>
      <span className="text-xs text-white/60">{count} {count === 1 ? 'room' : 'rooms'}</span>
    </div>
  );
}

function RoomGrid({ rooms }: { rooms: PartyRoom[] }) {
  return (
    <div className="room-grid grid grid-cols-1 md:grid-cols-2 gap-3">
      {rooms.map(room => <RoomCard key={room.id} room={room} />)}
    </div>
  );
}

function RoomCard({ room }: { room: PartyRoom }) {
  const {openRoom, setError} = useWatchPartyStore();
  const enterRoom = async () => {
    const accessKey = !room.joined && room.accessPolicy?.includes('KEY')
      ? window.prompt(`Enter the key for ${room.name}`) : undefined;
    if (accessKey === null || (room.accessPolicy?.includes('KEY') && !accessKey)) return;
    try { await openRoom(room, accessKey); }
    catch (error) { setError(String(error)); }
  };
  const youtubeId = room.mediaId && /^[\w-]{11}$/.test(room.mediaId) ? room.mediaId : null;
  const provider = room.mediaProvider ?? (youtubeId ? 'YOUTUBE' : 'WEB');
  const sensitive = _looksSensitive(`${room.name} ${room.mediaTitle ?? ''} ${room.mediaId ?? ''}`);
  const duration = room.durationSeconds ?? 0;
  const progress = duration > 0 ? Math.min(1, Math.max(0, room.positionSeconds / duration)) : 0;

  return (
    <article onClick={() => void enterRoom()} role="button" tabIndex={0} onKeyDown={event => {if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); void enterRoom(); }}} className="room-card relative rounded-2xl overflow-hidden cursor-pointer transition-colors hover:border-xynk-lime/50">
      <div className="relative flex h-[108px]">
        <div className="room-thumbnail relative flex-shrink-0">
          <MediaPreview
            mediaId={room.mediaId ?? ''}
            provider={provider}
            thumbnailUrl={room.thumbnailUrl}
            contentLabel={`${room.name} ${room.mediaTitle ?? ''}`}
            sensitive={sensitive}
            className="w-full h-full"
          />
          {sensitive && <div className="absolute inset-0 bg-xynk-ink/60 backdrop-blur-sm" />}
        </div>

        <div className="flex-1 p-3 min-w-0 flex flex-col">
          <h3 className="font-semibold text-sm leading-snug truncate text-white">
            {room.mediaTitle ?? room.name}
          </h3>
          {room.ownerName && (
            <p className="text-xs text-white/80 truncate mt-1">Host: {room.ownerName}</p>
          )}
          <div className="mt-auto flex items-center justify-between">
            <div className="room-viewers text-xs text-white/90" aria-label={`${room.viewerCount} watching`}>
              <Users className="w-4 h-4" aria-hidden="true" /><span>{room.viewerCount}</span>
            </div>
          </div>
        </div>

        {/* Progress bar */}
        <div className="room-progress absolute left-0 right-0 bottom-0 h-1.5 bg-gradient-to-r from-xynk-lime to-xynk-mint origin-left"
          style={{ transform: `scaleX(${progress})` }} />
      </div>
    </article>
  );
}

function EmptyRoomCard() {
  return (
    <div className="mt-3 p-6 bg-white/5 rounded-2xl text-center">
      <p className="text-white/80">No public rooms right now. Start one with the + button.</p>
    </div>
  );
}

function FloatingActionButton({ onClick, disabled, children }: { onClick: () => void; disabled?: boolean; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      aria-label="Create a room"
      className="home-create right-6 bottom-6 z-40 w-14 h-14 rounded-full
        bg-xynk-lime text-xynk-ink border border-white/30 shadow-lg
        flex items-center justify-center
        transition-all duration-200
        disabled:opacity-50 disabled:cursor-not-allowed disabled:shadow-none
        active:scale-[0.96]"
    >
      {children}
    </button>
  );
}
