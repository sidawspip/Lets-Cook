import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('xynkDesktop', {
  minimize: () => ipcRenderer.invoke('window:minimize'),
  maximize: () => ipcRenderer.invoke('window:maximize'),
  close: () => ipcRenderer.invoke('window:close'),
  isMaximized: () => ipcRenderer.invoke('window:isMaximized'),
  loginWithProvider: (provider: 'google' | 'x') => ipcRenderer.invoke('auth:identity-provider', provider),
  register: () => ipcRenderer.invoke('auth:register'),
  prepareCrunchyroll: (episodeId: string) => ipcRenderer.invoke('cr:prepare', episodeId),
  requestCrunchyrollLicense: (challenge: Uint8Array) => ipcRenderer.invoke('cr:license', challenge),
  resolveYouTube: (videoId: string, quality = 'auto') => ipcRenderer.invoke('youtube:resolve', videoId, quality),
  getScreenSources: () => ipcRenderer.invoke('screen:sources'),
  selectScreenSource: (sourceId: string) => ipcRenderer.invoke('screen:select', sourceId),
});
