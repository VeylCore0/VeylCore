// Bank: a card with your balance, recent activity, and a send-money flow (recipient confirmed first, one tap to pay,
// safe to retry: the server never charges the same request twice).
import { useEffect, useRef, useState } from 'react';
import { api, post } from '../api';
import { openApp } from '../controller';
import { listTime } from '../format';
import { Ico } from '../icons';
import { useStore } from '../store';
import { Avatar, Button, Empty, Header, Group, Sheet, Spinner, TextInput, cx, say } from '../ui';
import { Loaded, clientOp, useLoad, usd } from './kit';
import type { Contact } from '../types';

type Activity = { id: string; type: string; delta: number; balance: number; reason?: string; at: number };
type Overview = { name: string; bank: number; cash: number; account: string; accountMasked: string; recent: Activity[]; max: number };

const reasonIcon = (a: Activity) => /salary|paycheck|wage|pay/i.test(a.reason ?? '') ? 'briefcase' : /phone transfer/i.test(a.reason ?? '') ? 'send' : /invoice|citation|bill/i.test(a.reason ?? '') ? 'receipt' : a.delta >= 0 ? 'download' : 'bag';

export function BankApp() {
  const load = useLoad(() => api<Overview>('bankOverview'));
  const streamer = useStore((s) => s.settings.streamer);
  const [send, setSend] = useState(false);
  const [history, setHistory] = useState(false);
  const [hidden, setHidden] = useState(false);

  return (
    <div className="ph-app">
      <Header title="Bank" right={<button className="ph-link" onClick={() => setHistory(true)}>History</button>} />
      <div className="ph-scroll ph-pad">
        <Loaded {...load}>
          {(o) => (
            <>
              <div className="ph-bankcard">
                <div className="ph-bankcard-top"><span><Ico name="bank" size={16} /> Veyl Bank</span><button onClick={() => setHidden(!hidden)} aria-label={hidden ? 'Show balance' : 'Hide balance'}><Ico name="eye" size={16} /></button></div>
                <div className="ph-bankcard-bal"><small>Available balance</small><strong>{hidden || streamer ? '$••••••' : usd(o.bank)}</strong></div>
                <div className="ph-bankcard-bot"><span>{o.name}</span><span>{o.accountMasked}</span></div>
              </div>
              <div className="ph-bankstats">
                <div><Ico name="money" size={18} /><span>Cash on hand</span><strong>{hidden || streamer ? '$••••' : usd(o.cash)}</strong></div>
                <div><Ico name="transfer" size={18} /><span>Send up to</span><strong>{usd(o.max)}</strong></div>
              </div>
              <div className="ph-bankactions">
                <button className="primary" onClick={() => setSend(true)}><Ico name="send" size={20} /><span>Send money</span></button>
                <button onClick={() => openApp('bills')}><Ico name="receipt" size={20} /><span>Bills</span></button>
              </div>
              <Group title="Recent activity">
                {o.recent.length === 0 ? <Empty icon="bank" title="No activity yet" /> : o.recent.map((a) => <ActivityRow key={a.id} a={a} />)}
              </Group>
              {send && <SendSheet o={o} onClose={() => setSend(false)} onDone={() => { void load.reload(); }} />}
            </>
          )}
        </Loaded>
      </div>
      {history && <HistorySheet onClose={() => setHistory(false)} />}
    </div>
  );
}

function ActivityRow({ a }: { a: Activity }) {
  return (
    <div className="ph-activity">
      <span className={cx('ph-activity-ico', a.delta >= 0 ? 'in' : 'out')}><Ico name={reasonIcon(a)} size={16} /></span>
      <span className="ph-activity-main"><strong>{a.reason ?? (a.delta >= 0 ? 'Deposit' : 'Payment')}</strong><em>{listTime(a.at)}</em></span>
      <span className={cx('ph-activity-amt', a.delta >= 0 && 'in')}>{a.delta >= 0 ? '+' : ''}{usd(a.delta)}</span>
    </div>
  );
}

