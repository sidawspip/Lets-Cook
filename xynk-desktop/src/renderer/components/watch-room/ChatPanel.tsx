import { useState, useRef, useEffect } from 'react';
import { useWatchPartyStore } from '../../stores/watchPartyStore';
import { _time } from '../../lib/formatters';
import { MessageSquare, Reply, MoreHorizontal, Send, Mic, MicOff, Volume2, VolumeX, ScreenShare, Smile } from 'lucide-react';
import { MediaPreview } from '../ui/MediaPreview';
import type { ChatMessage, RoomWatchState } from '../../types/models';

const REACTIONS = ['❤️', '🔥', '😂', '😍', '👏', '😮', '😢', '👍'];

export function ChatPanel({ messages, state, onOpenVideo }: {messages: ChatMessage[]; state: RoomWatchState | null; onOpenVideo?: (message: ChatMessage) => void}) {
  const { replyToMessage, beginReply, cancelReply, sendMessage, reactToMessage,
    voice, voiceRevision, activeRoom, activeParticipants, profile, toggleMicrophone, toggleSpeaker, toggleScreenShare } = useWatchPartyStore();
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const [composer, setComposer] = useState('');
  const [showEmojis, setShowEmojis] = useState(false);
  const [sending, setSending] = useState(false);
  const [screenSources, setScreenSources] = useState<Array<{id: string; name: string; thumbnail: string}> | null>(null);
  const [sharingBusy, setSharingBusy] = useState(false);
  const [showActions, setShowActions] = useState<{ message: any; x: number; y: number } | null>(null);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const handleSend = async (text = composer) => {
    if (!text.trim() || sending) return;
    setSending(true);
    try {
      await sendMessage(text);
      setComposer('');
    } finally {
      setSending(false);
    }
  };

  const handleReply = (msg: any) => {
    beginReply(msg);
    setShowActions(null);
  };

  const handleAction = (msg: any, reaction: string) => {
    void reactToMessage(msg.id, reaction);
    setShowActions(null);
  };

  const openActions = (msg: any, e: React.MouseEvent) => {
    e.preventDefault();
    const rect = e.currentTarget.getBoundingClientRect();
    setShowActions({ message: msg, x: rect.right, y: rect.top });
  };

  useEffect(() => {
    const handleClick = (e: MouseEvent) => {
      if (showActions && !(e.target instanceof Element && e.target.closest('[data-actions]'))) {
        setShowActions(null);
      }
    };
    document.addEventListener('click', handleClick);
    return () => document.removeEventListener('click', handleClick);
  }, [showActions]);

  const scrollToBottom = () => messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  const handleScreenShare = async () => {
    if (voice.screenShareEnabled) { await toggleScreenShare(); return; }
    const me = activeParticipants.find(member => member.userId === profile?.id);
    if (activeRoom?.role !== 'HOST' && !me?.canShareScreen) { await toggleScreenShare(); return; }
    setScreenSources(await window.xynkDesktop.getScreenSources());
  };
  const startScreenShare = async (sourceId: string) => {
    setSharingBusy(true);
    try { await window.xynkDesktop.selectScreenSource(sourceId); await toggleScreenShare(); setScreenSources(null); }
    finally { setSharingBusy(false); }
  };

  return (
    <div className="flex flex-col h-full overflow-hidden">
      {/* Messages */}
      <div className="flex-1 overflow-y-auto p-3 space-y-3" onWheel={(e) => e.ctrlKey && scrollToBottom()}>
        {messages.map((msg) => (
          <MessageBubble
            key={msg.id}
            message={msg}
            isMine={msg.isMine}
            onReply={handleReply}
            onReact={handleAction}
            onActions={openActions}
            onOpenVideo={onOpenVideo}
          />
        ))}
        {!state && (
          <div className="text-center py-8 text-white/60">
            <MessageSquare className="w-12 h-12 mx-auto mb-3 text-white/30" />
            <p className="font-medium">No messages yet</p>
            <p className="text-xs text-white/40 mt-1">Be the first to say something</p>
          </div>
        )}
        <div ref={messagesEndRef} />
      </div>

      {/* Reactions dropdown */}
      {showActions && (
        <div
          className="fixed z-50 bg-xynk-panel rounded-2xl border border-xynk-line p-2 shadow-xl"
          style={{ left: showActions.x, top: showActions.y }}
          data-actions
        >
          <div className="flex gap-1 mb-2">
            {REACTIONS.map(r => (
              <button
                key={r}
                onClick={() => handleAction(showActions.message, r)}
                className="text-2xl p-1 hover:bg-white/10 rounded"
              >
                {r}
              </button>
            ))}
          </div>
          <button
            onClick={() => handleReply(showActions.message)}
            className="w-full flex items-center gap-2 px-3 py-2 hover:bg-white/10 rounded-xl text-left"
          >
            <svg className="w-5 h-5 text-white/70" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M9 18l6-6-6-6"/></svg>
            <span className="text-white">Reply</span>
          </button>
          {!showActions.message.isMine && (
            <button
              onClick={() => handleReply(showActions.message)}
              className="w-full flex items-center gap-2 px-3 py-2 hover:bg-white/10 rounded-xl text-left"
            >
              <MoreHorizontal className="w-5 h-5 text-white/70" />
              <span className="text-white">Reply & tag @{showActions.message.senderUsername}</span>
            </button>
          )}
        </div>
      )}

      {/* Reply bar */}
      {replyToMessage && (
        <div className="p-3 bg-xynk-panelSoft/80 border-t border-xynk-line flex items-center gap-3">
          <svg className="w-5 h-5 text-xynk-mint" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M9 18l6-6-6-6"/></svg>
          <div className="flex-1 min-w-0">
            <p className="text-xs font-medium text-xynk-mint">Replying to {replyToMessage.senderName}</p>
            <p className="text-xs text-white/60 truncate">{replyToMessage.body}</p>
          </div>
          <button onClick={cancelReply} className="p-1 rounded hover:bg-white/10">
            <svg className="w-5 h-5 text-white/60" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M18 6L6 18M6 6l12 12"/></svg>
          </button>
        </div>
      )}

      {/* Composer */}
      <div className="p-3 bg-black/50 border-t border-xynk-line flex items-end gap-2">
        <div className="flex items-center gap-1">
          <button onClick={() => void toggleMicrophone()} className="p-2 rounded-xl hover:bg-white/10 transition-colors" aria-label={voice.microphoneEnabled ? 'Mute microphone' : 'Turn on microphone'}>
            {voice.microphoneEnabled ? <Mic className="w-5 h-5 text-xynk-lime" /> : <MicOff className="w-5 h-5 text-white" />}
          </button>
          <button onClick={() => void toggleSpeaker()} className="p-2 rounded-xl hover:bg-white/10 transition-colors" aria-label={voice.speakerEnabled ? 'Mute room voices' : 'Hear room voices'}>
            {voice.speakerEnabled ? <Volume2 className="w-5 h-5 text-xynk-lime" /> : <VolumeX className="w-5 h-5 text-white" />}
          </button>
          <button className="p-2 rounded-xl hover:bg-white/10 transition-colors" aria-label="Emoji">
            <Smile className="w-5 h-5 text-white" onClick={() => setShowEmojis(!showEmojis)} />
          </button>
          <button onClick={() => void handleScreenShare()} className="p-2 rounded-xl hover:bg-white/10 transition-colors" aria-label={voice.screenShareEnabled ? 'Stop screen share' : 'Share screen'}>
            <ScreenShare className={`w-5 h-5 ${voice.screenShareEnabled ? 'text-xynk-lime' : 'text-white'}`} />
          </button>
        </div>

        <textarea
          ref={inputRef}
          value={composer}
          onChange={(e) => setComposer(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault();
              handleSend();
            }
          }}
          placeholder="Say something…"
          className="flex-1 min-h-[44px] max-h-32 px-4 py-2 bg-xynk-panelSoft rounded-2xl text-white placeholder:text-white/40 resize-none focus:outline-none"
          rows={1}
        />

        {showEmojis && (
          <div className="absolute bottom-full left-12 right-12 mb-2 p-2 bg-xynk-panel rounded-2xl border border-xynk-line flex gap-1 overflow-x-auto">
            {REACTIONS.map(r => (
              <button
                key={r}
              onClick={() => { setShowEmojis(false); void handleSend(r); }}
                className="text-2xl p-1 hover:bg-white/10 rounded"
              >
                {r}
              </button>
            ))}
          </div>
        )}

        <button
          onClick={() => void handleSend()}
          disabled={!composer.trim() || sending}
          className="p-3 rounded-full bg-xynk-lime text-xynk-ink hover:bg-xynk-lime/90 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex-shrink-0"
          aria-label="Send"
        >
          {sending ? (
            <svg className="w-5 h-5 animate-spin" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="10" strokeLinecap="round" strokeDasharray="31.4 31.4"/></svg>
          ) : (
            <Send className="w-5 h-5" />
          )}
        </button>
      </div>
      {screenSources && <div className="fixed inset-0 z-50 bg-black/80 p-6 flex items-center justify-center" role="dialog" aria-label="Choose screen or app window">
        <div className="w-full max-w-3xl max-h-[85vh] overflow-y-auto rounded-2xl bg-xynk-panel p-5 text-white">
          <div className="flex justify-between items-center mb-4"><h2 className="font-bold text-lg">Choose what to share</h2><button onClick={() => setScreenSources(null)} aria-label="Cancel screen share">✕</button></div>
          <div className="grid grid-cols-2 md:grid-cols-3 gap-3">{screenSources.map(source => <button key={source.id} disabled={sharingBusy} onClick={() => void startScreenShare(source.id)} className="rounded-xl overflow-hidden border border-xynk-line bg-black/30 text-left hover:border-xynk-lime"><img src={source.thumbnail} alt="" className="w-full aspect-video object-contain bg-black"/><span className="block p-2 text-xs truncate">{source.name}</span></button>)}</div>
        </div>
      </div>}
    </div>
  );
}

