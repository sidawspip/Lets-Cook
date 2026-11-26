import { create } from 'zustand';
import { applyTheme, getTheme, readTheme, THEME_KEY } from '../themes/appearance';

interface UIState {
  themeId: string;
  setThemeId: (id: string) => void;
  isProfileSheetOpen: boolean;
  setProfileSheetOpen: (open: boolean) => void;
  isFriendsOpen: boolean;
  setFriendsOpen: (open: boolean) => void;
  discoveryQuery: string | null;
  setDiscoveryQuery: (query: string | null) => void;
  isFullscreen: boolean;
  setFullscreen: (v: boolean) => void;
  controlsVisible: boolean;
  setControlsVisible: (v: boolean) => void;
  playbackRate: number;
  setPlaybackRate: (r: number) => void;
  volume: number;
  setVolume: (v: number) => void;
  muted: boolean;
  setMuted: (v: boolean) => void;
  quality: string;
  setQuality: (q: string) => void;
  caption: string;
  setCaption: (c: string) => void;
}

export const useUIStore = create<UIState>((set) => ({
  themeId: readTheme(),
  setThemeId: (id) => {
    const themeId = getTheme(id).id;
    applyTheme(themeId);
    try { localStorage.setItem(THEME_KEY, themeId); } catch { /* Session selection still works when storage is unavailable. */ }
    set({ themeId });
  },
  isProfileSheetOpen: false,
  setProfileSheetOpen: (open) => set({ isProfileSheetOpen: open }),
  isFriendsOpen: false,
  setFriendsOpen: (open) => set({ isFriendsOpen: open }),
  discoveryQuery: null,
  setDiscoveryQuery: (query) => set({ discoveryQuery: query }),
  isFullscreen: false,
  setFullscreen: (v) => set({ isFullscreen: v }),
  controlsVisible: true,
  setControlsVisible: (v) => set({ controlsVisible: v }),
  playbackRate: 1,
  setPlaybackRate: (r) => set({ playbackRate: r }),
  volume: 0.82,
  setVolume: (v) => set({ volume: v }),
  muted: false,
  setMuted: (v) => set({ muted: v }),
  quality: 'auto',
  setQuality: (q) => set({ quality: q }),
  caption: 'off',
  setCaption: (c) => set({ caption: c }),
}));