import { useCallback, useEffect, useState } from 'react';
import { Icon, SearchBox, StateView, Tabs, nui } from '@veyl/ui';
import { api, fmtDate, fmtDateTime, handOff } from '../types';

type Say = (k: 'ok' | 'error', t: string) => void;
type DeskTab = 'directory' | 'parcels' | 'notices';
export interface DeskData { building: string; label: string; tab?: string; directory: boolean }

export function DeskView({ data, toast }: { data: DeskData; toast: Say }) {
  const tabs: { id: DeskTab; label: string }[] = [
    ...(data.directory ? [{ id: 'directory' as const, label: 'Visit a resident' }] : []),
    { id: 'parcels', label: 'Parcels & storage' }, { id: 'notices', label: 'Noticeboard' },
  ];
  const [tab, setTab] = useState<DeskTab>((tabs.find((t) => t.id === data.tab)?.id ?? tabs[0].id) as DeskTab);
  return (
    <div className="apt-desk">
      <Tabs<DeskTab> tabs={tabs} value={tab} onChange={setTab} />
      <div className="apt-tab-body v-scroll">
        {tab === 'directory' && <Directory building={data.building} toast={toast} />}
        {tab === 'parcels' && <Parcels toast={toast} />}
        {tab === 'notices' && <Notices building={data.building} toast={toast} />}
      </div>
    </div>
  );
}

