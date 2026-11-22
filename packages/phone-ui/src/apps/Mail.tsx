import { useCallback, useEffect, useState } from 'react';
import { Icon } from '@veyl/ui';
import { api } from '../api';
import { AppHeader, usePhone } from '../App';
import { timeAgo } from '../types';

interface Mail { id: number; sender: string; subject: string; body: string; is_read: number; at: number }

export function MailApp() {
  const { toast } = usePhone();
  const [items, setItems] = useState<Mail[] | null>(null);
  const [open, setOpen] = useState<Mail | null>(null);
  const load = useCallback(async () => {
    const r = await api<Mail[]>('mailList');
    if (r.ok && r.data) setItems(r.data); else toast(r.message ?? 'Could not load mail', 'error');
  }, [toast]);
  useEffect(() => { void load(); }, [load]);

  if (open) {
    return (
      <div className="ph-appview">
        <AppHeader title="Mail" onBack={() => { setOpen(null); void load(); }}
          right={<button className="ph-icon-btn" aria-label="Delete" onClick={async () => { await api('mailDelete', open.id); setOpen(null); void load(); }}><Icon name="close" size="1rem" /></button>} />
        <div className="ph-body ml-read">
          <h3>{open.subject}</h3>
          <div className="muted">From {open.sender} · {timeAgo(open.at)}</div>
          <p>{open.body}</p>
        </div>
      </div>
    );
  }
  const unread = (items ?? []).filter((m) => !m.is_read).length;
  return (
    <div className="ph-appview">
      <AppHeader title={unread ? `Inbox (${unread})` : 'Inbox'} />
      <div className="ph-body">
        {items === null && <div className="ph-empty">Loading…</div>}
        {items?.length === 0 && <div className="ph-empty">No mail. Receipts, bills and offers arrive here.</div>}
        <ul className="ph-list">
          {items?.map((m) => (
            <li key={m.id}><button className={`ph-row${m.is_read ? '' : ' unread'}`} onClick={() => { setOpen(m); if (!m.is_read) void api('mailRead', m.id); }}>
              <span className={`ml-dot${m.is_read ? '' : ' on'}`} />
              <span className="ph-row-main"><strong>{m.sender}</strong><span>{m.subject}</span><span className="muted">{m.body.replace(/\s+/g, ' ').slice(0, 60)}</span></span>
              <span className="muted">{timeAgo(m.at)}</span>
            </button></li>
          ))}
        </ul>
      </div>
    </div>
  );
}
