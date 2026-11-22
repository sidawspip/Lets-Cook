import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Search, RefreshCw,UserPlus as PersonAdd,UserMinus as PersonRemove,UserRoundPlus as PersonAddAlt1, Check, X,MessageCircle as ChatBubbleOutline, MessageSquare, MoreVertical } from 'lucide-react';
import { useWatchPartyStore } from '../../stores/watchPartyStore';
import { api } from '../../services/api';
import { _publicDisplayName, _publicHandle, _watchTimeDetailed, _watchTime } from '../../lib/formatters';

export function FriendsScreen({ onClose }: { onClose: () => void }) {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [friendId, setFriendId] = useState('');
  const [friends, setFriends] = useState<any[]>([]);
  const [requests, setRequests] = useState<any[]>([]);

  useEffect(() => {
    load();
  }, []);

  async function load() {
    setLoading(true);
    try {
      const [loadedFriends, loadedRequests] = await Promise.all([
        api.getFriends(),
        api.getFriendRequests(),
      ]);
      setFriends(loadedFriends);
      setRequests(loadedRequests);
      setError(null);
    } catch (exception) {
      setError(String(exception));
    } finally {
      setLoading(false);
    }
  }

  async function decide(requestId: string, accept: boolean) {
    try {
      await api.decideFriendRequest(requestId, accept);
      await load();
    } catch (exception) { setError(String(exception)); }
  }

  async function openChat(friend: any) {
    navigate(`/chat/${friend.id}`);
  }

  async function openFriendProfile(friend: any) {
    navigate(`/profile/${friend.id}`);
  }

  async function sendFriendRequest(userId: string) {
    try {
      await api.sendFriendRequest(userId);
      setFriendId('');
      await load();
    } catch (exception) { setError(String(exception)); }
  }

  const normalizedQuery = query.trim().toLowerCase();
  const visibleFriends = normalizedQuery.length === 0
    ? friends
    : friends.filter((friend) => {
        const name = (friend.displayName || '').toString().toLowerCase();
        const handle = (friend.username || '').toString().toLowerCase();
        return name.includes(normalizedQuery) || handle.includes(normalizedQuery);
      });

  if (loading) return <LoaderFullScreen />;

  return (
    <div className="fixed inset-0 z-50 flex flex-col bg-xynk-ink">
      <header className="px-4 py-3 flex items-center justify-between border-b border-xynk-line bg-black/50">
        <button onClick={onClose} className="p-2 rounded-xl hover:bg-white/10 transition-colors">
          <svg className="w-6 h-6 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M18 6L6 18M6 6l12 12"/></svg>
        </button>
        <h1 className="font-black text-xl text-white mx-auto">Friends</h1>
        <button onClick={load} disabled={loading} className="p-2 rounded-xl hover:bg-white/10 transition-colors disabled:opacity-50">
          <RefreshCw className={`w-6 h-6 text-white ${loading ? 'animate-spin' : ''}`} />
        </button>
      </header>

      <main className="flex-1 overflow-y-auto p-4">
        {error && (
          <div className="mb-4 p-4 bg-red-500/20 border border-red-500/50 rounded-xl">
            <p className="text-red-300">{error}</p>
            <button onClick={load} className="mt-2 text-sm text-red-300 underline">Retry</button>
          </div>
        )}

        {/* Search */}
        <form className="mb-4 flex gap-2 max-w-xl mx-auto" onSubmit={event => {event.preventDefault(); if (friendId.trim()) void sendFriendRequest(friendId.trim());}}>
          <input value={friendId} onChange={event => setFriendId(event.target.value)} className="input-field flex-1" placeholder="Friend user ID" aria-label="Friend user ID" />
          <button type="submit" className="btn-primary px-4" disabled={!friendId.trim()}>Add friend</button>
        </form>
        <div className="mb-4">
          <div className="relative max-w-xl mx-auto">
            <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-white/60" />
            <input
              type="text"
              value={query}
              onChange={e => setQuery(e.target.value)}
              placeholder="Search friends"
              className="w-full px-12 py-3 pl-12 bg-white/10 rounded-2xl border border-white/20 focus:border-white/70 focus:ring-2 focus:ring-white/20 text-white placeholder:text-white/70"
            />
          </div>
        </div>

        {/* Requests */}
        {requests.length > 0 && (
          <div className="mb-6 space-y-2">
            <h3 className="text-xs font-black text-xynk-lime tracking-wider mb-3">REQUESTS ({requests.length})</h3>
            {requests.map((request) => (
              <div key={request.id} className="flex items-center gap-3 p-3 rounded-xl bg-xynk-panelSoft border border-xynk-line">
                <div className="relative w-10 h-10 rounded-full bg-xynk-panelSoft flex items-center justify-center">
                  <span className="text-xs font-bold text-white">{_publicDisplayName(request).charAt(0).toUpperCase()}</span>
                </div>
                <div className="flex-1">
                  <p className="font-medium text-white">{_publicDisplayName(request)}</p>
                  <p className="text-xs text-white/60">@{_publicHandle(request)}</p>
                </div>
                <div className="flex gap-2">
                  <button onClick={() => decide(request.id, true)} className="btn-ghost px-3 py-1 text-xs">
                    <Check className="w-4 h-4 mr-1" /> Accept
                  </button>
                  <button onClick={() => decide(request.id, false)} className="btn-ghost px-3 py-1 text-xs text-red-400">
                    <X className="w-4 h-4 mr-1" /> Decline
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}

        {/* Friends */}
        <div className="mb-4 flex items-center justify-between">
          <h3 className="text-xs font-black text-xynk-muted tracking-wider">FRIENDS ({visibleFriends.length})</h3>
        </div>

        {friends.length === 0 ? (
          <div className="text-center py-12 text-white/50">
            <PersonAdd className="w-16 h-16 mx-auto mb-4 text-white/30" />
            <p className="text-lg font-medium">Your circle starts here</p>
            <p className="text-white/50 mt-2">Accepted friends will appear here</p>
          </div>
        ) : visibleFriends.length === 0 ? (
          <div className="text-center py-8 text-white/50">
            <p>No friends match that search.</p>
          </div>
        ) : (
          <div className="space-y-2">
            {visibleFriends.map((friend) => (
              <FriendTile key={friend.id} friend={friend} onTap={() => openFriendProfile(friend)} onChat={() => openChat(friend)} />
            ))}
          </div>
        )}
      </main>
    </div>
  );
}

function FriendTile({ friend, onTap, onChat }: { friend: any; onTap: () => void; onChat: () => void }) {
  const name = _publicDisplayName(friend);
  const username = _publicHandle(friend);
  const avatar = friend.avatarUrl;
  const online = friend.online === true;
  const together = _watchTimeDetailed(friend.watchTogetherSeconds);

  return (
    <button onClick={onTap} className="w-full flex items-center gap-3 p-3 rounded-xl bg-xynk-panelSoft border border-xynk-line hover:bg-white/5 transition-colors text-left">
      <div className="relative w-10 h-10 rounded-full bg-gradient-to-br from-xynk-lime to-xynk-mint flex items-center justify-center flex-shrink-0">
        {avatar ? (
          <img src={avatar} alt="" className="w-full h-full rounded-full" />
        ) : (
          <span className="text-sm font-bold text-xynk-ink">{name.charAt(0).toUpperCase()}</span>
        )}
        {online && (
          <div className="absolute -bottom-1 -right-1 w-3 h-3 bg-xynk-mint rounded-full border-2 border-xynk-panel" />
        )}
      </div>
      <div className="flex-1 min-w-0">
        <p className="font-medium text-white truncate">{name}</p>
        <p className="text-xs text-white/60 truncate">@{username} · {together} together</p>
      </div>
      <button onClick={onChat} className="p-2 rounded-xl hover:bg-white/10 transition-colors" aria-label={`Chat with ${name}`}>
        <MessageSquare className="w-5 h-5 text-white/70" />
      </button>
    </button>
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
