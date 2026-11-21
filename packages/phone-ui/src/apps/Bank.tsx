import { useCallback, useEffect, useState } from 'react';
import { Icon } from '@veyl/ui';
import { api, newClientOp } from '../api';
import { AppHeader, usePhone } from '../App';
import { fmtNumber, type Contact } from '../types';

interface Row { id: string; type: string; delta: number; balance: number; reason: string; at: number | string }
interface Overview { name: string; bank: number; cash: number; account: string; accountMasked: string; recent: Row[]; max: number }
type View = { kind: 'home' } | { kind: 'history' } | { kind: 'send' };

const money = (n: number) => `${n < 0 ? '-' : ''}$${Math.abs(n).toLocaleString('en-US')}`;
const when = (at: number | string) => {
  const d = typeof at === 'number' ? new Date(at * 1000) : new Date(String(at).replace(' ', 'T'));
  return Number.isNaN(d.getTime()) ? '' : d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
};

function Activity({ rows }: { rows: Row[] }) {
  if (!rows.length) return <div className="ph-empty">No activity yet.</div>;
  return (
    <ul className="ph-list">
      {rows.map((r) => (
        <li key={r.id} className="bk-row">
          <span className={`bk-dot ${r.delta >= 0 ? 'in' : 'out'}`}><Icon name={r.delta >= 0 ? 'plus' : 'minus'} size="0.8rem" /></span>
          <span className="ph-row-main"><strong>{r.reason}</strong><span className="muted">{when(r.at)} · {r.type}</span></span>
          <span className={`bk-amt ${r.delta >= 0 ? 'in' : ''}`}>{r.delta >= 0 ? '+' : ''}{money(r.delta)}</span>
        </li>
      ))}
    </ul>
  );
}

export function BankApp() {
  const { settings, saveSettings } = usePhone();
  const [data, setData] = useState<Overview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [view, setView] = useState<View>({ kind: 'home' });
  const load = useCallback(async () => {
    const r = await api<Overview>('bankOverview');
    if (r.ok && r.data) { setData(r.data); setError(null); } else setError(r.message ?? 'Banking is unavailable');
  }, []);
  useEffect(() => { void load(); }, [load]);

  if (view.kind === 'history') return <History onBack={() => setView({ kind: 'home' })} />;
  if (view.kind === 'send' && data) return <Send max={data.max} balance={data.bank} onBack={() => setView({ kind: 'home' })} onDone={(o) => { setData(o); setView({ kind: 'home' }); }} />;

  const hidden = !settings.showBank;
  return (
    <div className="ph-appview">
      <AppHeader title="Bank" />
      <div className="ph-body">
        {error && <div className="ph-empty">{error}<br /><button className="ph-link" onClick={() => void load()}>Retry</button></div>}
        {!error && !data && <div className="ph-empty">Loading…</div>}
        {data && (
          <>
            <div className="bk-card">
              <div className="bk-card-top"><span>VEYL BANK</span><button className="bk-eye" onClick={() => void saveSettings({ showBank: !settings.showBank })} aria-label={hidden ? 'Show balance' : 'Hide balance'}><Icon name="eye" size="0.95rem" /></button></div>
              <div className="bk-balance">{hidden ? '$ • • • • •' : money(data.bank)}</div>
              <div className="bk-card-bottom"><span>{data.name}</span><span>{data.accountMasked}</span></div>
            </div>
            <div className="bk-cash muted">Cash on hand: {hidden ? '••••' : money(data.cash)}</div>
            <div className="bk-actions">
              <button className="ph-btn primary" onClick={() => setView({ kind: 'send' })}><Icon name="send" size="0.9rem" /> Send money</button>
              <button className="ph-btn" onClick={() => setView({ kind: 'history' })}><Icon name="clock" size="0.9rem" /> History</button>
            </div>
            <div className="ph-section">Recent activity</div>
            <Activity rows={data.recent} />
            <div className="ph-help">Deposits and withdrawals are done at a bank or ATM.</div>
          </>
        )}
      </div>
    </div>
  );
}

function History({ onBack }: { onBack: () => void }) {
  const [rows, setRows] = useState<Row[] | null>(null);
  const [next, setNext] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const load = useCallback(async (offset = 0) => {
    const r = await api<{ rows: Row[]; nextOffset: number | null }>('bankHistory', offset);
    if (!r.ok || !r.data) { setError(r.message ?? 'Could not load history'); return; }
    setRows((c) => (offset ? [...(c ?? []), ...r.data!.rows] : r.data!.rows));
    setNext(r.data.nextOffset ?? null);
  }, []);
  useEffect(() => { void load(); }, [load]);
  return (
    <div className="ph-appview">
      <AppHeader title="History" onBack={onBack} />
      <div className="ph-body">
        {error && <div className="ph-empty">{error}</div>}
        {!error && rows === null && <div className="ph-empty">Loading…</div>}
        {rows && <Activity rows={rows} />}
        {next !== null && <button className="ph-link fl-more" onClick={() => void load(next)}>Load more</button>}
      </div>
    </div>
  );
}

