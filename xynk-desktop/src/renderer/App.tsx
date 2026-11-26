import { Routes, Route, Navigate, useParams } from 'react-router-dom';
import { useEffect } from 'react';
import { useWatchPartyStore } from './stores/watchPartyStore';
import { HomeScreen } from './components/home/HomeScreen';
import { DirectChatScreen } from './components/home/DirectChatScreen';
import { LoginScreen } from './components/auth/LoginScreen';
import { WatchRoomScreen } from './components/watch-room/WatchRoomScreen';
import { UserProfileScreen } from './components/profile/UserProfileScreen';
import { MediaDiscoveryScreen } from './components/media-discovery/MediaDiscoveryScreen';
import { WaveLoader } from './components/ui/WaveLoader';
import { LogoMark } from './components/ui/LogoMark';
import { Minus, Square, X } from 'lucide-react';

function DesktopFrame({ children }: { children: React.ReactNode }) {
  return <div className="desktop-shell">
    <div className="desktop-titlebar">
      <div className="desktop-titlebar-brand"><LogoMark size={17} /><span>XYNK</span></div>
      <div className="desktop-window-actions">
        <button aria-label="Minimize window" title="Minimize" onClick={() => void window.xynkDesktop.minimize()}><Minus size={15} /></button>
        <button aria-label="Maximize window" title="Maximize or restore" onClick={() => void window.xynkDesktop.maximize()}><Square size={12} /></button>
        <button className="desktop-window-close" aria-label="Close window" title="Close" onClick={() => void window.xynkDesktop.close()}><X size={16} /></button>
      </div>
    </div>
    <div className="desktop-content">{children}</div>
  </div>;
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

function ProfileRoute() {
  const { userId } = useParams<{ userId: string }>();
  return userId ? <UserProfileScreen userId={userId} /> : <Navigate to="/" replace />;
}

export default function App() {
  const { initialize, initializing, authenticated, activeRoom } = useWatchPartyStore();

  useEffect(() => {
    initialize();
  }, [initialize]);

  if (initializing) return <DesktopFrame><LaunchScreen /></DesktopFrame>;

  return (
    <DesktopFrame><Routes>
      <Route path="/login" element={<LoginScreen />} />
      <Route
        path="/"
        element={
          authenticated ? (
            activeRoom ? <WatchRoomScreen /> : <HomeScreen />
          ) : (
            <Navigate to="/login" replace />
          )
        }
      />
      <Route
        path="/profile/:userId"
        element={<ProfileRoute />}
      />
      <Route path="/chat/:friendId" element={authenticated ? <DirectChatScreen /> : <Navigate to="/login" replace />} />
      <Route
        path="/discover"
        element={<MediaDiscoveryScreen />}
      />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes></DesktopFrame>
  );
}
