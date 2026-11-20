import { useEffect } from 'react';
import { toneColor, toneIcon, type NotifyMessage } from '@veyl/ui';

function Toast({ n, onDone }: { n: NotifyMessage; onDone: (id: string) => void }) {
  useEffect(() => {
    const t = setTimeout(() => onDone(n.id), Math.max(1500, Math.min(n.duration, 15000)));
    return () => clearTimeout(t);
  }, [n.id, n.duration, onDone]);
  return (
    <div className="toast v-panel" style={{ borderLeftColor: toneColor[n.type] }} role="status">
      <span className="toast-icon" style={{ color: toneColor[n.type] }}>{toneIcon[n.type]}</span>
      <div>
        {n.title && <div className="toast-title">{n.title}</div>}
        <div className="toast-msg">{n.message}</div>
      </div>
    </div>
  );
}

export function Notifications({ items, onDone }: { items: NotifyMessage[]; onDone: (id: string) => void }) {
  return (
    <div className="toasts">
      {items.map((n) => <Toast key={n.id} n={n} onDone={onDone} />)}
    </div>
  );
}
