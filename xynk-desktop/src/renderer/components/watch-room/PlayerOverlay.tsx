import { useState } from 'react';
import {
  Play, Pause, Volume2, VolumeX, Settings, Maximize2, Minimize2,
  ChevronLeft, ChevronRight, SkipBack, SkipForward, Heart, MoreHorizontal
} from 'lucide-react';
import { _time } from '../../lib/formatters';

interface PlayerOverlayProps {
  state: { title: string; provider: string; thumbnailUrl?: string; durationSeconds?: number; playbackRate: number } | null;
  position: number;
  duration: number;
  playing: boolean;
  canControl: boolean;
  muted: boolean;
  volume: number;
  onPlayPause: () => void;
  onSeek: (pos: number) => void;
  onMute: () => void;
  onVolumeChange: (vol: number) => void;
  onQualityChange: (q: string) => void;
  onCaptionChange: (c: string) => void;
  onPip: () => void;
  onFullscreen: () => void;
  qualities: string[];
  captionLanguages: Record<string, string>;
  selectedQuality: string;
  selectedCaption: string;
}

export function PlayerOverlay({
  state,
  position,
  duration,
  playing,
  canControl,
  muted,
  volume,
  onPlayPause,
  onSeek,
  onMute,
  onVolumeChange,
  onQualityChange,
  onCaptionChange,
  onFullscreen,
  qualities,
  captionLanguages,
  selectedQuality,
  selectedCaption,
}: PlayerOverlayProps) {
  const [showSettings, setShowSettings] = useState(false);
  const [showVolume, setShowVolume] = useState(false);
  const [vol, setVol] = useState(volume);

  const handleVolumeChange = (v: number) => {
    setVol(v);
    onVolumeChange(v);
  };

  return (
    <div className="absolute inset-0 pointer-events-none">
      {/* Top bar */}
      <div className="absolute top-2 left-2 right-2 flex items-start justify-between pointer-events-auto px-2">
        <div className="flex items-center gap-2">
          {state && state.thumbnailUrl && (
            <img src={state.thumbnailUrl} alt="" className="w-10 h-6 rounded" />
          )}
          {state && (
            <div className="text-left min-w-0">
              <p className="font-semibold text-xs text-white truncate max-w-[200px]">
                {state.title}
              </p>
              <p className="text-[10px] text-white/60 truncate max-w-[200px]">
                {state.provider}
              </p>
            </div>
          )}
        </div>

        <div className="flex items-center gap-1">
          <button
            onClick={() => setShowSettings(!showSettings)}
            className="p-2 rounded-xl hover:bg-white/10 transition-colors"
            disabled={!canControl}
          >
            <Settings className="w-5 h-5 text-white" />
          </button>
          <button
            onClick={onFullscreen}
            className="p-2 rounded-xl hover:bg-white/10 transition-colors"
          >
            <Maximize2 className="w-5 h-5 text-white" />
          </button>
        </div>
      </div>

      {/* Bottom controls */}
      <div className="absolute bottom-0 left-0 right-0 pointer-events-auto p-2 md:p-4 bg-gradient-to-t from-black/90 via-black/40 to-transparent">
        {/* Progress bar */}
        <div className="relative mb-3" role="slider" aria-label="Playback position" aria-valuemin={0} aria-valuemax={duration} aria-valuenow={Math.round(position)}>
          <div
            className="h-1.5 bg-white/20 rounded-full cursor-pointer"
            onClick={(e) => {
              if (canControl) {
                const rect = e.currentTarget.getBoundingClientRect();
                const pct = (e.clientX - rect.left) / rect.width;
                onSeek(pct * duration);
              }
            }}
          >
            <div
              className="h-full bg-xynk-lime rounded-full transition-all duration-75"
              style={{ width: `${duration > 0 ? (position / duration) * 100 : 0}%` }}
            />
            <div
              className="absolute top-1/2 -translate-y-1/2 w-3 h-3 bg-white rounded-full shadow-lg transform -translate-x-1/2 opacity-0 hover:opacity-100 transition-opacity pointer-events-none"
              style={{ left: `${duration > 0 ? (position / duration) * 100 : 0}%` }}
            />
          </div>
          <div className="flex justify-between text-[11px] text-white/60 mt-1 px-1">
            <span>{_time(position)}</span>
            <span>{_time(duration)}</span>
          </div>
        </div>

        {/* Main controls */}
        <div className="flex items-center justify-center gap-2 md:gap-4">
          <button
            onClick={() => onSeek(Math.max(0, position - 10))}
            className="p-2 rounded-xl hover:bg-white/10 transition-colors disabled:opacity-50"
            disabled={!canControl}
            aria-label="Rewind 10s"
          >
            <SkipBack className="w-5 h-5 text-white" />
          </button>

          <button
            onClick={onPlayPause}
            className="p-3 rounded-full bg-xynk-lime text-xynk-ink hover:bg-xynk-lime/90 transition-colors disabled:opacity-50"
            disabled={!canControl}
            aria-label={playing ? 'Pause' : 'Play'}
          >
            {playing ? <Pause className="w-6 h-6" /> : <Play className="w-6 h-6 ml-1" />}
          </button>

          <button
            onClick={() => onSeek(Math.min(duration, position + 10))}
            className="p-2 rounded-xl hover:bg-white/10 transition-colors disabled:opacity-50"
            disabled={!canControl}
            aria-label="Forward 10s"
          >
            <SkipForward className="w-5 h-5 text-white" />
          </button>

          <div className="flex items-center gap-1 ml-2 md:ml-4">
            <button
              onClick={onMute}
              className="p-2 rounded-xl hover:bg-white/10 transition-colors"
              aria-label={muted ? 'Unmute' : 'Mute'}
            >
              {muted || volume === 0 ? <VolumeX className="w-5 h-5 text-white" /> : <Volume2 className="w-5 h-5 text-white" />}
            </button>
            <input
              type="range"
              min={0}
              max={1}
              step={0.05}
              value={muted ? 0 : volume}
              onChange={(e) => handleVolumeChange(Number(e.target.value))}
              className="w-24 h-1.5 bg-white/20 rounded-full appearance-none cursor-pointer [&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:w-3 [&::-webkit-slider-thumb]:h-3 [&::-webkit-slider-thumb]:bg-white [&::-webkit-slider-thumb]:rounded-full"
              style={{ background: `linear-gradient(to right, #F1A0FF ${volume * 100}%, rgba(255,255,255,0.2) ${volume * 100}%)` }}
            />
          </div>

          <div className="flex items-center gap-1 ml-2">
            <select
              value={selectedQuality}
              onChange={(e) => onQualityChange(e.target.value)}
              className="px-2 py-1 bg-white/10 rounded-xl text-xs text-white border border-white/10 appearance-none cursor-pointer"
              disabled={qualities.length === 0}
            >
              <option value="auto">Auto</option>
              {qualities.map(q => <option key={q} value={q}>{q}</option>)}
            </select>

            <select
              value={selectedCaption}
              onChange={(e) => onCaptionChange(e.target.value)}
              className="px-2 py-1 bg-white/10 rounded-xl text-xs text-white border border-white/10 appearance-none cursor-pointer"
              disabled={Object.keys(captionLanguages).length === 0}
            >
              <option value="off">Off</option>
              {Object.entries(captionLanguages).map(([code, name]) => (
                <option key={code} value={code}>{name}</option>
              ))}
            </select>
          </div>
        </div>
      </div>

      {/* Settings dropdown */}
      {showSettings && (
        <div className="absolute bottom-[80px] right-2 pointer-events-auto z-10">
          <div className="bg-xynk-panel rounded-2xl border border-xynk-line p-3 min-w-[200px] shadow-xl">
            <div className="flex items-center justify-between mb-3">
              <h3 className="font-semibold text-white">Playback Settings</h3>
              <button onClick={() => setShowSettings(false)} className="p-1 rounded hover:bg-white/10">
                <svg className="w-5 h-5 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M18 6L6 18M6 6l12 12"/></svg>
              </button>
            </div>
            <div className="space-y-3">
              <div>
                <label className="block text-xs text-white/60 mb-1">Quality</label>
                <select
                  value={selectedQuality}
                  onChange={(e) => { onQualityChange(e.target.value); setShowSettings(false); }}
                  className="w-full px-3 py-2 bg-xynk-panelSoft rounded-xl text-sm text-white border border-xynk-line appearance-none cursor-pointer"
                >
                  <option value="auto">Auto</option>
                  {qualities.map(q => <option key={q} value={q}>{q}</option>)}
                </select>
              </div>
              <div>
                <label className="block text-xs text-white/60 mb-1">Captions</label>
                <select
                  value={selectedCaption}
                  onChange={(e) => { onCaptionChange(e.target.value); setShowSettings(false); }}
                  className="w-full px-3 py-2 bg-xynk-panelSoft rounded-xl text-sm text-white border border-xynk-line appearance-none cursor-pointer"
                >
                  <option value="off">Off</option>
                  {Object.entries(captionLanguages).map(([code, name]) => (
                    <option key={code} value={code}>{name}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-xs text-white/60 mb-1">Playback Speed</label>
                <select
                  value={1}
                  onChange={(e) => setShowSettings(false)}
                  className="w-full px-3 py-2 bg-xynk-panelSoft rounded-xl text-sm text-white border border-xynk-line appearance-none cursor-pointer"
                >
                  <option value="0.5">0.5x</option>
                  <option value="0.75">0.75x</option>
                  <option value="1">Normal</option>
                  <option value="1.25">1.25x</option>
                  <option value="1.5">1.5x</option>
                  <option value="2">2x</option>
                </select>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}