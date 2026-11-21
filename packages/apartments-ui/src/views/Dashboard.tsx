import { useCallback, useEffect, useState } from 'react';
import { Icon, StateView, Tabs, money, nui } from '@veyl/ui';
import { PERM_LABEL, ROLE_LABEL, api, fmtDate, fmtDateTime, newOp, relative, type Dashboard as Data, type Home } from '../types';

type Tab = 'home' | 'keys' | 'rent' | 'maintenance';
type Say = (k: 'ok' | 'error', t: string) => void;

function Target({ phone, onSubmit, label, busy, extra }: { phone: boolean; onSubmit: (t: { number?: string; serverId?: number }) => void; label: string; busy: boolean; extra?: React.ReactNode }) {
  const [value, setValue] = useState('');
  const digits = value.replace(/\D/g, '');
  const target = phone && digits.length === 7 ? { number: `${digits.slice(0, 3)}-${digits.slice(3)}` } : digits.length > 0 && digits.length <= 4 ? { serverId: Number(digits) } : null;
  return (
    <div className="apt-target">
      <input className="v-input" value={value} onChange={(e) => setValue(e.target.value)} placeholder={phone ? 'Phone number, or nearby player ID' : 'Nearby player ID'} aria-label={label} />
      {extra}
      <button className="v-btn primary" disabled={!target || busy} onClick={() => target && onSubmit(target)}>{label}</button>
    </div>
  );
}

export function DashboardView({ initial, toast }: { initial: Data; toast: Say }) {
  const [data, setData] = useState<Data | null>(initial);
  const [error, setError] = useState<string | null>(null);
  const [index, setIndex] = useState(0);
  const [tab, setTab] = useState<Tab>('home');
  const [busy, setBusy] = useState(false);
  const reload = useCallback(async () => {
    const r = await api<Data>('dashboard');
    if (r.ok && r.data) { setData(r.data); setError(null); } else setError(r.message ?? 'Could not load');
  }, []);
  useEffect(() => { const t = window.setInterval(() => void reload(), 15000); return () => window.clearInterval(t); }, [reload]);

  const act = async (name: string, ...args: unknown[]) => {
    setBusy(true);
    const r = await api(name, ...args);
    setBusy(false);
    toast(r.ok ? 'ok' : 'error', r.message ?? (r.ok ? 'Done' : 'Something went wrong'));
    if (r.ok) await reload();
    return r.ok;
  };

  if (error && !data) return <StateView kind="error" message={error} onRetry={() => void reload()} />;
  if (!data) return <StateView kind="loading" />;
  const home: Home | undefined = data.homes[index];

  return (
    <div className="apt-dash">
      {data.invites.map((i) => (
        <div key={i.leaseId} className="apt-banner" role="status">
          <Icon name="users" size="1.1rem" />
          <span><strong>{i.from}</strong> invited you to live at {i.label}.</span>
          <button className="v-btn" disabled={busy} onClick={() => void act('roommateRespond', i.leaseId, false)}>Decline</button>
          <button className="v-btn primary" disabled={busy} onClick={() => void act('roommateRespond', i.leaseId, true)}>Move in</button>
        </div>
      ))}
      {(data.parcels > 0 || data.recovery > 0) && (
        <div className="apt-banner subtle"><Icon name="box" size="1.1rem" />
          <span>{data.parcels > 0 ? `${data.parcels} parcel${data.parcels === 1 ? '' : 's'} waiting` : ''}{data.parcels > 0 && data.recovery > 0 ? ' · ' : ''}
            {data.recovery > 0 ? `${data.recovery} storage box${data.recovery === 1 ? '' : 'es'} to collect` : ''} at the front desk.</span>
        </div>
      )}
      {!home ? (
        <div className="apt-empty-home">
          <Icon name="home" size="2.2rem" />
          <h3>No home yet</h3>
          <p className="v-muted">Rent a room at the Starlite Motel front desk. Keys you are given also show up here.</p>
        </div>
      ) : (
        <>
          {data.homes.length > 1 && (
            <div className="apt-homes">{data.homes.map((h, i) => <button key={h.id} className={`apt-chip${i === index ? ' on' : ''}`} onClick={() => { setIndex(i); setTab('home'); }}>Room {h.number} · {ROLE_LABEL[h.role]}</button>)}</div>
          )}
          <div className="apt-home-head">
            <div>
              <div className="apt-eyebrow">{home.buildingLabel} · {ROLE_LABEL[home.role]}</div>
              <h2>Room {home.number}</h2>
              <div className="v-muted">Floor {home.floor} · {home.address}</div>
            </div>
            <div className="apt-head-actions">
              <button className="v-btn" onClick={() => void nui('waypoint', home.waypoint).then(() => toast('ok', 'Waypoint set'))}><Icon name="pin" size="1rem" /> Waypoint</button>
            </div>
          </div>
          {home.role !== 'guest' && (
            <Tabs<Tab> tabs={[{ id: 'home', label: 'Home' }, { id: 'keys', label: `Keys & visitors${home.visits?.length ? ` (${home.visits.length})` : ''}` },
              { id: 'rent', label: 'Rent' }, { id: 'maintenance', label: 'Maintenance' }]} value={tab} onChange={setTab} />
          )}
          <div className="apt-tab-body v-scroll">
            {(tab === 'home' || home.role === 'guest') && <HomeTab home={home} busy={busy} act={act} />}
            {tab === 'keys' && home.role !== 'guest' && <KeysTab home={home} data={data} busy={busy} act={act} />}
            {tab === 'rent' && home.role !== 'guest' && <RentTab home={home} data={data} busy={busy} act={act} />}
            {tab === 'maintenance' && home.role !== 'guest' && <MaintenanceTab home={home} categories={data.categories} busy={busy} act={act} />}
          </div>
        </>
      )}
    </div>
  );
}

