import { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { X, Settings, Image as PhotoLibrary, History, Heart as Favorite, Link, MoreVertical, UserPlus as PersonAdd, UserMinus as PersonRemove, ShieldCheck, User as Person, MessageCircle as ChatBubbleOutline, ChevronRight, Globe, Users } from 'lucide-react';
import { useWatchPartyStore } from '../../stores/watchPartyStore';
import { api } from '../../services/api';
import { MediaPreview } from '../ui/MediaPreview';
import { _publicDisplayName, _publicHandle, _time, _timeDetailed, _watchTime, _providerLabel, _dateLabel, _relativeTime, _providerCaption, _asInt } from '../../lib/formatters';

interface UserProfileScreenProps {
  userId: string;
  summary?: Record<string, any>;
}

export function UserProfileScreen({ userId, summary = {} }: UserProfileScreenProps) {
  const navigate = useNavigate();
  const selectYoutubeVideo = useWatchPartyStore(state => state.selectYoutubeVideo);
  const selectCrunchyrollVideo = useWatchPartyStore(state => state.selectCrunchyrollVideo);
  const selectDirectVideo = useWatchPartyStore(state => state.selectDirectVideo);
  const setOwnProfile = useWatchPartyStore(state => state.setProfile);
  const [profile, setProfile] = useState<Record<string, any> | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [friendBusy, setFriendBusy] = useState(false);
  const [editing, setEditing] = useState(false);
  const [editName, setEditName] = useState('');
  const [editBio, setEditBio] = useState('');
  const [savingProfile, setSavingProfile] = useState(false);

  useEffect(() => {
    load();
  }, []);

  async function load() {
    try {
      const [loaded, library] = await Promise.all([
        api.publicProfile(userId),
        userId === useWatchPartyStore.getState().profile?.id ? api.getMediaDashboard() : Promise.resolve(null),
      ]);
      setProfile(library ? {...loaded, gallery: library.gallery, history: library.history,
        likedVideos: library.likes, watchTogetherSeconds: library.watchTogetherSeconds} : loaded);
      setLoading(false);
    } catch (exception) {
      setError(String(exception));
      setLoading(false);
    }
  }

  const me = profile?.id === useWatchPartyStore.getState().profile?.id;
  const friend = profile?.relationship?.status === 'ACCEPTED';
  const outgoing = profile?.relationship?.outgoing === true;

  async function updateFriendship() {
    if (friendBusy || outgoing) return;
    setFriendBusy(true);
    setActionError(null);
    try {
      if (friend) await api.removeFriend(userId);
      else await api.sendFriendRequest(userId);
      await load();
    } catch (exception) {
      setActionError(String(exception));
    } finally {
      setFriendBusy(false);
    }
  }

  async function saveProfile() {
    setSavingProfile(true); setActionError(null);
    try {
      const saved = await api.updateBasicProfile(editName.trim(), editBio.trim());
      setOwnProfile(saved);
      setEditing(false);
      await load();
    } catch (exception) { setActionError(String(exception)); }
    finally { setSavingProfile(false); }
  }

  async function uploadAvatar(file: File) {
    setSavingProfile(true); setActionError(null);
    try {
      const saved = await api.uploadAvatar(file);
      setOwnProfile(saved);
      await load();
    } catch (exception) { setActionError(String(exception)); }
    finally { setSavingProfile(false); }
  }

  async function playMedia(item: any) {
    setActionError(null);
    try {
      const provider = String(item.provider || '').toUpperCase();
      if (provider === 'YOUTUBE') {
        await selectYoutubeVideo({videoId: item.mediaId, title: item.title, thumbnailUrl: item.thumbnailUrl,
          provider: 'YOUTUBE', channelTitle: item.channelTitle || ''});
      } else if (provider === 'CRUNCHYROLL') {
        await selectCrunchyrollVideo(item.mediaId, item.title, item.thumbnailUrl);
      } else {
        await selectDirectVideo(item.sourcePageUrl || item.mediaId);
      }
      navigate('/');
    } catch (exception) { setActionError(String(exception)); }
  }

  if (loading) return <LoaderFullScreen />;
  if (error) return <ErrorScreen error={error} onRetry={load} />;

  const name = _publicDisplayName(profile || summary);
  const avatar = (profile || summary).avatarUrl;

  return (
    <div className="min-h-screen bg-xynk-ink relative flex flex-col">
      <header className="px-4 py-3 flex items-center justify-between border-b border-xynk-line bg-black/50">
        <button onClick={() => window.history.back()} className="p-2 rounded-xl hover:bg-white/10 transition-colors">
          <X className="w-6 h-6 text-white" />
        </button>
        <h1 className="font-bold text-xl text-white mx-auto">{name}</h1>
        <div className="w-10" />
      </header>

      <main className="flex-1 overflow-y-auto p-4 space-y-4">
        {actionError && <div role="alert" className="rounded-xl border border-red-400/40 bg-red-500/10 p-3 text-red-200">{actionError}</div>}
        {/* Profile Header */}
        <div className="flex items-center gap-4 p-4 bg-xynk-panel rounded-2xl border border-xynk-line">
          <div className="relative w-20 h-20 rounded-full bg-gradient-to-br from-xynk-lime to-xynk-mint flex items-center justify-center flex-shrink-0">
            {avatar ? (
              <img src={avatar} alt="" className="w-full h-full rounded-full" />
            ) : (
              <span className="text-3xl font-bold text-xynk-ink">{name.charAt(0).toUpperCase()}</span>
            )}
          </div>
          <div className="flex-1">
            <h1 className="text-2xl font-bold text-white">{name}</h1>
            <p className="text-white/60">@{_publicHandle(profile || summary)}</p>
            <p className="text-xs text-white/50 mt-1">Joined {_dateLabel((profile || summary).joinedAt)}</p>
          </div>
          {!me && (
            <button className={`btn-${friend ? 'secondary' : 'primary'} px-4 py-2`} onClick={() => void updateFriendship()} disabled={friendBusy || outgoing}>
              {friend ? <PersonRemove className="w-5 h-5 mr-1" /> : outgoing ? <MoreVertical /> : <PersonAdd />}
              <span>{friend ? 'Remove friend' : outgoing ? 'Request pending' : 'Add friend'}</span>
            </button>
          )}
          {me && <button type="button" className="btn-secondary px-4 py-2" onClick={() => { setEditName(String(profile?.displayName || '')); setEditBio(String(profile?.bio || '')); setEditing(true); }}>Edit profile</button>}
        </div>

        {me && <label className="inline-flex items-center gap-2 text-sm text-xynk-lime cursor-pointer">Change avatar<input type="file" accept="image/*" className="sr-only" disabled={savingProfile} onChange={event => { const file = event.currentTarget.files?.[0]; if (file) void uploadAvatar(file); }} /></label>}

        {me && editing && <div role="dialog" aria-label="Edit profile" className="rounded-2xl border border-xynk-line bg-xynk-panel p-4 space-y-3">
          <label className="block text-sm text-white">Display name<input value={editName} maxLength={120} onChange={event => setEditName(event.target.value)} className="input-field w-full mt-1" /></label>
          <label className="block text-sm text-white">Bio<textarea value={editBio} maxLength={500} onChange={event => setEditBio(event.target.value)} className="input-field w-full mt-1 min-h-24" /></label>
          <div className="flex gap-2"><button type="button" className="btn-primary" disabled={!editName.trim() || savingProfile} onClick={() => void saveProfile()}>{savingProfile ? 'Saving…' : 'Save'}</button><button type="button" className="btn-secondary" onClick={() => setEditing(false)}>Cancel</button></div>
        </div>}

        {/* Bio */}
        {(profile?.bio) && (
          <div className="p-4 bg-xynk-panel rounded-2xl border border-xynk-line">
            <h3 className="font-semibold text-white mb-2">Bio</h3>
            <p className="text-white/80 whitespace-pre-wrap">{profile.bio}</p>
          </div>
        )}

        {/* Stats */}
        <div className="grid grid-cols-3 gap-3">
          <StatCard label="Friends" value={profile?.friendCount || 0} icon={Users} color="from-xynk-lime to-xynk-mint" />
          <StatCard label="Watch time" value={_watchTime(profile?.watchTogetherSeconds || 0)} icon={History} color="from-xynk-mint to-xynk-lime" />
          <StatCard label="Gallery" value={profile?.gallery?.length || 0} icon={PhotoLibrary} color="from-xynk-coral to-xynk-mint" />
        </div>

        {/* Gallery */}
        {(profile?.gallery?.length || summary?.gallery?.length) > 0 && (
          <div>
            <h3 className="font-semibold text-white mb-3 flex items-center gap-2">
              <PhotoLibrary className="w-5 h-5 text-xynk-lime" />
              Gallery
            </h3>
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
              {((profile?.gallery || summary?.gallery || []) as any[]).slice(0, 8).map((item: any, i: number) => (
                <MediaCard key={i} item={item} onClick={() => void playMedia(item)} />
              ))}
            </div>
          </div>
        )}

        {/* History */}
        {(profile?.history?.length || summary?.history?.length) > 0 && (
          <div>
            <h3 className="font-semibold text-white mb-3 flex items-center gap-2">
              <History className="w-5 h-5 text-xynk-lime" />
              History
            </h3>
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
              {((profile?.history || summary?.history || []) as any[]).slice(0, 12).map((item: any, i: number) => (
                <MediaCard key={i} item={item} onClick={() => void playMedia(item)} />
              ))}
            </div>
          </div>
        )}

        {/* Liked */}
        {(profile?.likedVideos?.length || summary?.likedVideos?.length) > 0 && (
          <div>
            <h3 className="font-semibold text-white mb-3 flex items-center gap-2">
              <Favorite className="w-5 h-5 text-xynk-coral" />
              Liked
            </h3>
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
              {((profile?.likedVideos || summary?.likedVideos || []) as any[]).slice(0, 8).map((item: any, i: number) => (
                <MediaCard key={i} item={item} onClick={() => void playMedia(item)} />
              ))}
            </div>
          </div>
        )}

        {/* Interests */}
        {(profile?.interests?.length || summary?.interests?.length) > 0 && (
          <div>
            <h3 className="font-semibold text-white mb-3 flex items-center gap-2">
              <Favorite className="w-5 h-5 text-xynk-lime" />
              Interests
            </h3>
            <div className="flex flex-wrap gap-2">
              {((profile?.interests || summary?.interests || []) as string[]).map((interest, i) => (
                <span key={i} className="px-3 py-1 bg-xynk-lime/20 text-xynk-lime rounded-full text-sm font-medium">{interest}</span>
              ))}
            </div>
          </div>
        )}

        {/* Connections */}
        {(profile?.connections?.length || summary?.connections?.length) > 0 && (
          <div>
            <h3 className="font-semibold text-white mb-3 flex items-center gap-2">
              <Link className="w-5 h-5 text-xynk-lime" />
              Connections
            </h3>
            <div className="space-y-2">
              {((profile?.connections || summary?.connections || []) as any[]).map((conn: any, i: number) => (
                <div key={i} className="flex items-center gap-3 p-3 rounded-xl bg-xynk-panelSoft border border-xynk-line">
                  <Globe className="w-5 h-5 text-xynk-lime" />
                  <div className="flex-1">
                    <p className="font-medium text-white">{conn.provider}</p>
                    <p className="text-xs text-white/60 truncate">{conn.url}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
      </main>
    </div>
  );
}

function LoaderFullScreen() {
  return (
    <div className="fixed inset-0 flex items-center justify-center bg-xynk-ink z-50">
      <div className="flex flex-col items-center gap-4">
        <div className="w-16 h-16 rounded-full border-4 border-xynk-lime border-t-transparent animate-spin" />
        <p className="text-white font-medium">Loading…</p>
      </div>
    </div>
  );
}

function ErrorScreen({ error, onRetry }: { error: string; onRetry: () => void }) {
  return (
    <div className="fixed inset-0 flex items-center justify-center bg-xynk-ink z-50 p-6">
      <div className="text-center max-w-md">
        <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-red-500/20 flex items-center justify-center">
          <svg className="w-8 h-8 text-red-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="10" /><path d="M12 8v4M12 16h.01"/></svg>
        </div>
        <h2 className="text-xl font-bold text-white mb-2">Could not load profile</h2>
        <p className="text-white/60 mb-4">{error}</p>
        <button onClick={onRetry} className="btn-primary">Retry</button>
      </div>
    </div>
  );
}

function StatCard({ label, value, icon: Icon, color }: { label: string; value: number | string; icon: any; color: string }) {
  return (
    <div className="p-4 rounded-2xl bg-xynk-panelSoft border border-xynk-line text-center">
      <div className={`w-10 h-10 mx-auto mb-3 rounded-xl flex items-center justify-center ${color}`}>
        <Icon className="w-5 h-5 text-white" />
      </div>
      <p className="font-bold text-xl text-white">{value}</p>
      <p className="text-xs text-white/60">{label}</p>
    </div>
  );
}

function MediaCard({ item, onClick }: { item: any; onClick: () => void }) {
  return (
    <button type="button" onClick={onClick} className="group relative aspect-video rounded-xl overflow-hidden bg-xynk-panelSoft text-left">
      <MediaPreview
        mediaId={item.mediaId}
        provider={item.provider}
        thumbnailUrl={item.thumbnailUrl}
        contentLabel={item.title}
        className="w-full h-full"
      />
      <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-transparent group-hover:from-black/60 transition-colors" />
      <div className="absolute bottom-3 left-3 right-3">
        <p className="font-semibold text-sm text-white truncate group-hover:text-xynk-lime transition-colors">{item.title}</p>
        <p className="text-[11px] text-white/60 truncate">{_providerLabel(item.provider)}</p>
      </div>
    </button>
  );
}
