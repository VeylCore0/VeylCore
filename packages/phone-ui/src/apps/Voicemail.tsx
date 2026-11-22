import { useCallback, useEffect, useState } from 'react';
import { Icon } from '@veyl/ui';
import { api } from '../api';
import { AppHeader, usePhone } from '../App';
import { fmtNumber, timeAgo } from '../types';

interface Voicemail { id: number; from_number: string; from_name?: string; body: string; is_read: number; at: number }

export function VoicemailApp() {
  const { toast } = usePhone();
  const [items, setItems] = useState<Voicemail[] | null>(null);
  const [leaving, setLeaving] = useState(false);
  const [number, setNumber] = useState('');
  const [text, setText] = useState('');
  const load = useCallback(async () => {
    const r = await api<Voicemail[]>('voicemailList');
    if (r.ok && r.data) setItems(r.data); else toast(r.message ?? 'Could not load voicemail', 'error');
  }, [toast]);
  useEffect(() => { void load(); }, [load]);

  if (leaving) {
    return (
      <div className="ph-appview">
        <AppHeader title="Leave a voicemail" onBack={() => setLeaving(false)} />
        <div className="ph-body ph-form">
          <label>Their number<input inputMode="numeric" maxLength={12} value={number} onChange={(e) => setNumber(e.target.value)} /></label>
          <label>Message<textarea rows={5} maxLength={500} value={text} onChange={(e) => setText(e.target.value)} placeholder="Hey, it's me. Call me back when you can." /></label>
          <button className="ph-btn wide" disabled={text.trim().length < 2 || number.replace(/\D/g, '').length < 7}
            onClick={async () => { const r = await api('voicemailLeave', number, text); toast(r.message ?? '', r.ok ? undefined : 'error'); if (r.ok) { setLeaving(false); setText(''); } }}>
            <Icon name="send" size="0.9rem" /> Leave voicemail
          </button>
        </div>
      </div>
    );
  }
  return (
    <div className="ph-appview">
      <AppHeader title="Voicemail" right={<button className="ph-icon-btn" aria-label="Leave a voicemail" onClick={() => setLeaving(true)}><Icon name="edit" size="1rem" /></button>} />
      <div className="ph-body">
        {items === null && <div className="ph-empty">Loading…</div>}
        {items?.length === 0 && <div className="ph-empty">No voicemail.</div>}
        <ul className="ph-list">
          {items?.map((v) => (
            <li key={v.id} className={`vm-item${v.is_read ? '' : ' unread'}`} onClick={() => { if (!v.is_read) { void api('voicemailRead', v.id); setItems((l) => l?.map((x) => x.id === v.id ? { ...x, is_read: 1 } : x) ?? null); } }}>
              <div className="vm-head"><strong>{v.from_name || fmtNumber(v.from_number)}</strong><span className="muted">{timeAgo(v.at)}</span>
                <button className="ph-icon-btn" aria-label="Delete" onClick={async (e) => { e.stopPropagation(); await api('voicemailDelete', v.id); void load(); }}><Icon name="close" size="0.85rem" /></button></div>
              <p>“{v.body}”</p>
              <button className="ph-link" onClick={(e) => { e.stopPropagation(); setNumber(v.from_number); setText(''); setLeaving(true); }}>Reply with a voicemail</button>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