type Act = (name: string, ...args: unknown[]) => Promise<boolean>;

function HomeTab({ home, busy, act }: { home: Home; busy: boolean; act: Act }) {
  const [typed, setTyped] = useState('');
  const now = home.serverTime ?? Date.now() / 1000;
  return (
    <div className="apt-grid2">
      <div className="apt-card">
        <div className="apt-card-title"><Icon name="money" size="1rem" /> Lease</div>
        {home.overdue ? <div className="apt-pill danger">Overdue since {fmtDate(home.overdueSince)}</div> : <div className="apt-pill ok">Paid up</div>}
        <div className="apt-line"><span>Rent</span><span>{money(home.rent)} / {home.intervalDays} days</span></div>
        <div className="apt-line"><span>Paid until</span><span>{fmtDate(home.paidUntil)}</span></div>
        <div className="apt-line"><span>Next payment</span><span>{fmtDate(home.nextChargeAt)} ({relative(home.nextChargeAt, now)})</span></div>
        <div className="apt-line"><span>Automatic rent</span><span>{home.autopay ? 'On' : 'Off'}</span></div>
      </div>
      <div className="apt-card">
        <div className="apt-card-title"><Icon name="key" size="1rem" /> Your access</div>
        <div className="apt-perms">{Object.entries(home.perms).filter(([, v]) => v).map(([k]) => <span key={k} className="apt-pill">{PERM_LABEL[k] ?? k}</span>)}</div>
        {home.parking && <div className="apt-line"><span>Parking</span><span>{home.parking.label}</span></div>}
        {home.role === 'roommate' && <button className="v-btn danger" disabled={busy} onClick={() => void act('roommateLeave', home.id)}>Move out of this home</button>}
      </div>
      {home.role === 'leaseholder' && (
        <div className="apt-card apt-span2">
          <div className="apt-card-title"><Icon name="users" size="1rem" /> Visitor directory</div>
          <p className="v-muted">When on, visitors can find you by name at the front desk and ring you. Your room number is never shown.</p>
          <label className="apt-check"><input type="checkbox" checked={home.directory} disabled={busy} onChange={(e) => void act('setDirectory', home.id, e.target.checked)} /> List me in the directory</label>
        </div>
      )}
      {home.role === 'leaseholder' && (
        <div className="apt-card apt-span2 danger-zone">
          <div className="apt-card-title"><Icon name="alert" size="1rem" /> Move out</div>
          <p className="v-muted">Your lease ends now. Storage and furniture wait for you at the front desk. {home.overdue ? 'Rent is overdue, so the deposit is kept.' : `Your ${money(home.deposit)} deposit is refunded.`}</p>
          <div className="apt-target">
            <input className="v-input" value={typed} onChange={(e) => setTyped(e.target.value)} placeholder="Type MOVE OUT to confirm" aria-label="Confirm move out" />
            <button className="v-btn danger" disabled={busy || typed !== 'MOVE OUT'} onClick={() => void act('moveOut', home.id, typed)}>End lease</button>
          </div>
        </div>
      )}
    </div>
  );
}

