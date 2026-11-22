import { useEffect, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { X, ChevronLeft, ChevronRight, RefreshCw, Settings, Search, ExternalLink, Check, Loader2, Zap, Monitor, Cloud, FolderOpen, Globe, Youtube, Play, Plus } from 'lucide-react';
import { useWatchPartyStore } from '../../stores/watchPartyStore';
import { useUIStore } from '../../stores/uiStore';
import { MediaPreview } from '../ui/MediaPreview';
import { WaveLoader } from '../ui/WaveLoader';
import { LogoMark } from '../ui/LogoMark';
import { PartyRoom, VideoSuggestion } from '../../types/models';
import { ProviderBrowser, type DetectedProviderVideo } from './ProviderBrowser';

const PROVIDERS = [
  { id: 'youtube', name: 'YouTube', icon: Youtube, url: 'https://www.youtube.com/', color: 'from-red-500 to-red-600' },
  { id: 'google-drive', name: 'Google Drive', icon: Cloud, url: 'https://drive.google.com/drive/u/0/my-drive', color: 'from-blue-500 to-blue-600' },
  { id: 'dropbox', name: 'Dropbox', icon: FolderOpen, url: 'https://www.dropbox.com/home', color: 'from-blue-400 to-blue-500' },
  { id: 'onedrive', name: 'OneDrive', icon: Cloud, url: 'https://onedrive.live.com/', color: 'from-blue-400 to-blue-600' },
  { id: 'box', name: 'Box', icon: FolderOpen, url: 'https://app.box.com/', color: 'from-blue-500 to-blue-600' },
  { id: 'internet-archive', name: 'Internet Archive', icon: Globe, url: 'https://archive.org/details/movies', color: 'from-amber-500 to-amber-600' },
  { id: 'twitch', name: 'Twitch', icon: Monitor, url: 'https://www.twitch.tv/', color: 'from-purple-600 to-purple-700' },
  { id: 'vimeo', name: 'Vimeo', icon: Globe, url: 'https://vimeo.com/watch', color: 'from-blue-500 to-cyan-500' },
  { id: 'x', name: 'X', icon: Zap, url: 'https://x.com/home', color: 'from-black to-gray-800' },
  { id: 'web', name: 'Google Search', icon: Search, url: 'https://www.google.com/', color: 'from-blue-500 to-violet-500' },
  { id: 'nextcloud', name: 'Nextcloud', icon: Cloud, url: 'https://nextcloud.com/sign-up/', color: 'from-blue-500 to-sky-500' },
  { id: 'crunchyroll', name: 'Crunchyroll', icon: Play, url: 'https://www.crunchyroll.com/videos/new', color: 'from-orange-500 to-amber-500' },
  { id: 'netflix', name: 'Netflix', icon: Play, url: 'https://www.netflix.com/browse', color: 'from-red-700 to-red-500' },
  { id: 'prime-video', name: 'Prime Video', icon: Play, url: 'https://www.primevideo.com/', color: 'from-blue-700 to-sky-500' },
];

interface MediaDiscoveryScreenProps {
  query?: string;
  initialProvider?: string;
  initialUrl?: string;
  targetRoomId?: string;
  onClose?: () => void;
  onSelect?: () => void;
}

export function MediaDiscoveryScreen({ query = '', initialProvider = 'youtube', initialUrl, targetRoomId, onClose, onSelect }: MediaDiscoveryScreenProps) {
  const navigate = useNavigate();
  const params = useParams();
  const { searchVideos, selectYoutubeVideo, selectCrunchyrollVideo, selectDirectVideo, createDirectParty } = useWatchPartyStore();
  const { setDiscoveryQuery } = useUIStore();

  const [activeProvider, setActiveProvider] = useState<string>(initialProvider);
  const [searchQuery, setSearchQuery] = useState(query);
  const [videoResults, setVideoResults] = useState<VideoSuggestion[]>([]);
  const [searching, setSearching] = useState(false);
  const [webViewUrl, setWebViewUrl] = useState<string>(initialUrl || (query && initialProvider === 'youtube'
    ? `https://www.youtube.com/results?search_query=${encodeURIComponent(query)}`
    : PROVIDERS.find(p => p.id === initialProvider)?.url || 'https://www.youtube.com/'));
  const [webViewLoading, setWebViewLoading] = useState(false);
  const [webViewError, setWebViewError] = useState<string | null>(null);
  const [selectionError, setSelectionError] = useState<string | null>(null);
  const [detectedVideo, setDetectedVideo] = useState<DetectedProviderVideo | null>(null);
  const [committing, setCommitting] = useState(false);
  const [browser, setBrowser] = useState<Electron.WebviewTag | null>(null);
  const lastSelectedPage = useRef(initialUrl || '');

  useEffect(() => {
    if (query && activeProvider === 'youtube') setWebViewUrl(`https://www.youtube.com/results?search_query=${encodeURIComponent(query)}`);
  }, [query]);

  const doSearch = async (q: string) => {
    if (q.trim().length < 2) {
      setVideoResults([]);
      return;
    }
    setSearching(true);
    try {
      const results = await searchVideos(q.trim());
      setVideoResults(results);
    } catch (e) {
      console.error('Search failed:', e);
    } finally {
      setSearching(false);
    }
  };

  const handleProviderSelect = (providerId: string) => {
    setActiveProvider(providerId);
    setDetectedVideo(null);
    setWebViewError(null);
    setSelectionError(null);
    const provider = PROVIDERS.find(p => p.id === providerId);
    lastSelectedPage.current = '';
    setWebViewLoading(true);
    setWebViewUrl(provider?.url ?? '');
  };

  const handleProviderNavigation = async (url: string, guest: Electron.WebviewTag) => {
    if (!['youtube', 'crunchyroll'].includes(activeProvider) || !url || url === lastSelectedPage.current) return;
    let selected: URL;
    try { selected = new URL(url); } catch { return; }
    const host = selected.hostname.toLowerCase();
    if (activeProvider === 'crunchyroll') {
      const episodeId = /(^|\.)crunchyroll\.com$/.test(host) ? selected.pathname.match(/^\/watch\/([A-Za-z0-9]+)/)?.[1] : null;
      if (!episodeId) return;
      lastSelectedPage.current = url;
      setSelectionError(null);
      setCommitting(true);
      try {
        let title = '';
        let thumbnail = '';
        for (let attempt = 0; attempt < 16; attempt++) {
          if (guest.getURL() !== url) return;
          try {
            const details = await guest.executeJavaScript(`(() => ({
              title: [...document.querySelectorAll('h1,h2,h3')].map(element => (element.textContent || '').replace(/\\s+/g, ' ').trim()).find(value => /^E\\d+\\s*[–—-]\\s*\\S/i.test(value)) || '',
              thumbnail: document.querySelector('meta[property="og:image"]')?.content || ''
            }))()`) as {title?: string; thumbnail?: string};
            if (details.thumbnail) thumbnail = details.thumbnail;
            if (details.title) {
              title = details.title.replace(/\s*\|\s*Crunchyroll\s*$/i, '').trim();
              break;
            }
          } catch { /* Episode route is still rendering. */ }
          await new Promise(resolve => setTimeout(resolve, 250));
        }
        if (!title) title = selected.pathname.split('/')[3]?.replace(/-/g, ' ') || 'Crunchyroll episode';
        await selectCrunchyrollVideo(url, title, thumbnail || undefined, targetRoomId);
        onSelect?.();
        onClose?.();
      } catch (error) {
        lastSelectedPage.current = '';
        setSelectionError(error instanceof Error ? error.message : String(error));
      } finally { setCommitting(false); }
      return;
    }
    const id = host === 'youtu.be' ? selected.pathname.slice(1) :
      host.endsWith('youtube.com') ? selected.searchParams.get('v') || selected.pathname.match(/^\/(?:shorts|live)\/([\w-]{11})/)?.[1] : null;
    if (!id || !/^[\w-]{11}$/.test(id)) return;
    lastSelectedPage.current = url;
    setSelectionError(null);
    setCommitting(true);
    try {
      // YouTube publishes /watch before its title updates. Wait for a video title
      // so the room and chat card never retain the generic site name.
      let title = '';
      for (let attempt = 0; attempt < 12; attempt++) {
        if (guest.getURL() !== url) return;
        try {
          const candidate = await guest.executeJavaScript('document.querySelector("meta[property=\'og:title\']")?.content || document.title || ""') as string;
          if (candidate && !/^(youtube|youtube - youtube)$/i.test(candidate.trim()) && !/results\?/i.test(candidate)) {
            title = candidate.replace(/\s+-\s+YouTube$/, '');
            break;
          }
        } catch { /* The guest is still navigating. */ }
        await new Promise(resolve => setTimeout(resolve, 250));
      }
      if (!title) {
        const matches = await searchVideos(id);
        title = matches.find(item => item.videoId === id)?.title || 'YouTube video';
      }
      await selectYoutubeVideo({videoId: id, title,
        channelTitle: 'YouTube', thumbnailUrl: `https://i.ytimg.com/vi/${id}/hqdefault.jpg`, provider: 'YOUTUBE'}, targetRoomId);
      onSelect?.();
      onClose?.();
    } catch (error) {
      lastSelectedPage.current = '';
      setSelectionError(error instanceof Error ? error.message : String(error));
    } finally { setCommitting(false); }
  };

  const handleSearch = async (e: React.FormEvent) => {
    e.preventDefault();
    if (searchQuery.trim().length >= 2) {
      await doSearch(searchQuery.trim());
    }
  };

  const handleYouTubeSelect = async (video: VideoSuggestion) => {
    if (targetRoomId) {
      await selectYoutubeVideo(video, targetRoomId);
    } else {
      await selectYoutubeVideo(video);
    }
    onSelect?.();
    onClose?.();
  };

  const handleDirectVideo = async () => {
    const url = webViewUrl;
    try {
      const uri = new URL(url);
      if (!['https:', 'http:'].includes(uri.protocol)) throw new Error('Invalid protocol');
      if (targetRoomId) {
        await selectDirectVideo(url, targetRoomId);
      } else {
        await createDirectParty(url);
      }
      onSelect?.();
      onClose?.();
    } catch {
      alert('Please enter a valid HTTPS URL');
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      doSearch(searchQuery);
    }
  };

  const provider = PROVIDERS.find(p => p.id === activeProvider);
  const Icon = provider?.icon ?? Globe;

  const handleDirectInput = (url: string) => {
    try {
      const uri = new URL(url);
      if (!['https:'].includes(uri.protocol)) throw new Error('Invalid protocol');
      setWebViewUrl(uri.toString());
    } catch {
      alert('Please enter a valid HTTPS URL');
    }
  };

  const commitSelection = async () => {
    if (detectedVideo) {
      setSelectionError(null);
      setCommitting(true);
      try {
        const selected = new URL(detectedVideo.pageUrl);
        const youtubeId = selected.hostname.endsWith('youtube.com')
          ? selected.searchParams.get('v') || selected.pathname.match(/^\/shorts\/([\w-]{11})/)?.[1]
          : null;
        if (youtubeId) {
          await selectYoutubeVideo({videoId: youtubeId, title: detectedVideo.title,
            channelTitle: 'YouTube', thumbnailUrl: detectedVideo.thumbnail || `https://i.ytimg.com/vi/${youtubeId}/hqdefault.jpg`, provider: 'YOUTUBE'}, targetRoomId);
        } else if (selected.hostname.endsWith('crunchyroll.com')) {
          const episodeId = selected.pathname.match(/^\/watch\/([A-Za-z0-9]+)/)?.[1];
          if (!episodeId) throw new Error('Open a Crunchyroll episode player first');
          const title = /^E\d+\s*[–—-]\s*\S/i.test(detectedVideo.title)
            ? detectedVideo.title
            : selected.pathname.split('/')[3]?.replace(/-/g, ' ') || 'Crunchyroll episode';
          await selectCrunchyrollVideo(detectedVideo.pageUrl, title, detectedVideo.thumbnail, targetRoomId);
        } else {
          await selectDirectVideo(detectedVideo.pageUrl, targetRoomId);
        }
        onSelect?.();
        onClose?.();
      } catch (error) {
        setSelectionError(error instanceof Error ? error.message : String(error));
      } finally {
        setCommitting(false);
      }
    }
  };

  return (
    <div className={`${onClose ? 'fixed inset-0 z-50' : 'h-screen'} bg-xynk-ink flex flex-col overflow-hidden`}>
      {/* Header */}
      <header className="px-4 py-3 flex items-center justify-between border-b border-xynk-line bg-black/50">
        <button onClick={onClose || (() => navigate('/'))} className="p-2 rounded-xl hover:bg-white/10 transition-colors">
          <ChevronLeft className="w-6 h-6 text-white" />
        </button>

        <LogoMark size={28} className="mx-auto" />

        {targetRoomId && (
          <div className="w-10" />
        )}
      </header>

      <div className="flex-1 min-h-0 flex overflow-hidden">
        {/* Provider sidebar */}
        <aside className="w-64 min-h-0 overflow-y-auto border-r border-xynk-line bg-black/30 flex flex-col">
          <div className="p-4 border-b border-xynk-line">
            <h3 className="font-semibold text-white mb-3">Choose a source</h3>
            <div className="space-y-1">
              {PROVIDERS.map(p => {
                const Icon = p.icon;
                return (
                  <button
                    key={p.id}
                    onClick={() => handleProviderSelect(p.id)}
                    disabled={committing}
                    className={`w-full flex items-center gap-3 p-3 rounded-xl transition-colors ${
                      activeProvider === p.id
                        ? 'bg-xynk-lime/20 text-xynk-lime'
                        : 'text-white/80 hover:bg-white/5'
                    }`}
                  >
                    <div className={`w-8 h-8 rounded-xl flex items-center justify-center ${p.color}`}>
                      <Icon className="w-5 h-5" />
                    </div>
                    <span className="font-medium">{p.name}</span>
                  </button>
                );
              })}
              <div className="pt-4 border-t border-xynk-line">
                <input
                  type="text"
                  placeholder="Enter HTTPS URL…"
                  className="input-field text-sm"
                  onKeyDown={e => e.key === 'Enter' && e.currentTarget.value.trim() && handleDirectInput(e.currentTarget.value.trim())}
                />
              </div>
            </div>
          </div>
        </aside>

        {/* Main content */}
        <main className="flex-1 min-w-0 min-h-0 flex flex-col overflow-hidden">
          {webViewUrl && (
            <div className="flex-1 min-h-0 relative flex flex-col">
              <div className="h-12 flex-none flex items-center gap-1 px-3 bg-xynk-panelSoft/80 border-b border-xynk-line">
                <button type="button" className="p-2 rounded-lg hover:bg-white/10 disabled:opacity-40" disabled={!browser} onClick={() => { try { if (browser?.canGoBack()) browser.goBack(); } catch { /* Guest is still loading. */ } }} aria-label="Browser back"><ChevronLeft className="w-5 h-5" /></button>
                <button type="button" className="p-2 rounded-lg hover:bg-white/10 disabled:opacity-40" disabled={!browser} onClick={() => { try { if (browser?.canGoForward()) browser.goForward(); } catch { /* Guest is still loading. */ } }} aria-label="Browser forward"><ChevronRight className="w-5 h-5" /></button>
                <button type="button" className="p-2 rounded-lg hover:bg-white/10" onClick={() => browser?.reload()} aria-label="Reload page"><RefreshCw className="w-5 h-5" /></button>
                <span className="ml-auto text-xs text-white/60">{provider?.name ?? 'Web'}</span>
              </div>
              <ProviderBrowser
                url={webViewUrl}
                temporary={false}
                onReady={setBrowser}
                onDetected={setDetectedVideo}
                onNavigate={handleProviderNavigation}
                onLoad={() => setWebViewLoading(false)}
                onError={error => {setWebViewError(error); setWebViewLoading(false);}}
              />
              {webViewLoading && (
                <div className="absolute inset-0 flex items-center justify-center bg-black/80 z-10">
                  <WaveLoader label="Loading…" size={52} />
                </div>
              )}
              {webViewError && (
                <div className="absolute inset-0 flex flex-col items-center justify-center gap-4 bg-black/80 z-10 p-8 text-center">
                  <p className="text-red-400">{webViewError}</p>
                  <button onClick={() => { setWebViewError(null); setWebViewLoading(true); browser?.reload(); }} className="btn-primary">Retry</button>
                </div>
              )}
              {selectionError && (
                <div role="alert" className="absolute top-3 left-3 right-3 md:right-auto md:max-w-md z-20 flex items-start gap-3 rounded-xl border border-red-400/40 bg-xynk-panel p-3 shadow-xl">
                  <p className="flex-1 min-w-0 text-sm text-red-200">{selectionError}</p>
                  <button type="button" onClick={() => setSelectionError(null)} className="text-white/70 hover:text-white" aria-label="Dismiss error"><X className="w-4 h-4" /></button>
                </div>
              )}
              {detectedVideo && activeProvider !== 'youtube' && (
                <div className="absolute bottom-4 left-4 right-4 md:left-auto md:right-4 md:w-80 z-20">
                  <div className="bg-xynk-panel rounded-2xl border border-xynk-line p-4 shadow-xl">
                    <div className="flex items-start gap-4">
                      <div className="relative w-24 h-14 rounded-lg overflow-hidden flex-shrink-0">
                        {detectedVideo.thumbnail ? (
                          <img src={detectedVideo.thumbnail} alt="" className="w-full h-full object-cover rounded-lg" />
                        ) : (
                          <div className="w-full h-full bg-gradient-to-br from-xynk-lime to-xynk-mint rounded-lg" />
                        )}
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-xs font-black text-xynk-lime tracking-wider">VIDEO FOUND</p>
                        <p className="font-semibold text-white truncate">{detectedVideo.title}</p>
                      </div>
                    </div>
                    <button className="btn-primary w-full mt-4" disabled={committing} onClick={() => commitSelection()}>
                      {committing ? 'Adding video…' : targetRoomId ? 'Add to room' : 'Play in room'}
                    </button>
                  </div>
                </div>
              )}
            </div>
          )}

          {!webViewUrl && activeProvider === 'youtube' && (
            <div className="flex-1 flex flex-col">
              {/* YouTube search */}
              <div className="p-4 border-b border-xynk-line">
                <form onSubmit={handleSearch} className="max-w-2xl mx-auto">
                  <div className="relative">
                    <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-white/60" />
                    <input
                      type="search"
                      value={searchQuery}
                      onChange={e => setSearchQuery(e.target.value)}
                      onKeyDown={handleKeyDown}
                      placeholder="Search YouTube…"
                      className="w-full px-12 py-3 pl-12 bg-white/10 rounded-2xl border border-white/20 focus:border-xynk-lime focus:ring-2 focus:ring-xynk-lime/20 text-white placeholder:text-white/50"
                    />
                    {searching && (
                      <Loader2 className="absolute right-4 top-1/2 -translate-y-1/2 w-5 h-5 animate-spin text-xynk-lime" />
                    )}
                  </div>
                </form>
              </div>

              {/* Video results */}
              <div className="flex-1 overflow-y-auto p-4">
                {videoResults.length === 0 && !searchQuery ? (
                  <div className="text-center py-12 text-white/50">
                    <Youtube className="w-16 h-16 mx-auto mb-4 text-white/30" />
                    <p className="text-lg font-medium">Search YouTube to find videos</p>
                    <p className="text-sm text-white/40 mt-2">Type a query above to search</p>
                  </div>
                ) : videoResults.length === 0 && searchQuery ? (
                  <div className="text-center py-12 text-white/50">
                    <Loader2 className="w-8 h-8 mx-auto mb-4 animate-spin text-xynk-lime" />
                    <p>Searching for "{searchQuery}"…</p>
                  </div>
                ) : (
                  <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                    {videoResults.map((video, i) => (
                      <YouTubeResultCard
                        key={`${video.videoId}-${i}`}
                        video={video}
                        onSelect={() => handleYouTubeSelect(video)}
                      />
                    ))}
                  </div>
                )}
              </div>
            </div>
          )}

          {!webViewUrl && activeProvider !== 'youtube' && provider && (
            <div className="flex-1 flex items-center justify-center p-8">
              <div className="text-center max-w-md">
                <div className="w-24 h-24 mx-auto mb-6 rounded-2xl bg-gradient-to-br from-xynk-lime to-xynk-mint flex items-center justify-center">
                  <Icon className="w-12 h-12 text-white" />
                </div>
                <h2 className="text-2xl font-bold text-white mb-2">{provider.name}</h2>
                <p className="text-white/60 mb-6">Browse {provider.name} and when you find a video, XYNK will detect it automatically.</p>
                <button className="btn-primary" onClick={() => setWebViewUrl(provider.url)}>
                  <ExternalLink className="w-5 h-5 mr-2" />
                  Open {provider.name}
                </button>
              </div>
            </div>
          )}
        </main>
      </div>
    </div>
  );
}

function YouTubeResultCard({ video, onSelect }: { video: VideoSuggestion; onSelect: () => void }) {
  return (
    <button
      onClick={onSelect}
      className="group relative bg-xynk-panelSoft rounded-2xl overflow-hidden transition-all hover:shadow-[0_0_24px_2px_rgba(241,160,255,0.2)]"
    >
      <div className="aspect-video relative overflow-hidden">
        <img
          src={video.thumbnailUrl}
          alt=""
          className="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
        />
        <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-transparent" />
      </div>
      <div className="p-3">
        <h3 className="font-semibold text-sm text-white line-clamp-2">{video.title}</h3>
        <p className="text-xs text-white/60 truncate mt-1">{video.channelTitle}</p>
      </div>
      <div className="absolute bottom-3 right-3 opacity-0 group-hover:opacity-100 transition-opacity">
        <span className="block p-2 rounded-full bg-xynk-lime/90 text-xynk-ink group-hover:bg-xynk-lime transition-colors">
          <Plus className="w-5 h-5" />
        </span>
      </div>
    </button>
  );
}