function Directory({ building, toast }: { building: string; toast: Say }) {
  const [q, setQ] = useState('');
  const [list, setList] = useState<{ leaseId: number; name: string }[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [ringing, setRinging] = useState<number | null>(null);
  useEffect(() => {
    const t = window.setTimeout(() => {
      void api<{ leaseId: number; name: string }[]>('directory', building, q).then((r) => { if (r.ok && r.data) { setList(r.data); setError(null); } else setError(r.message ?? 'Unavailable'); });
    }, 250);
    return () => window.clearTimeout(t);
  }, [building, q]);
  const ring = async (id: number) => {
    setRinging(id);
    const r = await api('ringDirectory', id);
    toast(r.ok ? 'ok' : 'error', r.ok ? 'Ringing… you will be told if they let you in.' : r.message ?? 'No one answered');
    window.setTimeout(() => setRinging(null), 4000);
  };
  return (
    <div className="apt-card">
      <p className="v-muted">Only residents who chose to be listed appear here. You will be told which room to go to if they let you in.</p>
      <SearchBox value={q} onChange={setQ} placeholder="Search by name…" />
      {error && <StateView kind="error" message={error} />}
      {!error && list === null && <StateView kind="loading" />}
      {list?.length === 0 && <StateView kind="empty" message="No listed residents match." />}
      {list?.map((r) => (
        <div key={r.leaseId} className="apt-person"><strong>{r.name}</strong>
          <button className="v-btn primary" disabled={ringing !== null} onClick={() => void ring(r.leaseId)}><Icon name="bell" size="0.9rem" /> {ringing === r.leaseId ? 'Ringing…' : 'Ring'}</button></div>
      ))}
    </div>
  );
}

interface Parcel { id: number; sender: string; label: string; status: string; items: { name: string; count: number }[]; at: number; buildingLabel?: string }
interface Recovery { id: string; label: string; until_at: number; open: boolean }

function Parcels({ toast }: { toast: Say }) {
  const [parcels, setParcels] = useState<Parcel[] | null>(null);
  const [recovery, setRecovery] = useState<Recovery[] | null>(null);
  const [busy, setBusy] = useState(false);
  const load = useCallback(async () => {
    const [p, r] = await Promise.all([api<Parcel[]>('parcels'), api<Recovery[]>('recoveryList')]);
    setParcels(p.ok && p.data ? p.data : []); setRecovery(r.ok && r.data ? r.data : []);
  }, []);
  useEffect(() => { void load(); }, [load]);
  const collect = async (id: number) => {
    setBusy(true);
    const r = await api('collectParcel', id);
    setBusy(false);
    toast(r.ok ? 'ok' : 'error', r.message ?? (r.ok ? 'Collected' : 'Failed'));
    if (r.ok) await load();
  };
  return (
    <div className="apt-grid2">
      <div className="apt-card">
        <div className="apt-card-title"><Icon name="box" size="1rem" /> Parcels</div>
        {parcels === null && <StateView kind="loading" />}
        {parcels?.length === 0 && <p className="v-muted">No parcels for you.</p>}
        {parcels?.map((p) => (
          <div key={p.id} className="apt-req">
            <div className="apt-person"><strong>{p.label}</strong><span className="v-muted">from {p.sender} · {fmtDateTime(p.at)}</span>
              {p.status === 'waiting' ? <button className="v-btn primary" disabled={busy} onClick={() => void collect(p.id)}>Collect</button> : <span className="apt-pill">{p.status}</span>}</div>
            <div className="v-muted small">{p.items.map((i) => `${i.count}x ${i.name}`).join(', ')}</div>
          </div>
        ))}
      </div>
      <div className="apt-card">
        <div className="apt-card-title"><Icon name="lock" size="1rem" /> Storage from a previous home</div>
        {recovery === null && <StateView kind="loading" />}
        {recovery?.length === 0 && <p className="v-muted">Nothing to collect.</p>}
        {recovery?.map((r) => (
          <div key={r.id} className="apt-person"><strong>{r.label}</strong>
            <span className="v-muted">{r.open ? `until ${fmtDate(r.until_at)}` : 'collection window closed: ask staff'}</span>
            <button className="v-btn primary" disabled={!r.open} onClick={() => void handOff('openStash', { id: r.id })}>Open</button></div>
        ))}
      </div>
    </div>
  );
}

interface Notice { id: number; author: string; category: string; title: string; body: string; at: number; mine: boolean; canRemove: boolean; reports: number }
const CAT: Record<string, string> = { announcement: 'Announcement', roommate: 'Roommate wanted', event: 'Event', forsale: 'For sale' };

function Notices({ building, toast }: { building: string; toast: Say }) {
  const [data, setData] = useState<{ items: Notice[]; canPost: boolean; staff: boolean } | null>(null);
  const [cat, setCat] = useState('announcement');
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [busy, setBusy] = useState(false);
  const load = useCallback(async () => { const r = await api<{ items: Notice[]; canPost: boolean; staff: boolean }>('notices', building); if (r.ok && r.data) setData(r.data); }, [building]);
  useEffect(() => { void load(); }, [load]);
  const act = async (name: string, ...args: unknown[]) => {
    setBusy(true);
    const r = await api(name, ...args);
    setBusy(false);
    toast(r.ok ? 'ok' : 'error', r.message ?? (r.ok ? 'Done' : 'Failed'));
    if (r.ok) await load();
    return r.ok;
  };
  if (!data) return <StateView kind="loading" />;
  return (
    <div className="apt-grid2">
      <div className="apt-card apt-notices">
        {data.items.length === 0 && <StateView kind="empty" message="The board is empty." />}
        {data.items.map((n) => (
          <article key={n.id} className="apt-notice">
            <div className="apt-person"><span className="apt-pill">{CAT[n.category] ?? n.category}</span><strong>{n.title}</strong></div>
            <p>{n.body}</p>
            <div className="apt-notice-foot v-muted small"><span>{n.author} · {fmtDate(n.at)}{data.staff && n.reports > 0 ? ` · ${n.reports} reports` : ''}</span>
              {n.canRemove ? <button className="v-btn" disabled={busy} onClick={() => void act('noticeRemove', n.id)}>Remove</button>
                : <button className="v-btn" disabled={busy} onClick={() => void act('noticeReport', n.id)}>Report</button>}</div>
          </article>
        ))}
      </div>
      <div className="apt-card">
        <div className="apt-card-title"><Icon name="note" size="1rem" /> Post a notice</div>
        {!data.canPost ? <p className="v-muted">Only residents of this building can post.</p> : (
          <>
            <div className="apt-chips">{Object.entries(CAT).map(([id, label]) => <button key={id} className={`apt-chip${cat === id ? ' on' : ''}`} onClick={() => setCat(id)}>{label}</button>)}</div>
            <input className="v-input" maxLength={60} value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Title" />
            <textarea className="v-input" rows={4} maxLength={400} value={body} onChange={(e) => setBody(e.target.value)} placeholder="Details" />
            <button className="v-btn primary" disabled={busy || !title.trim() || !body.trim()}
              onClick={() => void act('noticePost', building, cat, title, body).then((ok) => { if (ok) { setTitle(''); setBody(''); } })}>Post for 7 days</button>
          </>
        )}
      </div>
    </div>
  );
}