function KeysTab({ home, data, busy, act }: { home: Home; data: Data; busy: boolean; act: Act }) {
  const [hours, setHours] = useState(4);
  const [single, setSingle] = useState(false);
  const canGuests = !!home.perms.guests;
  const canRoommates = !!home.perms.roommates;
  const now = home.serverTime ?? Date.now() / 1000;
  return (
    <div className="apt-grid2">
      {canGuests && (
        <div className="apt-card apt-span2">
          <div className="apt-card-title"><Icon name="bell" size="1rem" /> At the door</div>
          {!home.visits?.length ? <p className="v-muted">No one is waiting.</p> : home.visits.map((v) => (
            <div key={v.id} className="apt-visit">
              <strong>{v.name}</strong><span className="v-muted">is requesting access</span>
              <button className="v-btn" disabled={busy} onClick={() => void act('respondVisit', v.id, 'block')}>Block</button>
              <button className="v-btn" disabled={busy} onClick={() => void act('respondVisit', v.id, 'decline')}>Decline</button>
              <button className="v-btn primary" disabled={busy} onClick={() => void act('respondVisit', v.id, 'allow')}>Allow entry</button>
            </div>
          ))}
        </div>
      )}
      <div className="apt-card">
        <div className="apt-card-title"><Icon name="users" size="1rem" /> Roommates</div>
        <div className="apt-person"><strong>{home.leaseholder?.name}</strong><span className="apt-pill">Leaseholder</span></div>
        {(home.roommates ?? []).map((r) => (
          <div key={r.citizenid} className="apt-person-block">
            <div className="apt-person"><strong>{r.name}</strong><span className="apt-pill">{r.status === 'invited' ? 'Invited' : 'Roommate'}</span>
              {canRoommates && <button className="v-icon-btn" disabled={busy} aria-label={`Remove ${r.name}`} onClick={() => void act('roommateRemove', home.id, r.citizenid)}><Icon name="close" size="0.9rem" /></button>}</div>
            {r.status === 'active' && (
              <div className="apt-perm-toggles">
                {data.roommatePermissions.map((p) => (
                  <label key={p} className="apt-check small">
                    <input type="checkbox" disabled={!canRoommates || busy || p === 'enter'} checked={r.perms.includes(p)}
                      onChange={(e) => void act('roommatePerms', home.id, r.citizenid, e.target.checked ? [...r.perms, p] : r.perms.filter((x) => x !== p))} />
                    {PERM_LABEL[p]}
                  </label>
                ))}
              </div>
            )}
          </div>
        ))}
        {canRoommates && <Target phone={data.phone} label="Invite roommate" busy={busy} onSubmit={(t) => void act('roommateInvite', home.id, t)} />}
      </div>
      <div className="apt-card">
        <div className="apt-card-title"><Icon name="key" size="1rem" /> Guest passes</div>
        {!(home.guests ?? []).length && <p className="v-muted">No active passes.</p>}
        {(home.guests ?? []).map((g) => (
          <div key={g.id} className="apt-person">
            <strong>{g.name}</strong>
            <span className="v-muted">{g.source === 'doorbell' ? 'Doorbell' : g.source === 'maintenance' ? 'Maintenance' : 'Pass'} · ends {relative(g.expires, now)}{g.singleUse ? (g.used ? ' · used' : ' · one visit') : ''}</span>
            {canGuests && <button className="v-btn" disabled={busy} onClick={() => void act('guestRevoke', g.id)}>Revoke</button>}
          </div>
        ))}
        {canGuests && (
          <Target phone={data.phone} label="Give pass" busy={busy} onSubmit={(t) => void act('guestGrant', home.id, t, hours, single)}
            extra={<>
              <select className="v-input apt-hours" value={hours} onChange={(e) => setHours(Number(e.target.value))} aria-label="Hours">
                {[1, 2, 4, 8, 24, 72].filter((h) => h <= data.maxGuestHours).map((h) => <option key={h} value={h}>{h} h</option>)}
              </select>
              <label className="apt-check small"><input type="checkbox" checked={single} onChange={(e) => setSingle(e.target.checked)} /> One visit</label>
            </>} />
        )}
        {!!home.blocked?.length && (
          <>
            <div className="apt-card-sub">Blocked visitors</div>
            {home.blocked.map((b) => <div key={b.citizenid} className="apt-person"><span>{b.name}</span><button className="v-btn" disabled={busy} onClick={() => void act('unblock', home.id, b.citizenid)}>Unblock</button></div>)}
          </>
        )}
      </div>
    </div>
  );
}

