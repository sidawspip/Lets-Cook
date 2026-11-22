import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Send } from 'lucide-react';
import { api } from '../../services/api';
import { useWatchPartyStore } from '../../stores/watchPartyStore';

export function DirectChatScreen() {
  const {friendId} = useParams<{friendId: string}>();
  const navigate = useNavigate();
  const myId = useWatchPartyStore(state => state.profile?.id);
  const [messages, setMessages] = useState<any[]>([]);
  const [body, setBody] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [sending, setSending] = useState(false);

  useEffect(() => {
    if (!friendId) return;
    let active = true;
    const refresh = async () => {
      try { const next = await api.getDirectMessages(friendId); if (active) {setMessages(next); setError(null);} }
      catch (exception) { if (active) setError(String(exception)); }
    };
    void refresh();
    const timer = setInterval(() => void refresh(), 3000);
    return () => {active = false; clearInterval(timer);};
  }, [friendId]);

  const send = async () => {
    if (!friendId || !body.trim() || sending) return;
    setSending(true);
    try {
      await api.sendDirectMessage(friendId, body.trim());
      setBody('');
      setMessages(await api.getDirectMessages(friendId));
      setError(null);
    } catch (exception) {setError(String(exception));}
    finally {setSending(false);}
  };

  return <div className="h-screen flex flex-col bg-xynk-ink text-white">
    <header className="flex items-center gap-3 p-4 border-b border-xynk-line">
      <button onClick={() => navigate('/')} aria-label="Back"><ArrowLeft /></button>
      <strong>Chat</strong>
    </header>
    <main className="flex-1 overflow-y-auto p-4 space-y-2">
      {error && <p role="alert" className="text-red-300">{error}</p>}
      {messages.map(message => <div key={message.id} className={`max-w-[75%] rounded-2xl p-3 ${message.senderId === myId ? 'ml-auto bg-xynk-lime/25' : 'bg-xynk-panelSoft'}`}>
        {message.body}
      </div>)}
    </main>
    <form className="flex gap-2 p-3 border-t border-xynk-line" onSubmit={event => {event.preventDefault(); void send();}}>
      <input aria-label="Message" value={body} onChange={event => setBody(event.target.value)} className="flex-1 input-field" placeholder="Say something…" />
      <button className="btn-primary px-4" type="submit" disabled={sending || !body.trim()} aria-label="Send"><Send size={18}/></button>
    </form>
  </div>;
}
