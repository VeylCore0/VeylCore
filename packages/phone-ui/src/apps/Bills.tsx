// Bills: invoices and citations to pay, standing orders (automatic payments), and your credit score.
import { useState } from 'react';
import { api } from '../api';
import { formatDigits } from '../format';
import { Ico } from '../icons';
import { Avatar, Button, Header, Sheet, TextInput, say } from '../ui';
import { Fab, Loaded, ago, usd, useLoad } from './kit';

type Bill = { kind: 'invoice' | 'citation'; id: number; amount: number; label: string; at: number };
type Standing = { id: number; to_label: string; amount: number; every_days: number; note: string | null; next_at: number; failures: number };
type Data = { bills: Bill[]; standing: Standing[]; score: number };

const band = (s: number): [string, string] => (s >= 800 ? ['Exceptional', '#34d27b'] : s >= 740 ? ['Very good', '#5fd35f'] : s >= 670 ? ['Good', '#a8d33a'] : s >= 580 ? ['Fair', '#f2b443'] : ['Poor', '#e0576a']);

function Gauge({ score }: { score: number }) {
  const pct = Math.max(0, Math.min(1, (score - 300) / 550));
  const [label, color] = band(score);
  const arc = Math.PI * 70;
  return (
    <div className="ph-gauge">
      <svg viewBox="0 0 180 100" aria-hidden="true">
        <path d="M20 90 A70 70 0 0 1 160 90" fill="none" stroke="rgba(255,255,255,.1)" strokeWidth="12" strokeLinecap="round" />
        <path d="M20 90 A70 70 0 0 1 160 90" fill="none" stroke={color} strokeWidth="12" strokeLinecap="round" strokeDasharray={`${arc * pct} ${arc}`} style={{ filter: `drop-shadow(0 0 8px ${color})` }} />
      </svg>
      <div className="ph-gauge-num"><strong>{score}</strong><em style={{ color }}>{label}</em></div>
    </div>
  );
}

export function BillsApp() {
  const load = useLoad(() => api<Data>('billsData'));
  const [pay, setPay] = useState<Bill | null>(null);
  const [create, setCreate] = useState(false);
  const total = load.data?.bills.reduce((a, b) => a + b.amount, 0) ?? 0;

  return (
    <div className="ph-app">
      <Header title="Bills" />
      <div className="ph-scroll ph-pad">
        <Loaded {...load}>
          {(d) => (
            <>
              <div className="ph-creditcard"><Gauge score={d.score} /><div className="ph-credit-side"><span>Credit score</span><small>Pay on time and keep your balance up to raise it.</small></div></div>
              <section className="ph-mine"><h4>Due now{d.bills.length > 0 && <span className="ph-due-total">{usd(total)}</span>}</h4>
                {d.bills.length === 0 && <div className="ph-allclear"><Ico name="check" size={18} /> You are all paid up</div>}
                {d.bills.map((b) => (
                  <div key={`${b.kind}${b.id}`} className="ph-billrow">
                    <span className="ph-place-ico" style={{ background: b.kind === 'citation' ? '#e0576a' : '#3a7bf0' }}><Ico name={b.kind === 'citation' ? 'alert' : 'money'} size={16} /></span>
                    <span className="ph-jobrow-main"><strong>{b.label}</strong><em>{ago(b.at)} ago</em></span>
                    <button className="ph-gps" onClick={() => setPay(b)}>{usd(b.amount)}</button>
                  </div>
                ))}
              </section>
              <section className="ph-mine"><h4>Standing orders</h4>
                {d.standing.length === 0 && <p className="ph-hint">Send money automatically, like rent or a weekly allowance.</p>}
                {d.standing.map((s) => (
                  <div key={s.id} className="ph-billrow">
                    <Avatar name={s.to_label} id={s.to_label} size={38} />
                    <span className="ph-jobrow-main"><strong>{usd(s.amount)} to {s.to_label}</strong><em>Every {s.every_days} day{s.every_days === 1 ? '' : 's'}{s.note ? ` · ${s.note}` : ''}{s.failures > 0 ? ` · ${s.failures} failed` : ''}</em></span>
                    <button className="ph-iconmini" onClick={async () => { if (say(await api('standingCancel', s.id))) void load.reload(); }} aria-label="Cancel standing order"><Ico name="x" size={14} /></button>
                  </div>
                ))}
              </section>
            </>
          )}
        </Loaded>
      </div>
      <Fab label="New standing order" onClick={() => setCreate(true)} />
      {pay && <PaySheet b={pay} onClose={() => setPay(null)} onDone={() => { setPay(null); void load.reload(); }} />}
      {create && <StandingSheet onClose={() => setCreate(false)} onDone={() => { setCreate(false); void load.reload(); }} />}
    </div>
  );
}

function PaySheet({ b, onClose, onDone }: { b: Bill; onClose: () => void; onDone: () => void }) {
  const [busy, setBusy] = useState(false);
  const go = async (method: 'cash' | 'bank') => { setBusy(true); const r = await api('billPay', b.kind, b.id, method); setBusy(false); if (say(r)) onDone(); };
  return (
    <Sheet title="Pay bill" onClose={onClose}>
      <div className="ph-form">
        <div className="ph-fee"><span>{b.label}</span><strong>{usd(b.amount)}</strong></div>
        <Button kind="primary" block disabled={busy} onClick={() => void go('bank')}><Ico name="transfer" size={16} /> Pay from bank</Button>
        <Button block disabled={busy} onClick={() => void go('cash')}><Ico name="money" size={16} /> Pay with cash</Button>
      </div>
    </Sheet>
  );
}

function StandingSheet({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const [number, setNumber] = useState('');
  const [amount, setAmount] = useState('');
  const [days, setDays] = useState('7');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const ok = number.replace(/\D/g, '').length === 7 && Number(amount) >= 1 && Number(days) >= 1 && !busy;
  const go = async () => { setBusy(true); const r = await api('standingCreate', number, Number(amount), Number(days), note); setBusy(false); if (say(r)) onDone(); };
  return (
    <Sheet title="New standing order" onClose={onClose}>
      <div className="ph-form">
        <label>Pay to (phone number)<TextInput value={formatDigits(number)} onChange={setNumber} placeholder="555-1234" inputMode="tel" autoFocus /></label>
        <div className="ph-two">
          <label>Amount ($)<TextInput value={amount} onChange={(v) => setAmount(v.replace(/\D/g, ''))} placeholder="100" inputMode="numeric" maxLength={6} /></label>
          <label>Every (days)<TextInput value={days} onChange={(v) => setDays(v.replace(/\D/g, ''))} placeholder="7" inputMode="numeric" maxLength={2} /></label>
        </div>
        <label>Note (optional)<TextInput value={note} onChange={setNote} placeholder="Rent" maxLength={40} /></label>
        <Button kind="primary" block disabled={!ok} onClick={go}>Create standing order</Button>
      </div>
    </Sheet>
  );
}
