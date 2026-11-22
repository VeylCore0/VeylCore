import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import { BrandHeader, CloseHint, Icon, RadioCard, StateView, Tabs, announceReady, money, newOpId, nui, useNuiMessage, type NuiResponse } from '@veyl/ui';

// ---------------------------------------------------------------------------
// Types (see resources/[veyl]/veyl_cityhall/server/main.lua: overview)
// ---------------------------------------------------------------------------
interface Person {
  firstname?: string; lastname?: string; birthdate?: string; gender?: number | string; nationality?: string; phone?: string;
  citizenid: string; job?: string; grade?: string;
}
interface Licence { key: string; label: string; description?: string; price?: number; held: boolean }
interface Doc { key: string; label: string; description?: string; price?: number; requires?: string; requiresLabel?: string; allowed: boolean }
interface Grade { grade: number; name: string; pay: number }
interface Job { job: string; label: string; description?: string; open: boolean; apply?: string; locationLabel?: string; hasLocation: boolean; grades: Grade[]; member: boolean; current: boolean }
type Method = 'cash' | 'bank';
interface Overview { person: Person; licences: Licence[]; documents: Doc[]; jobs: Job[]; methods: Method[]; balances: Record<Method, number> }
interface Card { kind: string; title: string; firstname?: string; lastname?: string; birthdate?: string; citizenid?: string; issued?: string; self?: boolean }
type Tab = 'identity' | 'licences' | 'jobs';

const api = <T,>(name: string, ...args: unknown[]) => nui<T>('api', { name, args }) as Promise<NuiResponse<T>>;
const gender = (g: Person['gender']) => (g === 1 || g === '1' || g === 'female' ? 'Female' : g === 0 || g === '0' || g === 'male' ? 'Male' : '—');

