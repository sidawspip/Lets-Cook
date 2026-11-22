import { useState, useEffect } from 'react';
import { useWatchPartyStore } from '../../stores/watchPartyStore';
import { MediaPreview } from '../ui/MediaPreview';
import { _time } from '../../lib/formatters';
import { VideoSuggestion, QueueItem, RoomWatchState } from '../../types/models';
import { X, Play, Pause, Search, Plus as Add, ChevronLeft, ChevronRight } from 'lucide-react';

export function Shelf({
  onClose,
  state,
  roomQueue,
  personalQueue,
  suggestions,
  onAddSuggestion,
  onSelectQueueItem,
}: {
  onClose: () => void;
  state: RoomWatchState | null;
  roomQueue: QueueItem[];
  personalQueue: QueueItem[];
  suggestions: VideoSuggestion[];
  onAddSuggestion: (video: VideoSuggestion) => void;
  onSelectQueueItem: (item: QueueItem) => void;
}) {
  const { selectedQuality, selectedCaption, searchVideos, canControlWatch, togglePlayback, seek } = useWatchPartyStore();
  const [search, setSearch] = useState('');
  const [searchResults, setSearchResults] = useState<VideoSuggestion[]>([]);
  const [searching, setSearching] = useState(false);
  const position = state?.positionSeconds || 0;
  const duration = state?.durationSeconds || 0;

  useEffect(() => {
    const timer = setTimeout(() => {
      if (search.trim().length >= 2) {
        doSearch(search.trim());
      } else {
        setSearchResults([]);
      }
    }, 400);
    return () => clearTimeout(timer);
  }, [search]);

  const doSearch = async (query: string) => {
    setSearching(true);
    try {
      setSearchResults(await searchVideos(query));
    } finally {
      setSearching(false);
    }
  };

  const handleAdd = (video: VideoSuggestion) => {
    onAddSuggestion(video);
    setSearch('');
    setSearchResults([]);
  };

  const handlePlayPause = () => { if (canControlWatch) void togglePlayback(); };
  const handleSeek = (pos: number) => { if (canControlWatch) void seek(pos); };

  const sections = [
    { title: 'NOW PLAYING', items: state ? [{ ...state, isPlaying: true } as any] : [] },
    { title: 'UP NEXT · VOTE', items: roomQueue, showVote: true },
    { title: 'YOUR QUEUE', items: personalQueue.slice(1), showVote: false },
    { title: search ? 'SEARCH RESULTS' : 'SUGGESTIONS', items: search ? searchResults : suggestions, showAdd: true },
  ];

  return (
    <div className="fixed inset-0 z-50 flex justify-end bg-black/55" onClick={onClose}>
    <div className="h-full w-full max-w-[660px] min-w-0 bg-xynk-ink border-l border-xynk-line shadow-2xl flex flex-col" onClick={event => event.stopPropagation()} role="dialog" aria-label="Room picks">
      {/* Header */}
      <div className="p-4 border-b border-xynk-line bg-xynk-panelSoft flex items-start justify-between gap-3">
        <div className="flex min-w-0 items-center gap-4">
          {/* Mini player */}
          <div className="relative w-[140px] md:w-[200px] flex-shrink-0">
            {state && (
              <>
                <button type="button" onClick={onClose} aria-label="Return to video" className="relative aspect-video w-full rounded-lg overflow-hidden">
                  <MediaPreview
                    mediaId={state.mediaId}
                    provider={state.provider}
                    thumbnailUrl={state.thumbnailUrl}
                    contentLabel={state.title}
                    className="w-full h-full"
                  />
                  <div className="absolute bottom-0 left-0 right-0 h-4 bg-gradient-to-t from-black/80 to-transparent">
                    <div className="h-1 bg-xynk-lime rounded-full" style={{ width: `${duration > 0 ? Math.min(100, Math.max(0, position / duration * 100)) : 0}%` }} />
                  </div>
                </button>
                <div className="mt-2 flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <button className="p-1 rounded hover:bg-white/10 disabled:opacity-40" aria-label="Rewind" disabled={!canControlWatch} onClick={() => handleSeek(Math.max(0, position - 10))}>
                      <ChevronLeft className="w-4 h-4 text-white" />
                    </button>
                    <button className="p-1 rounded hover:bg-white/10 disabled:opacity-40" aria-label="Play/Pause" disabled={!canControlWatch} onClick={handlePlayPause}>
                      {state?.playing ? <Pause className="w-4 h-4 text-xynk-lime" /> : <Play className="w-4 h-4 text-xynk-lime" />}
                    </button>
                    <button className="p-1 rounded hover:bg-white/10 disabled:opacity-40" aria-label="Forward" disabled={!canControlWatch} onClick={() => handleSeek(Math.min(duration || position + 10, position + 10))}>
                      <ChevronRight className="w-4 h-4 text-white" />
                    </button>
                  </div>
                </div>
              </>
            )}
            {!state && <div className="aspect-video rounded-lg bg-gradient-to-br from-[#673c87] to-[#183e64] flex items-center justify-center"><Play className="w-8 h-8 text-white/70" /></div>}
          </div>

          <div className="flex-1 ml-4 min-w-0">
            <p className="text-[10px] font-black text-xynk-lime tracking-wider">NOW PLAYING</p>
            <p className="font-semibold text-sm truncate text-white max-w-xs">{state ? state.title : 'Nothing playing'}</p>
            <p className="text-[11px] text-white/60 truncate max-w-xs">{_time(position)} / {_time(duration)}</p>
          </div>
        </div>

        <button onClick={onClose} aria-label="Close room picks" className="p-2 rounded-xl hover:bg-white/10 transition-colors"><X className="w-6 h-6 text-white" /></button>
      </div>

      {/* Search */}
      <div className="p-4 border-b border-xynk-line bg-xynk-panel/70">
        <div className="relative max-w-xl mx-auto">
          <input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search YouTube…"
            className="input-field w-full pl-12 pr-12"
          />
          <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-white/60" />
          {searching ? (
            <div className="absolute right-4 top-1/2 -translate-y-1/2 w-5 h-5 animate-spin border-2 border-xynk-lime border-t-transparent rounded-full" />
          ) : (
            <button onClick={() => { if (search.trim()) doSearch(search.trim()); }} className="absolute right-4 top-1/2 -translate-y-1/2 p-2 rounded-xl hover:bg-white/10">
              <ChevronRight className="w-5 h-5 text-white" />
            </button>
          )}
        </div>
      </div>

      {/* Sections */}
      <div className="flex-1 min-h-0 overflow-y-auto p-4 space-y-4">
        {sections.map((section, sectionIndex) => (
          <section key={sectionIndex} className="rounded-2xl border border-xynk-line bg-xynk-panelSoft/70 p-4">
            <h3 className="text-xs font-black text-xynk-muted tracking-wider mb-3">{section.title}</h3>
            {section.items.length === 0 ? (
              <div className="text-center py-5 text-sm text-white/50">
                {section.title.includes('SEARCH') ? 'No results' : 'Nothing here yet'}
              </div>
            ) : (
              <div className="grid grid-cols-2 gap-3">
                {section.items.map((item: any, itemIndex: number) => (
                  <ShelfItem
                    key={`${sectionIndex}-${itemIndex}`}
                    item={item}
                    isPlaying={section.title === 'NOW PLAYING'}
                    showVote={section.showVote}
                    showAdd={section.showAdd}
                    onTap={section.showAdd ? () => handleAdd(item) : () => onSelectQueueItem(item)}
                  />
                ))}
              </div>
            )}
          </section>
        ))}
      </div>
    </div>
    </div>
  );
}