interface PaymentRow { id: number; kind: string; period: number; amount: number; method: string; note?: string; at: number }

function RentTab({ home, data, busy, act }: { home: Home; data: Data; busy: boolean; act: Act }) {
  const [rows, setRows] = useState<PaymentRow[] | null>(null);
  const [next, setNext] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [payOp, setPayOp] = useState<string>(newOp);
  const [amount, setAmount] = useState('');
  const load = useCallback(async (before?: number) => {
    const r = await api<{ items: PaymentRow[]; nextBefore: number | null }>('payments', home.id, before);
    if (!r.ok || !r.data) { setError(r.message ?? 'Could not load payments'); return; }
    setRows((c) => (before ? [...(c ?? []), ...r.data!.items] : r.data!.items)); setNext(r.data.nextBefore);
  }, [home.id]);
  useEffect(() => { void load(); }, [load]);
  const KIND: Record<string, string> = { initial: 'First payment + deposit', rent: 'Rent', refund: 'Deposit refund', contribution: 'Roommate contribution' };
  return (
    <div className="apt-grid2">
      {home.perms.lease ? (
        <div className="apt-card">
          <div className="apt-card-title"><Icon name="money" size="1rem" /> Pay rent</div>
          <p className="v-muted">Pays the next period ({money(home.rent)}). You can pay at most one period ahead.</p>
          <button className="v-btn primary" disabled={busy || data.balances.bank < home.rent}
            onClick={() => void act('payRent', home.id, 'bank', payOp).then((ok) => ok && setPayOp(newOp()))}>Pay {money(home.rent)} from bank</button>
          <label className="apt-check"><input type="checkbox" checked={home.autopay} disabled={busy} onChange={(e) => void act('setAutopay', home.id, e.target.checked)} /> Automatic rent from my bank</label>
        </div>
      ) : (
        <div className="apt-card">
          <div className="apt-card-title"><Icon name="money" size="1rem" /> Help with rent</div>
          <p className="v-muted">{home.leaseholder?.name} pays the rent. You can send them a contribution (a normal bank transfer, recorded here).</p>
          <div className="apt-target">
            <input className="v-input" inputMode="numeric" value={amount} onChange={(e) => setAmount(e.target.value.replace(/\D/g, '').slice(0, 6))} placeholder="Amount" aria-label="Amount" />
            <button className="v-btn primary" disabled={busy || !Number(amount)} onClick={() => void act('contribute', home.id, Number(amount), newOp()).then((ok) => ok && setAmount(''))}>Send</button>
          </div>
        </div>
      )}
      <div className="apt-card">
        <div className="apt-card-title"><Icon name="receipt" size="1rem" /> Payment history</div>
        {error && <StateView kind="error" message={error} />}
        {!error && rows === null && <StateView kind="loading" />}
        {rows?.length === 0 && <p className="v-muted">No payments yet.</p>}
        {rows?.map((r) => (
          <div key={r.id} className="apt-line"><span>{KIND[r.kind] ?? r.kind}{r.kind === 'rent' ? ` · period ${r.period}` : ''}<em className="v-muted"> · {fmtDateTime(r.at)}</em></span>
            <span className={r.kind === 'refund' ? 'pos' : ''}>{r.kind === 'refund' ? '+' : ''}{money(r.amount)}</span></div>
        ))}
        {next && <button className="v-btn" onClick={() => void load(next)}>Load more</button>}
      </div>
    </div>
  );
}

