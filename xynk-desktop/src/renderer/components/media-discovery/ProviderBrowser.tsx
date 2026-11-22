import { useEffect, useRef } from 'react';

export interface DetectedProviderVideo {
  pageUrl: string;
  title: string;
  thumbnail?: string;
}

const DETECT_VIDEO = `(() => {
  if (location.hostname.endsWith('crunchyroll.com') && !/^\\/watch\\/[A-Za-z0-9]+/.test(location.pathname)) return null;
  const video = Array.from(document.querySelectorAll('video')).find(element => {
    const rect = element.getBoundingClientRect();
    const episodePlayer = location.hostname.endsWith('crunchyroll.com') && /^\\/watch\\/[A-Za-z0-9]+/.test(location.pathname);
    return rect.width >= 240 && rect.height >= 135 && rect.bottom > 0 && rect.top < innerHeight &&
      (element.readyState >= 1 || element.currentTime > 0 || element.videoWidth >= 240 || episodePlayer);
  });
  if (!video) return null;
  const thumbnail = video.poster || document.querySelector('meta[property="og:image"]')?.content || '';
  const episodeTitle = location.hostname.endsWith('crunchyroll.com')
    ? [...document.querySelectorAll('h1,h2,h3')].map(element => (element.textContent || '').replace(/\\s+/g, ' ').trim()).find(value => /^E\\d+\\s*[–—-]\\s*\\S/i.test(value))
    : null;
  return {pageUrl: location.href, title: episodeTitle || document.title || 'Selected video', thumbnail};
})()`;

export function ProviderBrowser({url, temporary, onDetected, onNavigate, onLoad, onError, onReady}: {
  url: string;
  temporary?: boolean;
  onDetected: (video: DetectedProviderVideo | null) => void;
  onNavigate?: (url: string, guest: Electron.WebviewTag) => void;
  onLoad: () => void;
  onError: (error: string) => void;
  onReady?: (guest: Electron.WebviewTag | null) => void;
}) {
  const mount = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const container = mount.current;
    if (!container || !url) return;
    const guest = document.createElement('webview') as Electron.WebviewTag;
    guest.setAttribute('src', url);
    guest.setAttribute('partition', temporary ? 'xynk-web' : 'persist:xynk-provider');
    guest.setAttribute('allowpopups', '');
    guest.style.width = '100%';
    guest.style.height = '100%';
    container.replaceChildren(guest);
    onReady?.(guest);
    let checking = false;
    const inspect = async () => {
      if (checking) return;
      checking = true;
      try {
        const detected = await guest.executeJavaScript(DETECT_VIDEO) as DetectedProviderVideo | null;
        onDetected(detected);
      } catch { onDetected(null); }
      finally { checking = false; }
    };
    const loaded = () => { onLoad(); void inspect(); onNavigate?.(guest.getURL(), guest); };
    const failed = (event: Electron.DidFailLoadEvent) => {
      if (event.errorCode !== -3) onError('Provider page could not be opened');
    };
    guest.addEventListener('did-finish-load', loaded);
    guest.addEventListener('did-navigate', loaded);
    guest.addEventListener('did-navigate-in-page', loaded);
    guest.addEventListener('did-fail-load', failed);
    const timer = setInterval(() => { void inspect(); }, 1500);
    return () => {
      clearInterval(timer);
      guest.removeEventListener('did-finish-load', loaded);
      guest.removeEventListener('did-navigate', loaded);
      guest.removeEventListener('did-navigate-in-page', loaded);
      guest.removeEventListener('did-fail-load', failed);
      guest.remove();
      onReady?.(null);
    };
  }, [url, temporary]);
  return <div ref={mount} className="w-full flex-1 min-h-0 bg-black" />;
}
