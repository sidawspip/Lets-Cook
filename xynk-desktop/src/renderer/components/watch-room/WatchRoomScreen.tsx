import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { X, Settings, Users, Mic, MicOff, Volume2, VolumeX, ScreenShare, Fullscreen, Maximize2, ChevronDown, MessageSquare, ListMusic, ChevronUp, Search, SkipForward, Heart, MoreHorizontal, Lock } from 'lucide-react';
import { useWatchPartyStore } from '../../stores/watchPartyStore';
import { api } from '../../services/api';
import { useUIStore } from '../../stores/uiStore';
import { PlayerOverlay } from './PlayerOverlay';
import { ChatPanel } from './ChatPanel';
import { PeoplePanel } from './PeoplePanel';
import { QueuePanel } from './QueuePanel';
import { PeopleDrawer } from './PeopleDrawer';
import { Shelf } from './Shelf';
import { MediaPreview } from '../ui/MediaPreview';
import { WaveLoader } from '../ui/WaveLoader';
import { LogoMark } from '../ui/LogoMark';
import { MediaDiscoveryScreen } from '../media-discovery/MediaDiscoveryScreen';
import { _mediaTitle, _sourceLabel, _time } from '../../lib/formatters';
import { PartyRoom, RoomWatchState, QueueItem } from '../../types/models';
import shaka from 'shaka-player';

function playbackErrorMessage(error: unknown): string {
  const failure = error as {code?: number; message?: string; data?: unknown[]};
  if (failure?.code === 1001) {
    const status = typeof failure.data?.[1] === 'number' ? failure.data[1] : null;
    const requestUrl = typeof failure.data?.[0] === 'string' ? failure.data[0] : '';
    let endpoint = '';
    try { const parsed = new URL(requestUrl); endpoint = `${parsed.hostname}${parsed.pathname}`; } catch { /* The response may omit its URL. */ }
    console.error(`Crunchyroll HTTP playback error: status=${status ?? 'unknown'} endpoint=${endpoint || 'unknown'}`);
    if (status === 401 || status === 403) return `Sign in to Crunchyroll to play this episode (HTTP ${status}).`;
    return status ? `Crunchyroll stream returned HTTP ${status}.` : 'Crunchyroll stream request failed.';
  }
  if (failure?.code) {
    console.error(`Crunchyroll playback error: code=${failure.code}`);
    return `Crunchyroll playback failed (${failure.code})`;
  }
  return failure?.message || String(error);
}