function HistorySheet({ onClose }: { onClose: () => void }) {
  const [rows, setRows] = useState<Activity[] | null>(null);
  const [next, setNext] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const fetchPage = async (offset: number) => {
    setBusy(true);
    const r = await api<{ rows: Activity[]; nextOffset: number | null }>('bankHistory', offset);
    setBusy(false);
    if (!say(r) || !r.data) return;
    setRows((l) => (offset === 0 ? r.data!.rows : [...(l ?? []), ...r.data!.rows]));
    setNext(r.data.nextOffset ?? null);
  };
  useEffect(() => { void fetchPage(0); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <Sheet title="Activity" onClose={onClose}>
      {rows === null && <Spinner />}
      {rows?.length === 0 && <Empty icon="bank" title="Nothing here yet" />}
      {!!rows?.length && <Group>{rows.map((a) => <ActivityRow key={a.id} a={a} />)}</Group>}
      {next !== null && <button className="ph-more" onClick={() => void fetchPage(next)} disabled={busy}>Load more</button>}
    </Sheet>
  );
}

const QUICK = [20, 50, 100, 500, 1000];

function SendSheet({ o, onClose, onDone }: { o: Overview; onClose: () => void; onDone: () => void }) {
  const [step, setStep] = useState<'who' | 'amount' | 'done'>('who');
  const [target, setTarget] = useState('');
  const [who, setWho] = useState<{ token: string; name: string; label: string } | null>(null);
  const [amount, setAmount] = useState('');
  const [ref, setRef] = useState('');
  const [busy, setBusy] = useState(false);
  const [contacts, setContacts] = useState<Contact[]>([]);
  const [note, setNote] = useState('');
  const op = useRef(clientOp());
  useEffect(() => { void api<Contact[]>('contacts').then((r) => setContacts(r.ok ? (r.data ?? []).slice(0, 8) : [])); }, []);

  const resolve = async (t = target) => {
    setBusy(true);
    const r = await api<{ token: string; name: string; label: string }>('bankResolve', t);
    setBusy(false);
    if (!say(r) || !r.data) return;
    setWho(r.data); setStep('amount');
  };
  const n = Number(amount.replace(/\D/g, '')) || 0;
  const pay = async () => {
    if (!who || n < 1) return;
    setBusy(true);
    let r = await api<Overview>('bankSend', who.token, n, ref, op.current);
    // The ledger may still be confirming: ask until it says whether it went through.
    for (let i = 0; i < 6 && r.code === 'PENDING'; i++) {
      setNote('Verifying the transfer...');
      await new Promise((res) => setTimeout(res, 1500));
      const st = await api<{ applied: boolean }>('bankStatus', op.current);
      if (st.ok && st.data?.applied) { r = { ok: true, data: undefined, message: `Sent ${usd(n)} to ${who.name}` }; break; }
    }
    setBusy(false);
    if (!r.ok) { say(r); return; }
    setStep('done'); onDone();
  };

  return (
    <Sheet title={step === 'done' ? 'Sent' : 'Send money'} onClose={onClose}>
      {step === 'who' && (
        <div className="ph-form">
          {contacts.length > 0 && (
            <div className="ph-quickrow" aria-label="Contacts">
              {contacts.map((c) => (
                <button key={c.id} onClick={() => { setTarget(c.number); void resolve(c.number); }}>
                  <Avatar name={c.name} id={c.number} size={46} /><span>{c.name.split(' ')[0]}</span>
                </button>
              ))}
            </div>
          )}
          <label>Phone number or account<TextInput value={target} onChange={setTarget} placeholder="555-1234 or VC12345" autoFocus onEnter={() => target && resolve()} /></label>
          <Button kind="primary" block onClick={() => resolve()} disabled={!target.trim() || busy}>Continue</Button>
        </div>
      )}
      {step === 'amount' && who && (
        <div className="ph-form">
          <div className="ph-payee"><Avatar name={who.name} id={who.label} size={52} /><span><strong>{who.name}</strong><em>{who.label}</em></span><button className="ph-link" onClick={() => setStep('who')}>Change</button></div>
          <div className="ph-amount"><span>$</span><input inputMode="numeric" value={amount} onChange={(e) => setAmount(e.target.value.replace(/\D/g, '').slice(0, 9))} placeholder="0" autoFocus
            onFocus={() => void post('ui:typing', { typing: true })} onBlur={() => void post('ui:typing', { typing: false })} aria-label="Amount" /></div>
          <div className="ph-quickamts">{QUICK.map((q) => <button key={q} className={cx(n === q && 'on')} onClick={() => setAmount(String(q))}>{usd(q)}</button>)}</div>
          <label>Reference (optional)<TextInput value={ref} onChange={setRef} placeholder="Rent, thanks, etc." maxLength={40} /></label>
          <p className={cx('ph-hint', n > o.bank && 'danger')}>{n > o.bank ? `You only have ${usd(o.bank)}` : `Available ${usd(o.bank)}. Maximum ${usd(o.max)} per transfer.`}</p>
          {note && <p className="ph-hint">{note}</p>}
          <Button kind="primary" block onClick={pay} disabled={busy || n < 1 || n > o.bank || n > o.max}>{busy ? 'Sending...' : `Send ${n ? usd(n) : ''}`}</Button>
        </div>
      )}
      {step === 'done' && who && (
        <div className="ph-done">
          <span className="ph-done-ico"><Ico name="check" size={40} stroke={2.6} /></span>
          <h3>{usd(n)} sent</h3>
          <p>to {who.name}</p>
          <Button kind="primary" block onClick={onClose}>Done</Button>
        </div>
      )}
    </Sheet>
  );
}