function MessageBubble({ message, isMine, onReply, onReact, onActions, onOpenVideo }: any) {
  if (message.type === 'VIDEO' && message.mediaId) {
    return <button type="button" onClick={() => onOpenVideo?.(message)} className="w-full flex items-center gap-3 p-3 rounded-2xl bg-xynk-panelSoft/80 border border-xynk-line text-left text-white hover:bg-white/10">
      <MediaPreview mediaId={message.mediaId} provider={message.mediaProvider || 'WEB'} contentLabel={message.mediaTitle || message.body || 'Video'} className="w-24 h-14 rounded-lg flex-shrink-0" />
      <div className="min-w-0 flex-1"><p className="text-xs text-xynk-mint">Now playing on {message.mediaProvider || 'Web'}</p><p className="text-sm font-semibold line-clamp-2">{message.mediaTitle || message.body || 'Video'}</p><p className="text-[10px] text-white/50 mt-1">{message.senderName}</p></div><span aria-hidden="true">→</span>
    </button>;
  }
  return (
    <div className={`flex ${isMine ? 'justify-end' : 'justify-start'}`}>
      <div
        className={`relative max-w-[75%] px-4 py-2.5 rounded-2xl ${
          isMine
            ? 'bg-xynk-lime/20 text-white rounded-bl-none'
            : 'bg-xynk-panelSoft text-white rounded-br-none'
        }`}
        onContextMenu={(event) => onActions(message, event)}
        onClick={() => onReply(message)}
      >
        {!isMine && (
          <p className="text-xs font-medium text-xynk-mint mb-1">{message.senderName}</p>
        )}
        <p className="whitespace-pre-wrap break-words">{message.body}</p>
        <div className="flex items-center gap-1 mt-1">
          <span className="text-[10px] text-white/50">{new Date(message.createdAt).toLocaleTimeString([], {hour: '2-digit', minute: '2-digit'})}</span>
          {message.reactions.length > 0 && (
            <span className="flex gap-1">
              {message.reactions.map((r: any) => (
                <span key={r.reaction} className="text-xs">{r.reaction} {r.count}</span>
              ))}
            </span>
          )}
        </div>
      </div>
    </div>
  );
}