function Send({ max, balance, onBack, onDone }: { max: number; balance: number; onBack: () => void; onDone: (o: Overview) => void }) {
  const { toast } = usePhone();
  const [target, setTarget] = useState('');
  const [contacts, setContacts] = useState<Contact[]>([]);
  const [recipient, setRecipient] = useState<{ token: string; name: string; label: string } | null>(null);
  const [amount, setAmount] = useState('');
  const [reference, setReference] = useState('');
  const [busy, setBusy] = useState(false);
  const [op, setOp] = useState<string | null>(null); // kept when the result is uncertain, so a retry can never pay twice
  const [pendingNote, setPendingNote] = useState<string | null>(null);
  useEffect(() => { void api<Contact[]>('contacts').then((r) => setContacts(r.ok && r.data ? r.data : [])); }, []);

  const resolve = async (t = target) => {
    if (!t.trim() || busy) return;
    setBusy(true);
    const r = await api<{ token: string; name: string; label: string }>('bankResolve', t.trim());
    setBusy(false);
    if (!r.ok || !r.data) { toast(r.message ?? 'Recipient not found', 'error'); return; }
    setRecipient(r.data);
  };
  const n = Number(amount);
  const validAmount = Number.isInteger(n) && n >= 1 && n <= max;
  const send = async () => {
    if (!recipient || !validAmount || busy) return;
    setBusy(true);
    const clientOp = op ?? newClientOp();
    setOp(clientOp);
    const r = await api<Overview>('bankSend', recipient.token, n, reference, clientOp);
    setBusy(false);
    if (r.ok && r.data) { toast(r.message ?? 'Sent'); onDone(r.data); return; }
    if (r.code === 'PENDING' || r.code === 'TIMEOUT') {
      setPendingNote('We could not confirm this transfer yet. Check before trying again.');
      return;
    }
    setOp(null);
    if (r.code === 'INVALID_STATE') setRecipient(null);
    toast(r.message ?? 'Transfer failed', 'error');
  };
  const check = async () => {
    if (!op) return;
    const r = await api<{ applied: boolean }>('bankStatus', op);
    if (r.ok && r.data?.applied) { toast('The transfer went through'); onBack(); }
    else { setPendingNote(null); toast('It did not go through. You can try again.', 'error'); }
  };

  if (!recipient) {
    const q = target.trim().toLowerCase();
    const matches = contacts.filter((c) => !q || c.name.toLowerCase().includes(q) || c.number.includes(q.replace(/\D/g, '') || '§')).slice(0, 8);
    return (
      <div className="ph-appview">
        <AppHeader title="Send money" onBack={onBack} />
        <div className="ph-body">
          <label className="ph-field">To<input className="ph-input" autoFocus placeholder="Phone number or account number" value={target}
            onChange={(e) => setTarget(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') void resolve(); }} /></label>
          <button className="ph-btn primary block" disabled={!target.trim() || busy} onClick={() => void resolve()}>{busy ? 'Checking…' : 'Continue'}</button>
          {matches.length > 0 && <div className="ph-section">Contacts</div>}
          <ul className="ph-list">
            {matches.map((c) => (
              <li key={c.id}><button className="ph-row" onClick={() => { setTarget(c.number); void resolve(c.number); }}>
                <span className="ph-row-main"><strong>{c.name}</strong><span className="muted">{fmtNumber(c.number)}</span></span><Icon name="chevron" size="0.9rem" />
              </button></li>
            ))}
          </ul>
        </div>
      </div>
    );
  }

  return (
    <div className="ph-appview">
      <AppHeader title="Send money" onBack={() => { if (!op) setRecipient(null); else onBack(); }} />
      <div className="ph-body">
        <div className="bk-to"><span className="muted">To</span><strong>{recipient.name}</strong><span className="muted">{recipient.label}</span></div>
        <label className="ph-field">Amount<div className="bk-amount"><span>$</span><input className="ph-input" inputMode="numeric" autoFocus value={amount} disabled={!!op}
          onChange={(e) => setAmount(e.target.value.replace(/\D/g, '').slice(0, 9))} /></div></label>
        <div className={`ph-help${n > balance ? ' warn' : ''}`}>{n > balance ? 'More than your balance' : `Up to $${max.toLocaleString('en-US')} per transfer`}</div>
        <label className="ph-field">Reference<input className="ph-input" maxLength={40} placeholder="Optional" value={reference} disabled={!!op} onChange={(e) => setReference(e.target.value)} /></label>
        {pendingNote ? (
          <div className="bk-pending"><p>{pendingNote}</p><button className="ph-btn" onClick={() => void check()}>Check status</button><button className="ph-btn" disabled={busy} onClick={() => void send()}>Try again safely</button></div>
        ) : (
          <button className="ph-btn primary block" disabled={!validAmount || busy} onClick={() => void send()}>{busy ? 'Sending…' : validAmount ? `Send $${n.toLocaleString('en-US')}` : 'Send'}</button>
        )}
      </div>
    </div>
  );
}
