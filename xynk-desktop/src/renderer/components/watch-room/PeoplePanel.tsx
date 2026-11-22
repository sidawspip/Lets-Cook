import { useEffect, useState } from 'react';
import { Mic, MicOff, ScreenShare, UserMinus, UserPlus, Volume2, VolumeX } from 'lucide-react';
import { useWatchPartyStore } from '../../stores/watchPartyStore';
import { api } from '../../services/api';

export function PeoplePanel({ room }: { room: {id: string; role: string; viewerCount: number} }) {
  const { voice, activeParticipants, profile, setError } = useWatchPartyStore();
  const [inviteId, setInviteId] = useState('');
  const [status, setStatus] = useState('');
  const [busy, setBusy] = useState(false);
  const [friends, setFriends] = useState<Array<{id: string; displayName?: string; username?: string}>>([]);
  useEffect(() => { void api.getFriends().then(setFriends).catch(() => {}); }, []);
  const isHost = room.role === 'HOST';
  const run = async (action: () => Promise<unknown>) => {
    setBusy(true); setStatus('');
    try { await action(); setStatus('Saved'); }
    catch (error) { setError(String(error)); setStatus(String(error)); }
    finally { setBusy(false); }
  };
  return <div className="flex flex-col h-full gap-5 text-white">
    <section>
      <h3 className="text-xs font-black text-xynk-lime tracking-wider mb-3">VOICE · {voice.members.filter(m => m.microphoneOn).length}</h3>
      {voice.members.filter(m => m.microphoneOn).map(member => <div key={member.identity} className="flex items-center gap-2 rounded-xl bg-white/5 p-2 mb-2">
        <span className={`w-9 h-9 rounded-full flex items-center justify-center border-2 ${member.speaking ? 'border-xynk-lime animate-pulse' : 'border-white/20'}`}>{member.name.charAt(0).toUpperCase()}</span>
        <span className="flex-1 truncate text-sm">{member.name}</span>
        {member.identity !== voice.localIdentity && <button title="Toggle this person's audio" onClick={() => voice.toggleListeningTo(member.identity)} className="p-2 rounded-lg hover:bg-white/10">{voice.isListeningTo(member.identity) ? <Volume2 size={17}/> : <VolumeX size={17}/>}</button>}
      </div>)}
    </section>
    <section className="flex-1 overflow-y-auto">
      <h3 className="text-xs font-black text-xynk-muted tracking-wider mb-3">ROOM MEMBERS · {activeParticipants.length}</h3>
      {activeParticipants.map(member => {
        const manage = member.userId !== profile?.id && (isHost || (room.role === 'CO_HOST' && member.role === 'MEMBER'));
        return <div key={member.userId} className="rounded-xl bg-white/5 p-3 mb-2">
          <div className="flex items-center gap-2"><span className="w-9 h-9 rounded-full bg-xynk-panelSoft flex items-center justify-center font-bold">{(member.displayName || member.username || '?').charAt(0).toUpperCase()}</span><div className="min-w-0 flex-1"><p className="text-sm truncate">{member.displayName || member.username}</p><p className="text-xs text-white/50">{member.role}</p></div>{member.screenShareRequested && <span className="text-xs text-yellow-300">Share requested</span>}{member.videoAccessRequested && <span className="text-xs text-yellow-300">Video requested</span>}</div>
          {manage && <div className="flex flex-wrap gap-1 mt-2">
            {isHost && <>
              <button disabled={busy} onClick={() => void run(() => api.hostMicAction(room.id, member.userId, 'MUTE'))} title="Mute microphone" className="p-2 rounded-lg hover:bg-white/10"><MicOff size={17}/></button>
              <button disabled={busy} onClick={() => void run(() => api.hostMicAction(room.id, member.userId, 'REQUEST_UNMUTE'))} title="Ask to unmute" className="p-2 rounded-lg hover:bg-white/10"><Mic size={17}/></button>
              <button disabled={busy} onClick={() => void run(() => api.setScreenPermission(room.id, member.userId, !member.canShareScreen))} title={member.canShareScreen ? 'Revoke screen sharing' : 'Allow screen sharing'} className="p-2 rounded-lg hover:bg-white/10"><ScreenShare size={17}/></button>
              <button disabled={busy} onClick={() => void run(() => api.updateVideoPermission(room.id, member.userId, !member.canAddVideos))} title="Toggle video selection" className="p-2 rounded-lg hover:bg-white/10">Video {member.canAddVideos ? '✓' : '+'}</button>
              <button disabled={busy} onClick={() => void run(() => api.updateVideoAccess(room.id, member.userId, !member.canViewVideo))} title="Toggle viewing access" className="p-2 rounded-lg hover:bg-white/10">View {member.canViewVideo ? '✓' : '+'}</button>
            </>}
            <button disabled={busy} onClick={() => void run(() => api.kickRoomMember(room.id, member.userId))} title="Remove from room" className="p-2 rounded-lg hover:bg-white/10 text-red-300"><UserMinus size={17}/></button>
            {isHost && member.role !== 'HOST' && <>
              <button disabled={busy} onClick={() => void run(() => api.setRoomLeadership(room.id, member.userId, member.role === 'CO_HOST' ? 'MEMBER' : 'CO_HOST'))} className="px-2 text-xs rounded-lg hover:bg-white/10">{member.role === 'CO_HOST' ? 'Remove co-host' : 'Make co-host'}</button>
              <button disabled={busy} onClick={() => { if (window.confirm(`Transfer room ownership to ${member.displayName || member.username}?`)) void run(() => api.setRoomLeadership(room.id, member.userId, 'TRANSFER')); }} className="px-2 text-xs rounded-lg hover:bg-white/10">Make host</button>
            </>}
          </div>}
        </div>;
      })}
    </section>
    <section className="border-t border-xynk-line pt-3">
      <label htmlFor="invite-user" className="text-xs font-black text-xynk-muted tracking-wider">INVITE FRIEND</label>
      <div className="flex gap-2 mt-2"><input id="invite-user" value={inviteId} onChange={e => setInviteId(e.target.value)} placeholder="Friend's user ID" className="input-field flex-1 min-w-0 text-sm"/><button disabled={!inviteId.trim() || busy} onClick={() => void run(async () => { await api.inviteUserToRoom(room.id, inviteId.trim()); setInviteId(''); })} className="btn-secondary" title="Invite"><UserPlus size={18}/></button></div>
      <div className="max-h-28 overflow-y-auto mt-2 space-y-1">{friends.filter(friend => !inviteId || `${friend.displayName} ${friend.username}`.toLowerCase().includes(inviteId.toLowerCase())).slice(0, 5).map(friend => <button key={friend.id} disabled={busy} onClick={() => void run(() => api.inviteUserToRoom(room.id, friend.id))} className="w-full flex items-center justify-between px-2 py-1 rounded-lg text-sm hover:bg-white/10"><span className="truncate">{friend.displayName || friend.username}</span><UserPlus size={15}/></button>)}</div>
      {status && <p role="status" className="text-xs text-white/60 mt-2">{status}</p>}
    </section>
  </div>;
}