function ShelfItem({
  item,
  isPlaying,
  showVote,
  showAdd,
  onTap,
}: {
  item: any;
  isPlaying?: boolean;
  showVote?: boolean;
  showAdd?: boolean;
  onTap: () => void;
}) {
  return (
    <button
      onClick={onTap}
      className={`relative group aspect-video rounded-xl overflow-hidden transition-all ${
        isPlaying ? 'ring-2 ring-xynk-lime' : ''
      }`}
    >
      <MediaPreview
        mediaId={item.mediaId || item.videoId}
        provider={item.provider}
        thumbnailUrl={item.thumbnailUrl}
        contentLabel={item.title}
        className="w-full h-full"
      />
      <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/20 to-transparent" />
      <div className="absolute bottom-3 left-3 right-3 flex flex-col gap-1">
        {showVote && (
          <span className="text-[10px] font-black text-xynk-lime px-2 py-0.5 rounded bg-xynk-lime/20 self-start">
            {showVote ? 'VOTE' : 'QUEUE'}
          </span>
        )}
        <p className="text-sm font-semibold text-white truncate group-hover:text-xynk-lime transition-colors">{item.title}</p>
        <p className="text-[11px] text-white/60 truncate">{item.addedByName || item.channelTitle || 'Unknown'}</p>
        {showAdd && (
          <div className="absolute bottom-3 right-3">
            <span className="block p-2 rounded-full bg-xynk-lime/90 text-xynk-ink group-hover:bg-xynk-lime transition-colors">
              <Add className="w-5 h-5" />
            </span>
          </div>
        )}
      </div>
    </button>
  );
}
