import { useWatchPartyStore } from '../../stores/watchPartyStore';
import { MediaPreview } from '../ui/MediaPreview';
import { _time } from '../../lib/formatters';
import { Users,MousePointerClick as TouchApp,Vote as HowToVote,Plus as Add} from 'lucide-react';
import { QueueItem } from '../../types/models';

export function QueuePanel() {
  const { roomQueue, personalQueue, selectQueueItem, voteQueueItem, setShelfOpen, canControlWatch } = useWatchPartyStore();

  return (
    <div className="p-3 space-y-4">
      {roomQueue.length > 0 && (
        <div>
          <h3 className="text-xs font-black text-xynk-lime tracking-wider mb-3">UP NEXT · VOTE</h3>
          <div className="space-y-2">
            {roomQueue.map((item) => (
              <QueueRow
                key={item.id}
                item={item}
                onTap={canControlWatch ? () => selectQueueItem(item) : undefined}
                showVote={true}
                onVote={() => voteQueueItem(item.id)}
              />
            ))}
          </div>
        </div>
      )}

      {roomQueue.length === 0 && personalQueue.length === 0 && (
        <div className="text-center py-8 text-white/60">
          <svg className="w-12 h-12 mx-auto mb-3 text-white/30" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 5v14M5 12h14"/></svg>
          <p>No videos in queue</p>
          <p className="text-xs text-white/40 mt-1">Add a video to get started</p>
        </div>
      )}

      {personalQueue.length > 0 && (
        <div>
          <h3 className="text-xs font-black text-xynk-muted tracking-wider mb-3">YOUR QUEUE</h3>
          <div className="space-y-2">
            {personalQueue.map((item, index) => (
              <QueueRow
                key={item.id}
                item={item}
                onTap={canControlWatch && index === 0 ? () => selectQueueItem(item) : undefined}
                showVote={false}
                position={index + 1}
              />
            ))}
          </div>
        </div>
      )}

      <button onClick={() => setShelfOpen(true)} className="btn-secondary w-full mt-4">
        <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 5v14M5 12h14"/></svg>
        Find another video
      </button>
    </div>
  );
}

function QueueRow({
  item,
  onTap,
  showVote,
  onVote,
  position,
}: {
  item: QueueItem;
  onTap?: () => void;
  showVote: boolean;
  onVote?: () => void;
  position?: number;
}) {
  return (
    <div
      className={`w-full text-left p-2 rounded-xl transition-colors ${
        onTap ? 'hover:bg-white/5' : ''
      }`}
    >
      <div className="flex items-center gap-3">
        <MediaPreview
          mediaId={item.mediaId}
          provider={item.provider}
          thumbnailUrl={item.thumbnailUrl}
          contentLabel={item.title}
          className="w-14 h-8 rounded flex-shrink-0"
        />
        <button type="button" onClick={onTap} disabled={!onTap} className="flex-1 min-w-0 text-left disabled:cursor-default">
          <p className="font-medium text-sm truncate text-white">{item.title}</p>
          <p className="text-xs text-white/60 truncate">
            {showVote
              ? `${item.voteCount} picks · ${item.addedByName}`
              : position
              ? `Waiting · #${position} in your queue`
              : `${item.addedByName} · ${item.voteCount} picks`}
          </p>
        </button>
        <div className="flex items-center gap-2">
          {showVote && (
            <button className="p-1 rounded hover:bg-white/10 transition-colors" onClick={() => onVote?.()} aria-label={item.votedByMe ? 'Remove vote' : 'Vote for video'}>
              {item.votedByMe ? <svg className="w-5 h-5 text-xynk-lime" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 22c5.523 0 10-4.477 10-10S17.523 2 12 2 2 6.477 2 12s4.477 10 10 10z"/><path d="M9 12l2 2 4-4"/></svg> : <svg className="w-5 h-5 text-white/60" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 5v14M5 12h14"/></svg>}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