export function WatchRoomScreen() {
  const navigate = useNavigate();
  const {
    activeRoom,
    watchState,
    canControlWatch,
    activeParticipants,
    voiceRevision,
    voice,
    canViewVideo,
    checkingVideoAccess,
    shelfOpen,
    setShelfOpen,
    panel,
    setPanel,
    queue,
    roomQueue,
    personalQueue,
    suggestions,
    setSuggestions,
    searchVideos,
    messages,
    muted,
    volume,
    setMuted,
    setVolume,
    leaveRoom,
    togglePlayback,
    seek,
    updatePosition,
    setWatchState,
    setActiveRoom,
    setQueue,
    addSuggestion,
    selectQueueItem,
    sendMessage,
    reactToMessage,
    beginReply,
    cancelReply,
    replyToMessage,
    selectedQuality,
    setQuality,
    selectedCaption,
    setCaption,
    qualities,
    setAvailableQualities,
    captionLanguages,
  } = useWatchPartyStore();

  const {
    controlsVisible,
    setControlsVisible,
    playbackRate,
    setPlaybackRate,
    isFullscreen,
    setFullscreen,
  } = useUIStore();

  const videoRef = useRef<HTMLVideoElement>(null);
  const screenRef = useRef<HTMLVideoElement>(null);
  const shakaRef = useRef<shaka.Player | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [playerReady, setPlayerReady] = useState(false);
  const [showPeopleDrawer, setShowPeopleDrawer] = useState(false);
  const [position, setPosition] = useState(0);
  const [duration, setDuration] = useState(0);
  const [videoError, setVideoError] = useState<string | null>(null);
  const [providerLoginOpen, setProviderLoginOpen] = useState(false);
  const [providerVideo, setProviderVideo] = useState<import('../../types/models').ChatMessage | null>(null);
  const [playerRetry, setPlayerRetry] = useState(0);
  const [liked, setLiked] = useState(false);
  const [skipNotice, setSkipNotice] = useState('');
  const [roomSettingsOpen, setRoomSettingsOpen] = useState(false);
  const [queueMode, setQueueMode] = useState('HOSTS_ONLY');
  const [youtubeUrl, setYoutubeUrl] = useState<string | null>(null);
  const youtube = watchState?.provider?.toUpperCase() === 'YOUTUBE';
  const crunchyroll = watchState?.provider?.toUpperCase() === 'CRUNCHYROLL';
  const directHls = watchState?.provider?.toUpperCase() === 'DIRECT_HLS' || watchState?.sourceType?.toUpperCase() === 'DIRECT_HLS';
  const activeMicMembers = voice.members.filter(member => member.microphoneOn);
  const screenTrack = voice.screenTrack;

  useEffect(() => {
    const title = watchState?.title?.trim() || '';
    if (!youtube || !title || /^(youtube video|video|now playing)$/i.test(title)) {
      setSuggestions([]);
      return;
    }
    let cancelled = false;
    const seed = title.replace(/\[[^\]]*\]|\([^)]*\)/g, ' ')
      .replace(/\b(official|video|audio|lyrics?|lyrical|hd|4k|8k|full song)\b/gi, ' ')
      .replace(/\s+/g, ' ').trim();
    if (!seed) { setSuggestions([]); return; }
    const query = /\b(s\d{1,2}\s*e\d{1,3}|season\s*\d+|episode\s*\d+|ep\.?\s*\d+)\b/i.test(title)
      ? `${seed} next episode`
      : /\b(song|music|lyrics?|remix|lofi|album|feat\.?|ft\.?)\b/i.test(title) || title.includes(' - ')
        ? `songs similar to ${seed}` : `${seed} related videos`;
    void searchVideos(query).then(videos => {
      if (!cancelled) setSuggestions(videos.filter(video => video.videoId !== watchState?.mediaId));
    }).catch(() => { if (!cancelled) setSuggestions([]); });
    return () => { cancelled = true; };
  }, [watchState?.mediaId, watchState?.title, youtube]);

  useEffect(() => {
    if (!watchState?.mediaId) { setLiked(false); return; }
    let cancelled = false;
    void api.getMediaDashboard().then(dashboard => {
      if (!cancelled) setLiked((dashboard.likes || []).some((item: {mediaId: string}) => item.mediaId === watchState.mediaId));
    }).catch(() => {});
    return () => { cancelled = true; };
  }, [watchState?.mediaId]);

  const toggleLike = async () => {
    if (!watchState) return;
    try {
      await api.recordMedia({mediaId: watchState.mediaId, provider: watchState.provider, title: watchState.title,
        thumbnailUrl: watchState.thumbnailUrl, sourceUrl: watchState.sourceUrl, sourceType: watchState.sourceType});
      await api.setMediaLike(watchState.mediaId, !liked);
      setLiked(!liked);
    } catch (error) { setSkipNotice(String(error)); }
  };

  const voteSkip = async () => {
    if (!activeRoom) return;
    try {
      const result = await api.voteToSkip(activeRoom.id);
      setSkipNotice(result.skipped ? 'Skipped' : `${result.votes}/${result.required} votes to skip`);
      if (result.state) setWatchState(result.state);
    } catch (error) { setSkipNotice(String(error)); }
  };

  useEffect(() => {
    if (!roomSettingsOpen || !activeRoom) return;
    void api.getWatchQueueInfo(activeRoom.id).then(info => setQueueMode(info.mode || 'HOSTS_ONLY')).catch(() => {});
  }, [roomSettingsOpen, activeRoom?.id]);

  const changeQueueMode = async (mode: string) => {
    if (!activeRoom || !canControlWatch) return;
    try { await api.updateWatchSettings(activeRoom.id, mode); setQueueMode(mode); }
    catch (error) { setSkipNotice(String(error)); }
  };

  const changeAudience = async (visibility: string) => {
    if (!activeRoom || !canControlWatch) return;
    const accessPolicy = visibility === 'PRIVATE' ? 'INVITE_ONLY' : 'OPEN';
    try {
      await api.updateRoomAudience(activeRoom.id, visibility, accessPolicy);
      setActiveRoom({...activeRoom, visibility, accessPolicy});
    } catch (error) { setSkipNotice(String(error)); }
  };

  useEffect(() => {
    const element = screenRef.current;
    if (!element || !screenTrack) return;
    screenTrack.attach(element);
    return () => { screenTrack.detach(element); };
  }, [screenTrack, voiceRevision]);

  useEffect(() => {
    if (!crunchyroll || !watchState?.mediaId || !videoRef.current) return;
    let cancelled = false;
    let player: shaka.Player | null = null;
    let diagnosticTimer: ReturnType<typeof setTimeout> | null = null;
    setPlayerReady(false);
    setVideoError(null);
    void (async () => {
      try {
        shaka.polyfill.installAll();
        if (!shaka.Player.isBrowserSupported()) throw new Error('Widevine playback is unavailable in this runtime');
        const prepared = await window.xynkDesktop.prepareCrunchyroll(watchState.mediaId);
        if (cancelled || !videoRef.current) return;
        player = new shaka.Player();
        shakaRef.current = player;
        player.addEventListener('error', event => {
          const failure = (event as Event & {detail?: unknown}).detail;
          if (!cancelled) setVideoError(playbackErrorMessage(failure));
        });
        await player.attach(videoRef.current);
        shaka.net.NetworkingEngine.registerScheme('xynk-license', (uri, request) => {
          const body = request.body;
          const challenge = body ? new Uint8Array(body instanceof ArrayBuffer ? body : body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength)) : new Uint8Array();
          const response = window.xynkDesktop.requestCrunchyrollLicense(challenge).then(data => ({
            uri,
            originalUri: uri,
            originalRequest: request,
            data: new Uint8Array(data),
            headers: {'content-type': 'application/octet-stream'},
            status: 200,
          }));
          return shaka.util.AbortableOperation.notAbortable(response);
        });
        player.configure({drm: {
          servers: {'com.widevine.alpha': 'xynk-license://widevine'},
          preferredKeySystems: ['com.widevine.alpha'],
        }});
        await player.load(prepared.manifestUrl);
        console.error(`Crunchyroll DRM selected: ${player.keySystem() || 'none'}; keys=${JSON.stringify(player.getKeyStatuses())}; track=${JSON.stringify(player.getVariantTracks().find(track => track.active) ?? null)}`);
        if (!cancelled) {
          setPlayerReady(true);
          diagnosticTimer = setTimeout(() => {
            const video = videoRef.current;
            if (!video || cancelled) return;
            const frames = video.getVideoPlaybackQuality?.().totalVideoFrames ?? -1;
            console.error(`Crunchyroll media state: drm=${player?.keySystem() || 'none'} keys=${JSON.stringify(player?.getKeyStatuses() ?? {})} ready=${video.readyState} network=${video.networkState} error=${video.error?.code ?? 'none'} paused=${video.paused} time=${Math.round(video.currentTime)} size=${video.videoWidth}x${video.videoHeight} frames=${frames} buffering=${player?.isBuffering()}`);
            if (watchState.playing && frames === 0) setVideoError(previous => previous ?? 'Crunchyroll video has not started rendering. Please retry.');
          }, 8000);
        }
      } catch (error) {
        if (!cancelled) {
          setVideoError(playbackErrorMessage(error));
        }
      }
    })();
    return () => {cancelled = true; if (diagnosticTimer) clearTimeout(diagnosticTimer); shakaRef.current = null; if (player) void player.destroy();};
  }, [crunchyroll, watchState?.mediaId, playerRetry]);

  useEffect(() => {
    if (!directHls || !watchState?.sourceUrl || !videoRef.current) return;
    let cancelled = false;
    const player = new shaka.Player();
    shakaRef.current = player;
    setPlayerReady(false);
    setVideoError(null);
    void (async () => {
      try {
        shaka.polyfill.installAll();
        if (!shaka.Player.isBrowserSupported()) throw new Error('HLS playback is unavailable in this runtime');
        await player.attach(videoRef.current!);
        await player.load(watchState.sourceUrl!);
        if (!cancelled) setPlayerReady(true);
      } catch (error) {
        if (!cancelled) setVideoError(error instanceof Error ? error.message : String(error));
      }
    })();
    return () => { cancelled = true; if (shakaRef.current === player) shakaRef.current = null; void player.destroy(); };
  }, [directHls, watchState?.sourceUrl, watchState?.mediaId, playerRetry]);

  useEffect(() => {
    if (!youtube || !watchState?.mediaId) { setYoutubeUrl(null); return; }
    let cancelled = false;
    setYoutubeUrl(null); setPlayerReady(false); setVideoError(null);
    void window.xynkDesktop.resolveYouTube(watchState.mediaId, selectedQuality).then(media => {
      if (cancelled) return;
      setYoutubeUrl(media.url);
      setAvailableQualities(['auto', ...media.qualities]);
    }).catch(error => { if (!cancelled) setVideoError(error instanceof Error ? error.message : String(error)); });
    return () => { cancelled = true; };
  }, [youtube, watchState?.mediaId, selectedQuality, playerRetry]);

  useEffect(() => {
    if (videoRef.current) {
      videoRef.current.muted = muted;
      videoRef.current.volume = volume;
    }
  }, [muted, volume, watchState?.mediaId, youtubeUrl]);

  useEffect(() => {
    if (!watchState) return;
    if (videoRef.current) {
      if (Math.abs(videoRef.current.currentTime - watchState.positionSeconds) > 2) videoRef.current.currentTime = watchState.positionSeconds;
      videoRef.current.playbackRate = watchState.playbackRate || 1;
      if (watchState.playing && videoRef.current.paused) void videoRef.current.play().catch(() => {});
      else if (!watchState.playing && !videoRef.current.paused) videoRef.current.pause();
    }
  }, [watchState?.revision, watchState?.playing, watchState?.positionSeconds, youtubeUrl]);

  // Position sync
  useEffect(() => {
    if (watchState) {
      setPosition(watchState.positionSeconds);
      setDuration(watchState.durationSeconds || 0);
    }
  }, [watchState]);

  // Sync position with store
  useEffect(() => {
    const interval = setInterval(() => {
      if (videoRef.current && !videoRef.current.paused) {
        setPosition(videoRef.current.currentTime);
        updatePosition(videoRef.current.currentTime);
      }
    }, 1000);
    return () => clearInterval(interval);
  }, [updatePosition]);

  const handleVideoLoaded = () => {
    setPlayerReady(true);
    setVideoError(null);
    if (videoRef.current && watchState?.positionSeconds) videoRef.current.currentTime = watchState.positionSeconds;
    if (watchState?.playing) {
      videoRef.current?.play().catch(() => {});
    }
  };

  const handleVideoError = (e: React.SyntheticEvent<HTMLVideoElement>) => {
    setVideoError('Failed to load video');
    console.error('Video error:', e);
  };

  const handlePlayPause = () => {
    if (videoRef.current) {
      videoRef.current.paused ? videoRef.current.play() : videoRef.current.pause();
      void togglePlayback();
    }
  };

  const handleSeek = (value: number) => {
    if (videoRef.current) {
      videoRef.current.currentTime = value;
      seek(value);
    }
  };

  const handleVideoEnded = () => {
    if (!activeRoom || !watchState || !canControlWatch) return;
    void (async () => {
      try {
        if (roomQueue.length > 0) {
          setWatchState(await api.playHighestVoted(activeRoom.id));
          setQueue(await api.getWatchQueue(activeRoom.id));
        } else {
          setWatchState(await api.updateWatch(activeRoom.id, {...watchState, playing: false, positionSeconds: duration}));
        }
      } catch (error) { setVideoError(String(error)); }
    })();
  };

  const handleBack = () => {
    void leaveRoom();
    navigate('/');
  };

  const [accessRequested, setAccessRequested] = useState(false);
  const [accessError, setAccessError] = useState<string | null>(null);
  const requestViewerAccess = async () => {
    if (!activeRoom || accessRequested) return;
    try { await api.requestVideoAccess(activeRoom.id); setAccessRequested(true); }
    catch (error) { setAccessError(String(error)); }
  };

  if (!activeRoom) return <LaunchScreen />;

  const state = watchState;
  const key = state ? `${state.provider}:${state.mediaId}:${state.sourceUrl ?? ''}` : null;

  return (
    <div className="watch-room-shell relative h-screen overflow-hidden bg-xynk-ink flex flex-col">
      {/* Ambient backdrop */}
      <div className="watch-room-ambient absolute inset-0 -z-10 bg-gradient-to-br from-[#31204B] via-[#4B315D] to-[#101D2B]">
        <div className="absolute -top-90 -right-90 w-[300px] h-[300px] rounded-full bg-[#66E33F9E] blur-[70px]" />
        <div className="absolute bottom-70 left-[-100px] w-[340px] h-[340px] rounded-full bg-[#661AA8D6] blur-[70px]" />
        <div className="absolute inset-0 bg-gradient-to-b from-[#12000000] to-[#B3050910]" />
      </div>

      <div className="relative flex-1 min-h-0 flex flex-col overflow-hidden">
        {/* Header */}
        <header className="watch-room-header px-2 py-2 flex items-center justify-between z-10 bg-black/50 backdrop-blur-sm border-b border-xynk-line">
          <button onClick={handleBack} className="p-2 rounded-xl hover:bg-white/10 transition-colors" aria-label="Back">
            <X className="w-7 h-7 text-white" />
          </button>

          <div className="flex-1 flex items-center justify-center">
            {state ? (
              <div className="flex items-center gap-2 overflow-hidden">
                <MediaPreview
                  mediaId={state.mediaId}
                  provider={state.provider}
                  thumbnailUrl={state.thumbnailUrl}
                  contentLabel={_mediaTitle(state)}
                  className="w-10 h-6 rounded"
                />
                <div className="text-left truncate">
                  <p className="font-semibold text-xs text-white">{_mediaTitle(state)}</p>
                  <p className="text-[10px] text-white/60">{_sourceLabel(state)}</p>
                </div>
              </div>
            ) : (
              <h1 className="font-black tracking-widest text-xl text-white">XYNK</h1>
            )}
          </div>

          {activeMicMembers.length > 0 && <div className="hidden md:flex items-center gap-1 mr-2">
            {activeMicMembers.slice(0, 5).map(member => <span key={member.identity}
              title={`${member.name}${member.speaking ? ' speaking' : ''}`}
              className={`w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold bg-xynk-panelSoft border-2 ${member.speaking ? 'border-xynk-lime shadow-[0_0_14px_rgba(214,140,250,0.9)] animate-pulse' : 'border-xynk-line'}`}>
              {member.name.charAt(0).toUpperCase()}
            </span>)}
          </div>}

          <div className="flex items-center gap-1">
            {canControlWatch && <button onClick={() => setRoomSettingsOpen(true)} className="p-2 rounded-xl hover:bg-white/10" aria-label="Room controls"><Settings className="w-5 h-5 text-white"/></button>}
            {state && <button onClick={() => void toggleLike()} className="p-2 rounded-xl hover:bg-white/10" aria-label={liked ? 'Unlike video' : 'Like video'} title={liked ? 'Unlike video' : 'Like video'}><Heart className={`w-5 h-5 ${liked ? 'fill-xynk-coral text-xynk-coral' : 'text-white'}`}/></button>}
            {state && <button onClick={() => void voteSkip()} className="p-2 rounded-xl hover:bg-white/10" aria-label="Vote to skip" title="Vote to skip"><SkipForward className="w-5 h-5 text-white"/></button>}
            <button onClick={() => setPanel('queue')} className="relative p-2 rounded-xl hover:bg-white/10 transition-colors" aria-label="Queue">
              <ListMusic className="w-5 h-5 text-white" />
              {(roomQueue.length + personalQueue.length > 0) && (
                <span className="absolute -top-1 -right-1 w-5 h-5 bg-xynk-coral rounded-full text-[9px] font-black flex items-center justify-center">
                  {roomQueue.length + personalQueue.length}
                </span>
              )}
            </button>
            <button onClick={() => setShowPeopleDrawer(true)} className="p-2 rounded-xl hover:bg-white/10 transition-colors relative" aria-label="People">
              <Users className="w-5 h-5 text-white" />
              <span className="absolute -top-1 -right-1 w-5 h-5 bg-xynk-coral rounded-full text-[9px] font-black flex items-center justify-center">
                {activeRoom.viewerCount}
              </span>
            </button>
            <button onClick={() => setShelfOpen(true)} className="p-2 rounded-xl hover:bg-white/10 transition-colors" aria-label="Add source" disabled={!canControlWatch && !canViewVideo}>
              <Search className="w-5 h-5 text-white" />
            </button>
            <button onClick={() => setFullscreen(!isFullscreen)} className="p-2 rounded-xl hover:bg-white/10 transition-colors" aria-label={isFullscreen ? 'Exit fullscreen' : 'Fullscreen'}>
              {isFullscreen ? <Maximize2 className="w-5 h-5 text-white" /> : <Fullscreen className="w-5 h-5 text-white" />}
            </button>
          </div>
        </header>
        {skipNotice && <div role="status" className="text-center text-xs text-white/80 bg-xynk-panelSoft py-1">{skipNotice}</div>}

        {/* Main content */}
        <main className="watch-room-main flex-1 min-h-0 relative flex flex-col lg:flex-row overflow-hidden">
          {checkingVideoAccess ? (
            <div className="flex items-center justify-center h-full">
              <WaveLoader label="Joining room" size={56} />
            </div>
          ) : !canViewVideo ? (
            <VideoAccessGate onRequest={() => void requestViewerAccess()} requested={accessRequested} error={accessError} />
          ) : (
            <>
              {/* Video Player */}
              <div className="watch-room-player-stage relative w-full lg:flex-1 h-[min(28vh,360px)] lg:h-full min-h-0 flex items-center justify-center p-3 md:p-4">
                {(videoError || (!playerReady && state?.playing)) && (
                  <div className="absolute inset-0 flex items-center justify-center z-10 bg-black/80 rounded-2xl">
                    {videoError ? (
                      <div className="p-6 text-center">
                        <p className="text-white mb-4">{videoError}</p>
                        <button onClick={() => { if (crunchyroll && /(?:HTTP |returned )(?:401|403)/.test(videoError)) setProviderLoginOpen(true); else { setVideoError(null); setPlayerRetry(value => value + 1); videoRef.current?.load(); } }} className="btn-primary">
                          {crunchyroll && /(?:HTTP |returned )(?:401|403)/.test(videoError) ? 'Open Crunchyroll sign-in' : 'Retry'}
                        </button>
                      </div>
                    ) : (
                      <WaveLoader label="Starting video" size={56} />
                    )}
                  </div>
                )}

                {screenTrack && <video ref={screenRef} autoPlay playsInline muted={voice.screenShareEnabled}
                  className={`absolute object-contain rounded-2xl bg-black z-[5] ${voice.screenShareEnabled ? 'left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 w-[70%] h-[70%] border border-xynk-line' : 'inset-3 md:inset-4 w-[calc(100%-1.5rem)] h-[calc(100%-1.5rem)] md:w-[calc(100%-2rem)] md:h-[calc(100%-2rem)]'}`} />}
                <video
                  ref={videoRef}
                  key={youtube ? youtubeUrl ?? state?.mediaId : state?.mediaId}
                  src={youtube ? youtubeUrl ?? undefined : undefined}
                  className="w-full h-full max-w-[1600px] max-h-[900px] rounded-2xl bg-black object-contain"
                  onLoadedData={handleVideoLoaded}
                  onError={handleVideoError}
                  onEnded={handleVideoEnded}
                  onTimeUpdate={(e) => setPosition(e.currentTarget.currentTime)}
                  playsInline
                  disablePictureInPicture={!isFullscreen}
                >
                  {state && state.sourceUrl && !crunchyroll && !youtube && !directHls && (
                    <source src={state.sourceUrl} type="video/mp4" />
                  )}
                </video>

                {/* Player Overlay */}
                <PlayerOverlay
                  state={state}
                  position={position}
                  duration={duration}
                  playing={state?.playing || false}
                  canControl={canControlWatch}
                  muted={muted}
                  volume={volume}
                  onPlayPause={handlePlayPause}
                  onSeek={handleSeek}
                  onMute={() => setMuted(!muted)}
                  onVolumeChange={setVolume}
                  onQualityChange={setQuality}
                  onCaptionChange={setCaption}
                  onPip={() => { if (videoRef.current && document.pictureInPictureEnabled) void videoRef.current.requestPictureInPicture().catch(() => {}); }}
                  onFullscreen={() => setFullscreen(!isFullscreen)}
                  qualities={qualities}
                  captionLanguages={captionLanguages}
                  selectedQuality={selectedQuality}
                  selectedCaption={selectedCaption}
                />

                {state && <div className="watch-room-now-playing" aria-label={`Now playing ${_mediaTitle(state)}`}>
                  <div className="watch-room-now-playing-copy">
                    <span>NOW PLAYING · {_sourceLabel(state)}</span>
                    <strong>{_mediaTitle(state)}</strong>
                  </div>
                  <span className="watch-room-viewers">{activeRoom.viewerCount} watching</span>
                </div>}

                {/* Caption */}
                {/* Would render WebVTT captions here */}
              </div>

              {/* People Drawer */}
              {showPeopleDrawer && (
                <PeopleDrawer
                  onClose={() => setShowPeopleDrawer(false)}
                  activeRoom={activeRoom}
                />
              )}

              {/* Shelf */}
              {shelfOpen && (
                <Shelf
                  onClose={() => setShelfOpen(false)}
                  state={state}
                  roomQueue={roomQueue}
                  personalQueue={queue}
                  suggestions={suggestions}
                  onAddSuggestion={addSuggestion}
                  onSelectQueueItem={selectQueueItem}
                />
              )}

              {providerLoginOpen && <MediaDiscoveryScreen initialProvider="crunchyroll" targetRoomId={activeRoom.id}
                onClose={() => {setProviderLoginOpen(false); setPlayerRetry(value => value + 1);}} />}
              {providerVideo && <MediaDiscoveryScreen
                initialProvider={providerVideo.mediaProvider?.toLowerCase() === 'youtube' ? 'youtube' : providerVideo.mediaProvider?.toLowerCase() || 'web'}
                initialUrl={providerVideo.mediaProvider === 'YOUTUBE' ? `https://www.youtube.com/watch?v=${encodeURIComponent(providerVideo.mediaId || '')}` : providerVideo.mediaId}
                targetRoomId={activeRoom.id} onClose={() => setProviderVideo(null)} />}

              {roomSettingsOpen && <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4" role="dialog" aria-label="Room controls">
                <div className="watch-room-settings w-full max-w-md rounded-2xl border border-xynk-line bg-xynk-panel p-5 text-white">
                  <div className="flex items-center justify-between mb-5"><h2 className="font-bold text-lg">Room controls</h2><button onClick={() => setRoomSettingsOpen(false)} aria-label="Close room controls"><X size={22}/></button></div>
                  <p className="text-xs font-bold text-xynk-mint mb-2">WHO CAN SET VIDEO</p>
                  {([['HOSTS_ONLY','Host only'], ['PERMISSION','Selected people'], ['VOTE',"Let's vote"]] as const).map(([mode,label]) => <button key={mode} onClick={() => void changeQueueMode(mode)} className={`w-full text-left p-3 rounded-xl mb-1 ${queueMode === mode ? 'bg-xynk-lime/20 text-xynk-lime' : 'hover:bg-white/10'}`}>{label}</button>)}
                  <p className="text-xs font-bold text-xynk-mint mb-2 mt-4">WHO CAN JOIN</p>
                  {([['PUBLIC','Everyone'], ['FRIENDS','Friends'], ['PRIVATE','Invite only']] as const).map(([visibility,label]) => <button key={visibility} onClick={() => void changeAudience(visibility)} className={`w-full text-left p-3 rounded-xl mb-1 ${activeRoom.visibility === visibility ? 'bg-xynk-lime/20 text-xynk-lime' : 'hover:bg-white/10'}`}>{label}</button>)}
                </div>
              </div>}

              {/* Bottom Panels */}
              <div className="watch-room-side-panel relative flex-1 lg:flex-none lg:w-[40%] max-w-[520px] h-[32vh] lg:h-full min-h-0 flex flex-col border-t lg:border-t-0 lg:border-l border-xynk-line bg-xynk-panel/75 backdrop-blur-xl">
                {/* Tab bar */}
                <div className="watch-room-tabbar flex px-2 py-1 border-b border-xynk-line bg-black/30">
                  {(['chat', 'queue', 'people'] as const).map((tab) => (
                    <button
                      key={tab}
                      onClick={() => setPanel(tab)}
                      className={`watch-room-tab flex-1 flex items-center justify-center gap-1.5 py-2 px-2 rounded-xl text-sm font-medium transition-colors ${
                        panel === tab
                          ? 'bg-xynk-lime/20 text-xynk-lime'
                          : 'text-white/70 hover:text-white hover:bg-white/5'
                      }`}
                    >
                      {tab === 'chat' && <MessageSquare className="w-4 h-4" />}
                      {tab === 'queue' && <ListMusic className="w-4 h-4" />}
                      {tab === 'people' && <Users className="w-4 h-4" />}
                      <span className="hidden sm:inline">{tab.charAt(0).toUpperCase() + tab.slice(1)}</span>
                      {tab === 'queue' && (roomQueue.length + personalQueue.length > 0) && (
                        <span className="w-5 h-5 bg-xynk-coral rounded-full text-[9px] font-black flex items-center justify-center">
                          {roomQueue.length + personalQueue.length}
                        </span>
                      )}
                    </button>
                  ))}
                </div>

                {/* Panel content */}
                <div className="flex-1 overflow-y-auto p-3">
                  {panel === 'chat' && <ChatPanel messages={messages} state={state} onOpenVideo={setProviderVideo} />}
                  {panel === 'queue' && <QueuePanel />}
                  {panel === 'people' && <PeoplePanel room={activeRoom} />}
                </div>
              </div>
            </>
          )}
        </main>
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

function VideoAccessGate({ onRequest, requested, error }: { onRequest: () => void; requested: boolean; error: string | null }) {
  return (
    <div className="flex items-center justify-center h-full p-8">
      <div className="w-full max-w-md text-center p-8 bg-xynk-panel rounded-2xl border border-xynk-line">
        <div className="w-16 h-16 mx-auto mb-6 rounded-full bg-red-500/20 flex items-center justify-center">
          <Lock className="w-8 h-8 text-red-400" />
        </div>
        <h2 className="text-xl font-bold text-white mb-2">Video is private</h2>
        <p className="text-white/70 mb-6">The host hasn't granted you video access yet.</p>
        {error && <p role="alert" className="text-red-300 mb-3">{error}</p>}
        <button onClick={onRequest} disabled={requested} className="btn-primary w-full">{requested ? 'Request sent' : 'Request access'}</button>
      </div>
    </div>
  );
}
