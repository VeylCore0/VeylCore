import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import { BrandHeader, CloseHint, Icon, StateView, announceReady, money, nui, useNuiMessage, type NuiResponse } from '@veyl/ui';

// ---------------------------------------------------------------------------
// Types (see resources/[veyl]/veyl_mdt/server/main.lua)
// ---------------------------------------------------------------------------
interface Warrant { id: number; citizenid?: string; name?: string; reason: string; issued_by: string; status?: string; at: number }
interface ReportRow { id: number; type: string; title: string; author_name?: string; role?: string; at: number }
interface Dashboard { officer: string; warrants: Warrant[]; reports: ReportRow[]; flagged: { plate: string; stolen: number; bolo: number; notes?: string }[] }
interface PersonRow { citizenid: string; firstname?: string; lastname?: string; birthdate?: string; phone?: string; job?: string; warrants?: number }
interface Person extends Omit<PersonRow, 'warrants'> {
  gender?: number | string; nationality?: string; online: boolean; licences: { key: string; label: string; held: boolean }[];
  vehicles: { plate: string; model: string; state: string; stolen?: number; bolo?: number }[];
  citations: { id: number; amount: number; reason: string; officer_name: string; status: string; at: number }[];
  warrants: Warrant[]; reports: ReportRow[]; notes: string; notesBy?: string; sentence?: { months: number; remaining: number } | null;
}
interface Vehicle { plate: string; model?: string; state?: string; registered: boolean; owner?: { citizenid: string; name: string }; stolen: boolean; bolo: boolean; notes: string; flaggedBy?: string }
interface Report { id?: number; type: string; title: string; body: string; author_name?: string; at?: number; people: { citizenid: string; role: string; name?: string }[] }
type Tab = 'dashboard' | 'people' | 'vehicles' | 'reports';
type Say = (k: 'ok' | 'error', t: string) => void;

const api = <T,>(name: string, ...args: unknown[]) => nui<T>('api', { name, args }) as Promise<NuiResponse<T>>;
const date = (at?: number) => (at ? new Date(at * 1000).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }) : '');
const fullName = (p: { firstname?: string; lastname?: string }) => `${p.firstname ?? '?'} ${p.lastname ?? ''}`.trim();
const TYPES = ['incident', 'arrest', 'traffic', 'other'];
const ROLES = ['suspect', 'victim', 'witness', 'officer'];

