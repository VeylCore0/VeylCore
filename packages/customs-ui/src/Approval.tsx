import { useState } from 'react';
import { Icon } from '@veyl/ui';
import { api, money, type Line } from './lib';
import type { Toast } from './App';

interface Quote { id: number; shopLabel: string; model: string; plate: string; mechanic?: string; version: number; note?: string; lines: Line[]; subtotal: number; labor: number; tax: number; total: number }

/** The customer reviews the exact quote version a mechanic sent, then approves (and pays) or rejects it. */
export function Approval({ data, say, close }: { data: { quotes: Quote[]; methods: string[] }; say: Toast; close: () => void }) {
  const [quotes, setQuotes] = useState(data.quotes);
  const [method, setMethod] = useState(data.methods[0] ?? 'bank');
  const [busy, setBusy] = useState(false);
  const q = quotes[0];
  const act = async (name: 'approve' | 'reject') => {
    setBusy(true);
    const r = name === 'approve' ? await api(name, q.id, q.version, method) : await api(name, q.id, q.version);
    setBusy(false);
    say(r.message ?? (r.ok ? 'Done' : 'Failed'), !r.ok);
    if (r.ok || r.code === 'STALE' || r.code === 'EXPIRED') { const rest = quotes.slice(1); if (rest.length) setQuotes(rest); else close(); }
  };
  if (!q) return null;
  return (
    <div className="modal-back" onKeyDown={(e) => { if (e.key === 'Escape') close(); }}>
      <div className="modal" role="dialog" aria-label="Quote approval" style={{ width: 'min(520px, 94vw)' }}>
        <div className="wordmark"><b>VEYL</b><i>/</i><span>CUSTOMS</span></div>
        <div className="pane" style={{ width: 'auto', padding: 0, background: 'none', border: 0 }}>
          <div className="eyebrow" style={{ marginTop: 20 }}>QUOTE #{q.id} · VERSION {q.version}</div>
          <h2>{q.model.toUpperCase()}</h2>
          <div className="cust">{q.shopLabel} · {q.plate}{q.mechanic ? ` · ${q.mechanic}` : ''}</div>
          {q.note && <p className="note">{q.note}</p>}
          {q.lines.map((l) => <div className="line" key={l.id}><span>{l.label}</span><b>{money(l.price)}</b></div>)}
          {q.labor > 0 && <div className="sum"><span>Labour</span><span>{money(q.labor)}</span></div>}
          {q.tax > 0 && <div className="sum"><span>Tax</span><span>{money(q.tax)}</span></div>}
          <div className="sum big"><span>Total</span><span>{money(q.total)}</span></div>
          <p className="note">You pay when you approve. If the order is cancelled, everything not yet installed is refunded (with its share of labour and tax).</p>
          <div className="sub">Pay with</div>
          <div className="chips">{data.methods.map((m) => <button key={m} className={`chip${method === m ? ' on' : ''}`} onClick={() => setMethod(m)}>{m === 'bank' ? 'Card' : 'Cash'}</button>)}</div>
          <div className="actions">
            <button className="btn primary" disabled={busy} onClick={() => void act('approve')}><Icon name="check" size="1em" /> Approve and pay {money(q.total)}</button>
            <button className="btn danger" disabled={busy} onClick={() => void act('reject')}>Reject</button>
            <button className="btn ghost" onClick={close}>Later</button>
          </div>
        </div>
      </div>
    </div>
  );
}