interface MReq { id: number; category: string; description: string; preference?: string; allow_entry: number; status: string; staff_name?: string; scheduled_for?: string; note?: string; at: number }

function MaintenanceTab({ home, categories, busy, act }: { home: Home; categories: string[]; busy: boolean; act: Act }) {
  const [list, setList] = useState<MReq[] | null>(null);
  const [category, setCategory] = useState(categories[0] ?? 'other');
  const [text, setText] = useState('');
  const [pref, setPref] = useState('');
  const [allow, setAllow] = useState(false);
  const load = useCallback(async () => { const r = await api<MReq[]>('maintenanceList', home.id); setList(r.ok && r.data ? r.data : []); }, [home.id]);
  useEffect(() => { void load(); }, [load]);
  const STATUS: Record<string, string> = { open: 'Waiting', accepted: 'Accepted', scheduled: 'Scheduled', in_progress: 'In progress', completed: 'Done', cancelled: 'Cancelled' };
  return (
    <div className="apt-grid2">
      <div className="apt-card">
        <div className="apt-card-title"><Icon name="wrench" size="1rem" /> New request</div>
        <div className="apt-chips">{categories.map((c) => <button key={c} className={`apt-chip${c === category ? ' on' : ''}`} onClick={() => setCategory(c)}>{c}</button>)}</div>
        <textarea className="v-input" rows={3} maxLength={300} value={text} onChange={(e) => setText(e.target.value)} placeholder="What is wrong?" />
        <input className="v-input" maxLength={60} value={pref} onChange={(e) => setPref(e.target.value)} placeholder="Best time (optional)" />
        <label className="apt-check"><input type="checkbox" checked={allow} onChange={(e) => setAllow(e.target.checked)} /> Staff may enter once while I am away (time-limited)</label>
        <button className="v-btn primary" disabled={busy || !text.trim()}
          onClick={() => void act('maintenanceCreate', home.id, category, text, pref, allow).then((ok) => { if (ok) { setText(''); setPref(''); void load(); } })}>Send request</button>
      </div>
      <div className="apt-card">
        <div className="apt-card-title"><Icon name="receipt" size="1rem" /> Requests</div>
        {list === null && <StateView kind="loading" />}
        {list?.length === 0 && <p className="v-muted">No requests.</p>}
        {list?.map((r) => (
          <div key={r.id} className="apt-req">
            <div className="apt-person"><strong>{r.category}</strong><span className={`apt-pill${r.status === 'completed' ? ' ok' : ''}`}>{STATUS[r.status] ?? r.status}</span>
              {['open', 'accepted', 'scheduled'].includes(r.status) && <button className="v-btn" disabled={busy} onClick={() => void act('maintenanceCancel', r.id).then(() => load())}>Cancel</button>}</div>
            <div className="v-muted">{r.description}</div>
            {(r.scheduled_for || r.note || r.staff_name) && <div className="v-muted small">{[r.staff_name, r.scheduled_for, r.note].filter(Boolean).join(' · ')}</div>}
          </div>
        ))}
      </div>
    </div>
  );
}