export function App() {
  const [data, setData] = useState<Overview | null>(null);
  const [tab, setTab] = useState<Tab>('identity');
  const [method, setMethod] = useState<Method>('cash');
  const [busy, setBusy] = useState<string | null>(null);
  const [card, setCard] = useState<Card | null>(null);
  const [toast, setToast] = useState<{ kind: 'ok' | 'error'; text: string } | null>(null);
  const timer = useRef<number>();
  useEffect(() => announceReady(), []);
  const say = useCallback((kind: 'ok' | 'error', text: string) => {
    setToast({ kind, text });
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setToast(null), 3500);
  }, []);

  useNuiMessage<Overview>('cityhall:open', (d) => { setData(d); setTab('identity'); setMethod(d.methods[0] ?? 'cash'); });
  useNuiMessage('cityhall:close', () => setData(null));
  useNuiMessage<Card | null>('cityhall:card', (c) => setCard(c ?? null));

  const close = useCallback(() => { void nui('close'); setData(null); }, []);
  useEffect(() => {
    if (!data) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') close(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [data, close]);

  const run = async (id: string, call: Promise<NuiResponse<Overview>>) => {
    setBusy(id);
    const r = await call;
    setBusy(null);
    if (r.ok && r.data) setData(r.data);
    say(r.ok ? 'ok' : 'error', r.message ?? (r.ok ? 'Done' : 'Something went wrong'));
  };
  const buy = (kind: 'licence' | 'document', key: string) =>
    run(`${kind}:${key}`, api<Overview>('buy', { kind, key, method, opId: newOpId() }));
  const takeJob = (job: string) => run(`job:${job}`, api<Overview>('takeJob', job));
  const waypoint = (job: string) => { void nui('waypoint', { job }); };

  return (
    <>
      {card && !data && <IdCard card={card} floating />}
      {data && (
        <div className="ch-root">
          <header className="ch-header"><BrandHeader section="City Hall" /><CloseHint onClose={close} /></header>
          <main className="ch-main v-panel">
            <div className="ch-toolbar">
              <Tabs<Tab> value={tab} onChange={setTab} tabs={[{ id: 'identity', label: 'Identity' }, { id: 'licences', label: 'Licences' }, { id: 'jobs', label: 'Job board' }]} />
              {tab !== 'jobs' && (
                <div className="ch-pay" role="radiogroup" aria-label="Payment method">
                  {data.methods.map((m) => (
                    <RadioCard key={m} active={method === m} onSelect={() => setMethod(m)} label={`${m === 'cash' ? 'Cash' : 'Bank'} · ${money(data.balances[m])}`} />
                  ))}
                </div>
              )}
            </div>
            <div className="ch-body v-scroll">
              {tab === 'identity' && (
                <div className="ch-identity">
                  <IdCard card={{ kind: 'identity_card', title: 'Identity card', firstname: data.person.firstname, lastname: data.person.lastname, birthdate: data.person.birthdate, citizenid: data.person.citizenid }} />
                  <div className="ch-facts">
                    <Fact label="Gender" value={gender(data.person.gender)} />
                    <Fact label="Nationality" value={data.person.nationality || '—'} />
                    <Fact label="Phone" value={data.person.phone || '—'} />
                    <Fact label="Employment" value={data.person.job ? `${data.person.job}${data.person.grade ? ` · ${data.person.grade}` : ''}` : '—'} />
                  </div>
                  <h3 className="ch-section">Print a document</h3>
                  <div className="ch-list">
                    {data.documents.map((d) => (
                      <Row key={d.key} icon="card" title={d.label} sub={d.allowed ? d.description : `Needs a ${d.requiresLabel ?? d.requires}`}
                        action={<button className="v-btn primary" disabled={!d.allowed || busy !== null} onClick={() => void buy('document', d.key)}>
                          {busy === `document:${d.key}` ? 'Printing…' : `Print · ${money(d.price)}`}
                        </button>} />
                    ))}
                  </div>
                  <p className="v-muted small">Use a card from your inventory to show it to people standing next to you.</p>
                </div>
              )}
              {tab === 'licences' && (
                <div className="ch-list">
                  {data.licences.map((l) => (
                    <Row key={l.key} icon={l.held ? 'check' : 'shield'} tone={l.held ? 'ok' : undefined} title={l.label} sub={l.description}
                      action={l.held ? <span className="ch-pill ok">Held</span>
                        : l.price ? <button className="v-btn primary" disabled={busy !== null} onClick={() => void buy('licence', l.key)}>
                          {busy === `licence:${l.key}` ? 'Issuing…' : `Apply · ${money(l.price)}`}
                        </button>
                        : <span className="ch-pill">Not sold here</span>} />
                  ))}
                </div>
              )}
              {tab === 'jobs' && (
                <div className="ch-jobs">
                  {data.jobs.length === 0 && <StateView kind="empty" message="No jobs are listed right now." />}
                  {data.jobs.map((j) => (
                    <div key={j.job} className="ch-job">
                      <div className="ch-job-head">
                        <Icon name="briefcase" size="1.1rem" />
                        <strong>{j.label}</strong>
                        {j.current ? <span className="ch-pill ok">Your job</span> : j.member ? <span className="ch-pill">Member</span> : j.open ? <span className="ch-pill accent">Hiring now</span> : <span className="ch-pill">Applications</span>}
                      </div>
                      {j.description && <p>{j.description}</p>}
                      <div className="ch-grades">
                        {j.grades.map((g) => <span key={g.grade}>{g.name} <em>{money(g.pay)}</em></span>)}
                      </div>
                      {!j.open && j.apply && <div className="v-muted small">{j.apply}</div>}
                      <div className="ch-job-actions">
                        {j.hasLocation && <button className="v-btn" onClick={() => waypoint(j.job)}><Icon name="pin" size="1rem" /> {j.locationLabel ?? 'Set GPS'}</button>}
                        {j.open && !j.current && (
                          <button className="v-btn primary" disabled={busy !== null} onClick={() => void takeJob(j.job)}>
                            {busy === `job:${j.job}` ? 'Signing…' : 'Take this job'}
                          </button>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </main>
        </div>
      )}
      {toast && <div className={`v-toast-inline ${toast.kind === 'error' ? 'error' : 'success'}`} role="alert"><Icon name={toast.kind === 'error' ? 'alert' : 'check'} size="1rem" />{toast.text}</div>}
    </>
  );
}

function Fact({ label, value }: { label: string; value: string }) {
  return <div className="ch-fact"><span className="v-muted small">{label}</span><strong>{value}</strong></div>;
}

function Row({ icon, title, sub, action, tone }: { icon: 'card' | 'check' | 'shield'; title: string; sub?: string; action: ReactNode; tone?: 'ok' }) {
  return (
    <div className="ch-row">
      <span className={`ch-row-icon ${tone ?? ''}`}><Icon name={icon} size="1.1rem" /></span>
      <div className="ch-row-main"><strong>{title}</strong>{sub && <div className="v-muted small">{sub}</div>}</div>
      <div>{action}</div>
    </div>
  );
}

function IdCard({ card, floating }: { card: Card; floating?: boolean }) {
  const name = `${card.firstname ?? ''} ${card.lastname ?? ''}`.trim() || 'Unknown';
  return (
    <div className={`ch-card ${card.kind}${floating ? ' floating' : ''}`} aria-live={floating ? 'polite' : undefined}>
      <div className="ch-card-top">
        <span>STATE OF SAN ANDREAS</span>
        <span>{card.title.toUpperCase()}</span>
      </div>
      <div className="ch-card-body">
        <div className="ch-card-photo"><Icon name="user" size="2.6rem" /></div>
        <div className="ch-card-fields">
          <div><label>Name</label><strong>{name}</strong></div>
          <div><label>Date of birth</label><strong>{card.birthdate || '—'}</strong></div>
          <div><label>Citizen ID</label><strong className="mono">{card.citizenid || '—'}</strong></div>
          {card.issued && <div><label>Issued</label><strong>{card.issued}</strong></div>}
        </div>
      </div>
      {floating && card.self && <div className="ch-card-note">You are showing this card</div>}
    </div>
  );
}
