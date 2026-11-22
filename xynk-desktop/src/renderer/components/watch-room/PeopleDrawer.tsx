import { X } from 'lucide-react';
import { PeoplePanel } from './PeoplePanel';

export function PeopleDrawer({ onClose, activeRoom }: { onClose: () => void; activeRoom: {id: string; role: string; viewerCount: number} | null }) {
  if (!activeRoom) return null;
  return <div className="fixed inset-0 z-50 flex flex-row-reverse">
    <button className="absolute inset-0 bg-black/50" onClick={onClose} aria-label="Close people" />
    <div className="relative w-full md:w-96 bg-xynk-panel border-l border-xynk-line flex flex-col">
      <header className="flex items-center justify-between p-4 border-b border-xynk-line"><h2 className="text-lg font-bold text-white">People</h2><button onClick={onClose} className="p-2 rounded-xl hover:bg-white/10" aria-label="Close"><X className="w-5 h-5 text-white" /></button></header>
      <div className="flex-1 min-h-0 overflow-y-auto p-4"><PeoplePanel room={activeRoom} /></div>
    </div>
  </div>;
}