export function App() {
  const [dash, setDash] = useState<Dashboard | null>(null);
  const [tab, setTab] = useState<Tab>('dashboard');
  const [personId, setPersonId] = useState<string | null>(null);
  const [plate, setPlate] = useState<string | null>(null);
  const [reportId, setReportId] = useState<number | 'new' | null>(null);
  const [toast, setToast] = useState<{ kind: 'ok' | 'error'; text: string } | null>(null);
  const timer = useRef<number>();
  useEffect(() => announceReady(), []);
  const say: Say = useCallback((kind, text) => { setToast({ kind, text }); window.clearTimeout(timer.current); timer.current = window.setTimeout(() => setToast(null), 3500); }, []);

  useNuiMessage<Dashboard>('mdt:open', (d) => { setDash(d); setTab('dashboard'); setPersonId(null); setPlate(null); setReportId(null); });
  useNuiMessage('mdt:close', () => setDash(null));
  const close = useCallback(() => { void nui('close'); setDash(null); }, []);
  useEffect(() => {
    if (!dash) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      const t = e.target as HTMLElement;
      if (t && ['INPUT', 'TEXTAREA', 'SELECT'].includes(t.tagName)) { t.blur(); return; }
      if (document.querySelector('.v-dialog-backdrop')) return;
      close();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [dash, close]);

  if (!dash) return null;
  const go = (t: Tab) => { setTab(t); setPersonId(null); setPlate(null); setReportId(null); };
  const openPerson = (cid: string) => { setTab('people'); setPersonId(cid); };
  const openVehicle = (p: string) => { setTab('vehicles'); setPlate(p); };
  const openReport = (id: number | 'new') => { setTab('reports'); setReportId(id); };
  const refreshDash = async () => { const r = await api<Dashboard>('dashboard'); if (r.ok && r.data) setDash(r.data); };

  const nav: { id: Tab; label: string; icon: 'home' | 'users' | 'car' | 'folder' }[] = [
    { id: 'dashboard', label: 'Dashboard', icon: 'home' }, { id: 'people', label: 'People', icon: 'users' },
    { id: 'vehicles', label: 'Vehicles', icon: 'car' }, { id: 'reports', label: 'Reports', icon: 'folder' },
  ];

  return (
    <div className="mdt-root">
      <div className="mdt-shell">
        <aside className="mdt-nav">
          <BrandHeader section="MDT" />
          <div className="mdt-officer"><Icon name="shield" size="1rem" /> {dash.officer}</div>
          {nav.map((n) => (
            <button key={n.id} className={`mdt-nav-btn${tab === n.id ? ' on' : ''}`} onClick={() => go(n.id)}><Icon name={n.icon} size="1.05rem" /> {n.label}</button>
          ))}
          <div className="mdt-nav-foot"><CloseHint onClose={close} /></div>
        </aside>
        <main className="mdt-main">
          {tab === 'dashboard' && <DashboardView dash={dash} openPerson={openPerson} openVehicle={openVehicle} openReport={openReport} refresh={refreshDash} />}
          {tab === 'people' && (personId ? <PersonView cid={personId} say={say} back={() => setPersonId(null)} openVehicle={openVehicle} openReport={openReport} /> : <PeopleSearch open={openPerson} say={say} />)}
          {tab === 'vehicles' && (plate ? <VehicleView plate={plate} say={say} back={() => setPlate(null)} openPerson={openPerson} /> : <VehicleSearch open={openVehicle} say={say} />)}
          {tab === 'reports' && (reportId !== null ? <ReportEditor id={reportId} say={say} back={() => setReportId(null)} openPerson={openPerson} /> : <ReportList open={openReport} />)}
        </main>
      </div>
      {toast && <div className={`v-toast-inline ${toast.kind === 'error' ? 'error' : 'success'}`} role="alert"><Icon name={toast.kind === 'error' ? 'alert' : 'check'} size="1rem" />{toast.text}</div>}
    </div>
  );
}

// ---------------------------------------------------------------------------
function Section({ title, right, children }: { title: string; right?: ReactNode; children: ReactNode }) {
  return <section className="mdt-section"><header><h3>{title}</h3>{right}</header>{children}</section>;
}
function Back({ onClick, label }: { onClick: () => void; label: string }) {
  return <button className="v-btn link mdt-back" onClick={onClick}><Icon name="back" size="0.9rem" /> {label}</button>;
}
function Search({ placeholder, onSearch, busy }: { placeholder: string; onSearch: (q: string) => void; busy?: boolean }) {
  const [q, setQ] = useState('');
  return (
    <form className="mdt-search" onSubmit={(e) => { e.preventDefault(); onSearch(q); }}>
      <Icon name="search" size="1rem" />
      <input className="v-input" value={q} onChange={(e) => setQ(e.target.value)} placeholder={placeholder} maxLength={40} autoFocus />
      <button className="v-btn primary" disabled={busy}>{busy ? 'Searching…' : 'Search'}</button>
    </form>
  );
}

// ---------------------------------------------------------------------------
function DashboardView({ dash, openPerson, openVehicle, openReport, refresh }: { dash: Dashboard; openPerson: (c: string) => void; openVehicle: (p: string) => void; openReport: (id: number | 'new') => void; refresh: () => void }) {
  return (
    <div className="mdt-page">
      <div className="mdt-page-head"><h2>Dashboard</h2><div className="mdt-row-gap"><button className="v-btn" onClick={refresh}><Icon name="reset" size="0.9rem" /> Refresh</button><button className="v-btn primary" onClick={() => openReport('new')}><Icon name="plus" size="0.9rem" /> New report</button></div></div>
      <div className="mdt-grid">
        <Section title={`Active warrants (${dash.warrants.length})`}>
          {dash.warrants.length === 0 && <div className="v-muted small">No active warrants.</div>}
          {dash.warrants.map((w) => (
            <button key={w.id} className="mdt-item danger" onClick={() => w.citizenid && openPerson(w.citizenid)}>
              <strong>{w.name}</strong><span>{w.reason}</span><em>#{w.id} · {w.issued_by} · {date(w.at)}</em>
            </button>
          ))}
        </Section>
        <Section title="Flagged vehicles">
          {dash.flagged.length === 0 && <div className="v-muted small">No stolen or BOLO vehicles.</div>}
          {dash.flagged.map((f) => (
            <button key={f.plate} className="mdt-item warn" onClick={() => openVehicle(f.plate)}>
              <strong className="mono">{f.plate}</strong><span>{[f.stolen ? 'Stolen' : '', f.bolo ? 'BOLO' : ''].filter(Boolean).join(' · ')}{f.notes ? ` — ${f.notes}` : ''}</span>
            </button>
          ))}
        </Section>
        <Section title="Recent reports">
          {dash.reports.length === 0 && <div className="v-muted small">No reports yet.</div>}
          {dash.reports.map((r) => (
            <button key={r.id} className="mdt-item" onClick={() => openReport(r.id)}>
              <strong>#{r.id} {r.title}</strong><em>{r.type} · {r.author_name} · {date(r.at)}</em>
            </button>
          ))}
        </Section>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
function PeopleSearch({ open, say }: { open: (cid: string) => void; say: Say }) {
  const [rows, setRows] = useState<PersonRow[] | null>(null);
  const [busy, setBusy] = useState(false);
  const run = async (q: string) => {
    setBusy(true);
    const r = await api<PersonRow[]>('searchPeople', q);
    setBusy(false);
    if (r.ok && r.data) setRows(r.data); else say('error', r.message ?? 'Search failed');
  };
  return (
    <div className="mdt-page">
      <div className="mdt-page-head"><h2>People</h2></div>
      <Search placeholder="Name, citizen ID or phone number" onSearch={(q) => void run(q)} busy={busy} />
      <div className="mdt-list">
        {rows === null && <StateView kind="empty" message="Search for a person by name, citizen ID or phone number." />}
        {rows && rows.length === 0 && <StateView kind="empty" message="Nobody matches." />}
        {rows?.map((p) => (
          <button key={p.citizenid} className="mdt-person" onClick={() => open(p.citizenid)}>
            <span className="mdt-avatar"><Icon name="user" size="1.1rem" /></span>
            <span className="mdt-person-main"><strong>{fullName(p)}</strong><em>DOB {p.birthdate ?? '—'} · {p.citizenid} · {p.job}</em></span>
            {(p.warrants ?? 0) > 0 && <span className="mdt-badge danger">WARRANT</span>}
          </button>
        ))}
      </div>
    </div>
  );
}

function PersonView({ cid, say, back, openVehicle, openReport }: { cid: string; say: Say; back: () => void; openVehicle: (p: string) => void; openReport: (id: number | 'new') => void }) {
  const [p, setP] = useState<Person | null>(null);
  const [notes, setNotes] = useState('');
  const [dialog, setDialog] = useState<'warrant' | 'sentence' | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => { void (async () => { const r = await api<Person>('person', cid); if (r.ok && r.data) { setP(r.data); setNotes(r.data.notes); } else say('error', r.message ?? 'Not found'); })(); }, [cid, say]);
  const apply = (r: NuiResponse<Person>) => { if (r.ok && r.data) { setP(r.data); setNotes(r.data.notes); } say(r.ok ? 'ok' : 'error', r.message ?? (r.ok ? 'Saved' : 'Failed')); };
  if (!p) return <div className="mdt-page"><Back onClick={back} label="People" /><StateView kind="loading" /></div>;
  const active = p.warrants.filter((w) => w.status === 'active');
  const unpaid = p.citations.filter((c) => c.status === 'unpaid');
  return (
    <div className="mdt-page">
      <Back onClick={back} label="People" />
      <div className="mdt-profile">
        <span className="mdt-photo"><Icon name="user" size="2.4rem" /></span>
        <div className="mdt-profile-main">
          <h2>{fullName(p)} {p.online && <span className="mdt-badge ok">ONLINE</span>} {active.length > 0 && <span className="mdt-badge danger">{active.length} WARRANT{active.length > 1 ? 'S' : ''}</span>}</h2>
          <div className="mdt-facts">
            <span><label>Citizen ID</label>{p.citizenid}</span><span><label>Date of birth</label>{p.birthdate ?? '—'}</span>
            <span><label>Phone</label>{p.phone ?? '—'}</span><span><label>Job</label>{p.job ?? '—'}</span>
            <span><label>Nationality</label>{p.nationality ?? '—'}</span>
            {p.sentence && <span><label>In prison</label>{p.sentence.remaining} of {p.sentence.months} months left</span>}
          </div>
        </div>
        <div className="mdt-row-gap">
          <button className="v-btn danger" onClick={() => setDialog('warrant')}>Issue warrant</button>
          <button className="v-btn" onClick={() => setDialog('sentence')}>Sentence</button>
        </div>
      </div>
      <div className="mdt-grid">
        <Section title="Licences">
          <div className="mdt-chips">{p.licences.map((l) => <span key={l.key} className={`mdt-chip ${l.held ? 'ok' : 'off'}`}>{l.held ? '✓' : '✕'} {l.label}</span>)}</div>
        </Section>
        <Section title={`Warrants (${active.length} active)`}>
          {p.warrants.length === 0 && <div className="v-muted small">None.</div>}
          {p.warrants.map((w) => (
            <div key={w.id} className={`mdt-item static ${w.status === 'active' ? 'danger' : ''}`}>
              <strong>#{w.id} {w.reason}</strong><em>{w.status} · {w.issued_by} · {date(w.at)}</em>
              {w.status === 'active' && <span className="mdt-row-gap">
                <button className="v-btn small" onClick={async () => apply(await api<Person>('closeWarrant', w.id, 'served'))}>Served</button>
                <button className="v-btn small link" onClick={async () => apply(await api<Person>('closeWarrant', w.id, 'cancelled'))}>Cancel</button>
              </span>}
            </div>
          ))}
        </Section>
        <Section title={`Citations (${unpaid.length} unpaid)`}>
          {p.citations.length === 0 && <div className="v-muted small">None.</div>}
          {p.citations.map((c) => (
            <div key={c.id} className={`mdt-item static ${c.status === 'unpaid' ? 'warn' : ''}`}>
              <strong>#{c.id} {money(c.amount)} · {c.reason}</strong><em>{c.status} · {c.officer_name} · {date(c.at)}</em>
            </div>
          ))}
        </Section>
        <Section title={`Vehicles (${p.vehicles.length})`}>
          {p.vehicles.length === 0 && <div className="v-muted small">None registered.</div>}
          {p.vehicles.map((v) => (
            <button key={v.plate} className={`mdt-item ${v.stolen || v.bolo ? 'warn' : ''}`} onClick={() => openVehicle(v.plate)}>
              <strong className="mono">{v.plate}</strong><span>{v.model}</span><em>{v.state}{v.stolen ? ' · STOLEN' : ''}{v.bolo ? ' · BOLO' : ''}</em>
            </button>
          ))}
        </Section>
        <Section title={`Reports (${p.reports.length})`}>
          {p.reports.length === 0 && <div className="v-muted small">None.</div>}
          {p.reports.map((r) => (
            <button key={r.id} className="mdt-item" onClick={() => openReport(r.id)}><strong>#{r.id} {r.title}</strong><em>{r.role} · {r.type} · {date(r.at)}</em></button>
          ))}
        </Section>
        <Section title="Officer notes" right={<button className="v-btn small primary" disabled={busy || notes === p.notes} onClick={async () => { setBusy(true); apply(await api<Person>('saveNotes', p.citizenid, notes)); setBusy(false); }}>Save</button>}>
          <textarea className="v-input mdt-notes" value={notes} maxLength={2000} onChange={(e) => setNotes(e.target.value)} placeholder="Known associates, cautions, anything other officers should know." />
          {p.notesBy && <div className="v-muted small">Last edited by {p.notesBy}</div>}
        </Section>
      </div>
      {dialog === 'warrant' && <FormDialog title={`Warrant for ${fullName(p)}`} fields={[{ name: 'reason', label: 'Reason', textarea: true }]} submit="Issue warrant" danger
        onCancel={() => setDialog(null)} onSubmit={async (v) => { const r = await api<Person>('issueWarrant', p.citizenid, v.reason); apply(r); if (r.ok) setDialog(null); }} />}
      {dialog === 'sentence' && <FormDialog title={`Sentence ${fullName(p)}`} fields={[{ name: 'months', label: 'Months (1 month = 1 minute in prison)', number: true }, { name: 'reason', label: 'Charges' }]} submit="Send to prison" danger
        onCancel={() => setDialog(null)} onSubmit={async (v) => { const r = await api<Person>('sentence', p.citizenid, Number(v.months), v.reason); apply(r); if (r.ok) setDialog(null); }} />}
    </div>
  );
}

function FormDialog({ title, fields, submit, danger, onCancel, onSubmit }: { title: string; fields: { name: string; label: string; textarea?: boolean; number?: boolean }[]; submit: string; danger?: boolean; onCancel: () => void; onSubmit: (v: Record<string, string>) => Promise<void> }) {
  const [v, setV] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  return (
    <div className="v-dialog-backdrop" role="dialog" aria-modal="true">
      <form className="v-panel mdt-dialog" onSubmit={async (e) => { e.preventDefault(); setBusy(true); await onSubmit(v); setBusy(false); }}>
        <h3>{title}</h3>
        {fields.map((f) => (
          <label key={f.name} className="mdt-field"><span>{f.label}</span>
            {f.textarea ? <textarea className="v-input" rows={4} maxLength={240} value={v[f.name] ?? ''} onChange={(e) => setV({ ...v, [f.name]: e.target.value })} />
              : <input className="v-input" type={f.number ? 'number' : 'text'} min={f.number ? 1 : undefined} maxLength={160} value={v[f.name] ?? ''} onChange={(e) => setV({ ...v, [f.name]: e.target.value })} />}
          </label>
        ))}
        <div className="mdt-row-gap end"><button type="button" className="v-btn" onClick={onCancel}>Cancel</button><button className={`v-btn ${danger ? 'danger' : 'primary'}`} disabled={busy}>{submit}</button></div>
      </form>
    </div>
  );
}

// ---------------------------------------------------------------------------
function VehicleSearch({ open, say }: { open: (p: string) => void; say: Say }) {
  const [list, setList] = useState<{ plate: string; model: string }[] | null>(null);
  const [busy, setBusy] = useState(false);
  const run = async (q: string) => {
    setBusy(true);
    const r = await api<{ exact?: Vehicle; list: { plate: string; model: string }[] }>('searchVehicle', q);
    setBusy(false);
    if (!r.ok || !r.data) return say('error', r.message ?? 'Search failed');
    if (r.data.exact) return open(r.data.exact.plate);
    setList(r.data.list);
  };
  return (
    <div className="mdt-page">
      <div className="mdt-page-head"><h2>Vehicles</h2></div>
      <Search placeholder="Plate" onSearch={(q) => void run(q)} busy={busy} />
      <div className="mdt-list">
        {list === null && <StateView kind="empty" message="Search by plate. Partial plates list close matches." />}
        {list && list.length === 0 && <StateView kind="empty" message="No registered vehicle matches. You can still flag an unregistered plate by typing it in full." />}
        {list?.map((v) => <button key={v.plate} className="mdt-item" onClick={() => open(v.plate)}><strong className="mono">{v.plate}</strong><span>{v.model}</span></button>)}
      </div>
    </div>
  );
}

function VehicleView({ plate, say, back, openPerson }: { plate: string; say: Say; back: () => void; openPerson: (c: string) => void }) {
  const [v, setV] = useState<Vehicle | null>(null);
  const [form, setForm] = useState({ stolen: false, bolo: false, notes: '' });
  useEffect(() => { void (async () => {
    const r = await api<Vehicle>('vehicle', plate);
    const data = r.ok && r.data ? r.data : { plate, registered: false, stolen: false, bolo: false, notes: '' };
    setV(data); setForm({ stolen: data.stolen, bolo: data.bolo, notes: data.notes });
  })(); }, [plate]);
  if (!v) return <div className="mdt-page"><Back onClick={back} label="Vehicles" /><StateView kind="loading" /></div>;
  return (
    <div className="mdt-page">
      <Back onClick={back} label="Vehicles" />
      <div className="mdt-profile">
        <span className="mdt-photo"><Icon name="car" size="2.2rem" /></span>
        <div className="mdt-profile-main">
          <h2 className="mono">{v.plate} {v.stolen && <span className="mdt-badge danger">STOLEN</span>} {v.bolo && <span className="mdt-badge warn">BOLO</span>}</h2>
          <div className="mdt-facts">
            <span><label>Model</label>{v.model ?? '—'}</span><span><label>Status</label>{v.registered ? v.state : 'Not registered'}</span>
            <span><label>Owner</label>{v.owner ? <button className="v-btn link small" onClick={() => openPerson(v.owner!.citizenid)}>{v.owner.name}</button> : '—'}</span>
          </div>
        </div>
      </div>
      <Section title="Flags" right={<button className="v-btn small primary" onClick={async () => {
        const r = await api<Vehicle>('flagVehicle', v.plate, form.stolen, form.bolo, form.notes);
        if (r.ok && r.data) setV(r.data);
        say(r.ok ? 'ok' : 'error', r.message ?? '');
      }}>Save</button>}>
        <div className="mdt-row-gap">
          <label className="mdt-check"><input type="checkbox" checked={form.stolen} onChange={(e) => setForm({ ...form, stolen: e.target.checked })} /> Reported stolen</label>
          <label className="mdt-check"><input type="checkbox" checked={form.bolo} onChange={(e) => setForm({ ...form, bolo: e.target.checked })} /> BOLO (be on the lookout)</label>
        </div>
        <textarea className="v-input mdt-notes" maxLength={400} value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} placeholder="Notes for other officers" />
        {v.flaggedBy && <div className="v-muted small">Last edited by {v.flaggedBy}</div>}
      </Section>
    </div>
  );
}

// ---------------------------------------------------------------------------
function ReportList({ open }: { open: (id: number | 'new') => void }) {
  const [rows, setRows] = useState<ReportRow[] | null>(null);
  const load = async (q?: string) => { const r = await api<ReportRow[]>('reports', q ?? ''); if (r.ok && r.data) setRows(r.data); };
  useEffect(() => { void load(); }, []);
  return (
    <div className="mdt-page">
      <div className="mdt-page-head"><h2>Reports</h2><button className="v-btn primary" onClick={() => open('new')}><Icon name="plus" size="0.9rem" /> New report</button></div>
      <Search placeholder="Search title, text or report number" onSearch={(q) => void load(q)} />
      <div className="mdt-list">
        {rows === null && <StateView kind="loading" />}
        {rows && rows.length === 0 && <StateView kind="empty" message="No reports found." />}
        {rows?.map((r) => <button key={r.id} className="mdt-item" onClick={() => open(r.id)}><strong>#{r.id} {r.title}</strong><em>{r.type} · {r.author_name} · {date(r.at)}</em></button>)}
      </div>
    </div>
  );
}

function ReportEditor({ id, say, back, openPerson }: { id: number | 'new'; say: Say; back: () => void; openPerson: (c: string) => void }) {
  const [r, setR] = useState<Report | null>(id === 'new' ? { type: 'incident', title: '', body: '', people: [] } : null);
  const [busy, setBusy] = useState(false);
  const [find, setFind] = useState<PersonRow[] | null>(null);
  useEffect(() => { if (id !== 'new') void (async () => { const res = await api<Report>('report', id); if (res.ok && res.data) setR(res.data); else say('error', res.message ?? 'Not found'); })(); }, [id, say]);
  if (!r) return <div className="mdt-page"><Back onClick={back} label="Reports" /><StateView kind="loading" /></div>;
  const save = async () => {
    setBusy(true);
    const res = await api<Report>('saveReport', { id: r.id, type: r.type, title: r.title, body: r.body, people: r.people.map((p) => ({ citizenid: p.citizenid, role: p.role })) });
    setBusy(false);
    if (res.ok && res.data) setR(res.data);
    say(res.ok ? 'ok' : 'error', res.message ?? '');
  };
  const searchPeople = async (q: string) => { const res = await api<PersonRow[]>('searchPeople', q); if (res.ok && res.data) setFind(res.data); else say('error', res.message ?? 'Search failed'); };
  return (
    <div className="mdt-page">
      <Back onClick={back} label="Reports" />
      <div className="mdt-page-head">
        <h2>{r.id ? `Report #${r.id}` : 'New report'}</h2>
        <button className="v-btn primary" disabled={busy} onClick={() => void save()}>{busy ? 'Saving…' : 'Save report'}</button>
      </div>
      {r.author_name && <div className="v-muted small">Written by {r.author_name} · {date(r.at)}</div>}
      <div className="mdt-report">
        <div className="mdt-report-main">
          <div className="mdt-row-gap">
            <select className="v-input" value={r.type} onChange={(e) => setR({ ...r, type: e.target.value })}>{TYPES.map((t) => <option key={t} value={t}>{t[0].toUpperCase() + t.slice(1)}</option>)}</select>
            <input className="v-input grow" value={r.title} maxLength={120} placeholder="Title" onChange={(e) => setR({ ...r, title: e.target.value })} />
          </div>
          <textarea className="v-input mdt-body" value={r.body} maxLength={8000} placeholder="What happened, in order. Charges, evidence, statements." onChange={(e) => setR({ ...r, body: e.target.value })} />
        </div>
        <Section title={`People involved (${r.people.length})`}>
          {r.people.map((p, i) => (
            <div key={p.citizenid} className="mdt-involved">
              <button className="v-btn link small" onClick={() => openPerson(p.citizenid)}>{p.name ?? p.citizenid}</button>
              <select className="v-input" value={p.role} onChange={(e) => { const people = [...r.people]; people[i] = { ...p, role: e.target.value }; setR({ ...r, people }); }}>
                {ROLES.map((x) => <option key={x} value={x}>{x}</option>)}
              </select>
              <button className="v-btn small link" aria-label="Remove" onClick={() => setR({ ...r, people: r.people.filter((x) => x.citizenid !== p.citizenid) })}><Icon name="close" size="0.9rem" /></button>
            </div>
          ))}
          <Search placeholder="Add a person: name or citizen ID" onSearch={(q) => void searchPeople(q)} />
          {find?.map((f) => (
            <button key={f.citizenid} className="mdt-item" disabled={r.people.some((p) => p.citizenid === f.citizenid)}
              onClick={() => { setR({ ...r, people: [...r.people, { citizenid: f.citizenid, role: 'suspect', name: fullName(f) }] }); setFind(null); }}>
              <strong>{fullName(f)}</strong><em>{f.citizenid} · DOB {f.birthdate ?? '—'}</em>
            </button>
          ))}
        </Section>
      </div>
    </div>
  );
}
