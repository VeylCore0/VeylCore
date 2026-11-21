import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { BrandHeader, CloseHint, Icon, SearchBox, StateView, announceReady, nui, useNuiMessage, type NuiResponse } from '@veyl/ui';

// ---------------------------------------------------------------------------
// Types (see resources/[veyl]/veyl_doorlocks/server/main.lua)
// ---------------------------------------------------------------------------
type GradeMap = Record<string, number>;
interface Settings {
  locked: boolean; autoLock: number; distance: number; hidePrompt: boolean;
  access: { jobs: GradeMap; gangs: GradeMap; requireDuty: boolean; citizens: { citizenid: string; name: string }[]; items: string[]; keys: boolean; managers: GradeMap };
  breach: { lockpick: boolean; lockpickChance: number; ram: boolean; ramJobs: GradeMap; relock: number };
}
interface Entity { model: number; x: number; y: number; z: number; heading: number }
interface DoorRow { id: number; name: string; entities: Entity[]; settings: Settings; locked: boolean; x: number; y: number; z: number }
interface Group { name: string; label: string; grades: { grade: number; name: string }[] }
interface Draft { id?: number; name: string; entities: Entity[]; settings: Settings }
interface EditorData {
  doors: DoorRow[]; jobs: Group[]; gangs: Group[]; items: { name: string; label: string }[];
  limits: { distance: [number, number]; autoLock: number; maxEntities: number }; player: { x: number; y: number; z: number };
  focus?: { draft?: Draft; cancelled?: boolean };
}
interface ManageData {
  id: number; name: string; locked: boolean; businessOpen: boolean; grants: { id: number; name: string; expires: number }[]; keys: number; maxKeys: number;
  maxHours: number; keysEnabled: boolean; serverTime: number; phone: boolean;
}
type Screen = { view: 'editor'; data: EditorData } | { view: 'manage'; data: ManageData };
type Say = (k: 'ok' | 'error', t: string) => void;

const api = <T,>(name: string, ...args: unknown[]) => nui<T>('api', { name, args }) as Promise<NuiResponse<T>>;
const newOp = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
const blank = (): Settings => ({
  locked: true, autoLock: 0, distance: 2, hidePrompt: false,
  access: { jobs: {}, gangs: {}, requireDuty: false, citizens: [], items: [], keys: true, managers: {} },
  breach: { lockpick: false, lockpickChance: 0.35, ram: false, ramJobs: {}, relock: 300 },
});
const clone = <T,>(v: T): T => JSON.parse(JSON.stringify(v));
const dist = (a: { x: number; y: number; z: number }, b: { x: number; y: number; z: number }) => Math.hypot(a.x - b.x, a.y - b.y, a.z - b.z);

export function App() {
  const [screen, setScreen] = useState<Screen | null>(null);
  const [openId, setOpenId] = useState(0);
  const [status, setStatus] = useState<{ visible: boolean; name?: string; locked?: boolean; open?: boolean }>({ visible: false });
  const [select, setSelect] = useState<{ visible: boolean; count?: number; max?: number; aiming?: boolean; already?: boolean; isDoor?: boolean }>({ visible: false });
  const [toast, setToast] = useState<{ kind: 'ok' | 'error'; text: string } | null>(null);
  const timer = useRef<number>();
  useEffect(() => announceReady(), []);
  const say: Say = useCallback((kind, text) => { setToast({ kind, text }); window.clearTimeout(timer.current); timer.current = window.setTimeout(() => setToast(null), 3500); }, []);

  useNuiMessage<Screen>('door:open', (d) => { setScreen(d); setOpenId((n) => n + 1); });
  useNuiMessage('door:close', () => setScreen(null));
  useNuiMessage<typeof status>('door:status', (d) => setStatus(d ?? { visible: false }));
  useNuiMessage<typeof select>('door:select', (d) => setSelect(d ?? { visible: false }));

  const close = useCallback(() => { void nui('close'); setScreen(null); }, []);
  useEffect(() => {
    if (!screen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      const t = e.target as HTMLElement;
      if (t && ['INPUT', 'TEXTAREA', 'SELECT'].includes(t.tagName)) { t.blur(); return; }
      if (document.querySelector('.v-dialog-backdrop')) return;
      close();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [screen, close]);

  return (
    <>
      {status.visible && !screen && !select.visible && (
        <div className={`dl-status ${status.locked ? 'locked' : 'open'}`} aria-live="polite">
          <Icon name={status.locked ? 'lock' : 'unlock'} size="1rem" />
          <span>{status.name}</span>
          <em>{status.locked ? 'Locked' : status.open ? 'Open for business' : 'Unlocked'}</em>
        </div>
      )}
      {select.visible && (
        <div className="dl-select v-panel">
          <div className="dl-select-title"><Icon name="door" size="1rem" /> Pick the door{(select.max ?? 1) > 1 ? 's' : ''} for this entry</div>
          <div className={`dl-select-state ${select.aiming ? (select.isDoor ? 'ok' : 'warn') : ''}`}>
            {!select.aiming ? 'Aim at a door' : select.already ? 'Selected · E to remove' : select.isDoor ? 'Door found · E to add' : 'Object found (not a known door) · E to add anyway'}
          </div>
          <div className="dl-keys"><span><kbd>E</kbd> add / remove</span><span><kbd>Enter</kbd> done ({select.count}/{select.max})</span><span><kbd>Backspace</kbd> cancel</span></div>
        </div>
      )}
      {screen && (
        <div className="dl-root">
          <header className="dl-header"><BrandHeader section={screen.view === 'editor' ? 'Door locks' : 'Door access'} /><CloseHint onClose={close} /></header>
          <main key={openId} className="dl-main">
            {screen.view === 'editor' && <Editor data={screen.data} say={say} />}
            {screen.view === 'manage' && <Manage initial={screen.data} say={say} />}
          </main>
        </div>
      )}
      {toast && <div className={`v-toast-inline ${toast.kind === 'error' ? 'error' : 'success'}`} role="alert"><Icon name={toast.kind === 'error' ? 'alert' : 'check'} size="1rem" />{toast.text}</div>}
    </>
  );
}

// ---------------------------------------------------------------------------
// Editor
// ---------------------------------------------------------------------------
function Editor({ data, say }: { data: EditorData; say: Say }) {
  const [doors, setDoors] = useState(data.doors);
  const [draft, setDraft] = useState<Draft | null>(data.focus?.draft ? { ...data.focus.draft, settings: data.focus.draft.settings ?? blank() } : null);
  const [search, setSearch] = useState('');
  const [confirmDelete, setConfirmDelete] = useState<DoorRow | null>(null);
  const [logFor, setLogFor] = useState<{ door: DoorRow; rows: { citizenid: string; action: string; detail?: string; at: number }[] } | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => { if (data.focus?.cancelled) say('error', 'Door picking cancelled'); }, [data.focus, say]);

  const list = useMemo(() => {
    const q = search.trim().toLowerCase();
    return doors.filter((d) => !q || d.name.toLowerCase().includes(q) || String(d.id) === q)
      .map((d) => ({ ...d, dist: dist(d, data.player) })).sort((a, b) => a.dist - b.dist);
  }, [doors, search, data.player]);

  const reload = async () => { const r = await api<EditorData>('adminData'); if (r.ok && r.data) setDoors(r.data.doors); };
  const pick = (d: Draft) => void nui('pickDoors', { draft: d });

  if (draft) return <DoorForm data={data} draft={draft} busy={busy} onCancel={() => setDraft(null)} onPick={pick}
    onSave={async (d) => {
      setBusy(true);
      const r = await api<{ id: number }>('adminSave', d);
      setBusy(false);
      say(r.ok ? 'ok' : 'error', r.message ?? (r.ok ? 'Saved' : 'Could not save'));
      if (r.ok) { setDraft(null); await reload(); }
    }} />;

  return (
    <div className="dl-panel v-panel">
      <div className="dl-toolbar">
        <div><h2>Doors</h2><div className="v-muted">{doors.length} registered · nearest first</div></div>
        <div className="dl-toolbar-right">
          <SearchBox value={search} onChange={setSearch} placeholder="Search name or #id…" />
          <button className="v-btn primary" onClick={() => pick({ name: '', entities: [], settings: blank() })}><Icon name="plus" size="1rem" /> New door</button>
        </div>
      </div>
      <div className="dl-list v-scroll">
        {list.length === 0 && <StateView kind="empty" message={doors.length ? 'No doors match.' : 'No doors yet. Press "New door", aim at a door in the world and press E.'} />}
        {list.map((d) => (
          <div key={d.id} className="dl-row">
            <span className={`dl-lock ${d.locked ? 'locked' : 'open'}`}><Icon name={d.locked ? 'lock' : 'unlock'} size="1rem" /></span>
            <div className="dl-row-main">
              <div className="dl-row-name">{d.name} <span className="v-muted">#{d.id}</span></div>
              <div className="v-muted small">{summary(d.settings, data)} · {d.entities.length} door{d.entities.length === 1 ? '' : 's'} · {Math.round(d.dist)} m away</div>
            </div>
            <div className="dl-row-actions">
              <button className="v-btn" disabled={busy} onClick={() => void api<{ locked: boolean }>('adminToggle', d.id).then((r) => { say(r.ok ? 'ok' : 'error', r.message ?? ''); if (r.ok) setDoors((all) => all.map((x) => (x.id === d.id ? { ...x, locked: r.data!.locked } : x))); })}>{d.locked ? 'Unlock' : 'Lock'}</button>
              <button className="v-btn" onClick={() => setDraft({ id: d.id, name: d.name, entities: d.entities, settings: clone(d.settings) })}>Edit</button>
              <button className="v-btn" onClick={() => void nui('teleport', { x: d.x, y: d.y, z: d.z })}>Go to</button>
              <button className="v-btn" onClick={() => void api<{ citizenid: string; action: string; detail?: string; at: number }[]>('adminLog', d.id).then((r) => setLogFor({ door: d, rows: r.data ?? [] }))}>Log</button>
              <button className="v-icon-btn" aria-label={`Delete ${d.name}`} onClick={() => setConfirmDelete(d)}><Icon name="close" size="0.9rem" /></button>
            </div>
          </div>
        ))}
      </div>
      {confirmDelete && (
        <div className="v-dialog-backdrop" role="dialog" aria-modal="true">
          <div className="v-panel dl-dialog">
            <h3>Delete “{confirmDelete.name}”?</h3>
            <p className="v-muted">The door unlocks for everyone and its access rules and temporary grants are removed. This cannot be undone.</p>
            <div className="dl-row-end">
              <button className="v-btn" onClick={() => setConfirmDelete(null)}>Cancel</button>
              <button className="v-btn danger" disabled={busy} onClick={async () => {
                setBusy(true);
                const r = await api('adminDelete', confirmDelete.id);
                setBusy(false);
                say(r.ok ? 'ok' : 'error', r.message ?? '');
                setConfirmDelete(null);
                if (r.ok) setDoors((all) => all.filter((x) => x.id !== confirmDelete.id));
              }}>Delete door</button>
            </div>
          </div>
        </div>
      )}
      {logFor && (
        <div className="v-dialog-backdrop" role="dialog" aria-modal="true" onClick={(e) => { if (e.target === e.currentTarget) setLogFor(null); }}>
          <div className="v-panel dl-dialog wide">
            <h3>{logFor.door.name} · activity</h3>
            <div className="dl-log v-scroll">
              {logFor.rows.length === 0 && <p className="v-muted">Nothing logged yet.</p>}
              {logFor.rows.map((r, i) => (
                <div key={i} className="dl-log-row"><span>{new Date(r.at * 1000).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })}</span>
                  <strong>{r.action.replace(/_/g, ' ')}</strong><span className="v-muted">{r.citizenid}{r.detail ? ` · ${r.detail}` : ''}</span></div>
              ))}
            </div>
            <div className="dl-row-end"><button className="v-btn" onClick={() => setLogFor(null)}>Close</button></div>
          </div>
        </div>
      )}
    </div>
  );
}

function summary(s: Settings, data: EditorData) {
  const parts: string[] = [];
  const label = (list: Group[], name: string) => list.find((g) => g.name === name)?.label ?? name;
  Object.keys(s.access.jobs).forEach((j) => parts.push(label(data.jobs, j)));
  Object.keys(s.access.gangs).forEach((g) => parts.push(label(data.gangs, g)));
  if (s.access.citizens.length) parts.push(`${s.access.citizens.length} people`);
  if (s.access.items.length) parts.push(`item: ${s.access.items.join(', ')}`);
  return parts.length ? parts.join(', ') : 'Staff and keys only';
}

function GradeRows({ title, groups, value, onChange, hint }: { title: string; groups: Group[]; value: GradeMap; onChange: (v: GradeMap) => void; hint?: string }) {
  const [add, setAdd] = useState('');
  const unused = groups.filter((g) => value[g.name] === undefined);
  return (
    <div className="dl-field">
      <div className="dl-field-title">{title}</div>
      {hint && <div className="v-muted small">{hint}</div>}
      {Object.entries(value).map(([name, grade]) => {
        const g = groups.find((x) => x.name === name);
        return (
          <div key={name} className="dl-grade-row">
            <strong>{g?.label ?? name}</strong>
            <span className="v-muted">from</span>
            <select className="v-input" value={grade} onChange={(e) => onChange({ ...value, [name]: Number(e.target.value) })} aria-label={`${name} minimum grade`}>
              {(g?.grades.length ? g.grades : [{ grade: 0, name: 'Any' }]).map((x) => <option key={x.grade} value={x.grade}>{x.grade} · {x.name}</option>)}
            </select>
            <button className="v-icon-btn" aria-label={`Remove ${name}`} onClick={() => { const n = { ...value }; delete n[name]; onChange(n); }}><Icon name="close" size="0.85rem" /></button>
          </div>
        );
      })}
      {unused.length > 0 && (
        <div className="dl-grade-row">
          <select className="v-input" value={add} onChange={(e) => setAdd(e.target.value)} aria-label={`Add to ${title}`}>
            <option value="">Add…</option>
            {unused.map((g) => <option key={g.name} value={g.name}>{g.label}</option>)}
          </select>
          <button className="v-btn" disabled={!add} onClick={() => { onChange({ ...value, [add]: 0 }); setAdd(''); }}>Add</button>
        </div>
      )}
    </div>
  );
}

function DoorForm({ data, draft, busy, onCancel, onPick, onSave }: { data: EditorData; draft: Draft; busy: boolean; onCancel: () => void; onPick: (d: Draft) => void; onSave: (d: Draft) => Promise<void> }) {
  const [d, setD] = useState<Draft>(draft);
  const [lookup, setLookup] = useState('');
  const [manual, setManual] = useState('');
  const [itemAdd, setItemAdd] = useState('');
  const s = d.settings;
  const set = (patch: Partial<Settings>) => setD({ ...d, settings: { ...s, ...patch } });
  const access = (patch: Partial<Settings['access']>) => set({ access: { ...s.access, ...patch } });
  const breach = (patch: Partial<Settings['breach']>) => set({ breach: { ...s.breach, ...patch } });
  const addCitizen = async () => {
    const r = await api<{ citizenid: string; name: string }>('adminLookup', Number(lookup));
    if (r.ok && r.data && !s.access.citizens.some((c) => c.citizenid === r.data!.citizenid)) access({ citizens: [...s.access.citizens, r.data] });
    setLookup('');
  };
  const valid = d.name.trim().length > 0 && d.entities.length > 0;
  return (
    <div className="dl-form v-panel">
      <div className="dl-toolbar">
        <div><h2>{d.id ? `Edit door #${d.id}` : 'New door'}</h2><div className="v-muted">{d.entities.length} door{d.entities.length === 1 ? '' : 's'} captured</div></div>
        <div className="dl-toolbar-right">
          <button className="v-btn" onClick={() => onPick(d)}><Icon name="door" size="1rem" /> {d.entities.length ? 'Re-pick doors' : 'Pick doors'}</button>
          <button className="v-btn" onClick={onCancel}>Cancel</button>
          <button className="v-btn primary" disabled={!valid || busy} onClick={() => void onSave(d)}>{busy ? 'Saving…' : 'Save door'}</button>
        </div>
      </div>
      <div className="dl-form-grid v-scroll">
        <section className="dl-card">
          <div className="dl-card-title"><Icon name="door" size="1rem" /> Door</div>
          <label className="dl-field"><span className="dl-field-title">Name</span>
            <input className="v-input" maxLength={48} value={d.name} onChange={(e) => setD({ ...d, name: e.target.value })} placeholder="e.g. MRPD Front Desk" autoFocus /></label>
          {d.entities.map((e, i) => <div key={i} className="v-muted small dl-mono">#{i + 1} model {e.model} · {e.x.toFixed(2)}, {e.y.toFixed(2)}, {e.z.toFixed(2)}</div>)}
          <label className="dl-check"><input type="checkbox" checked={s.locked} onChange={(e) => set({ locked: e.target.checked })} /> Locked by default</label>
          <label className="dl-field"><span className="dl-field-title">Interaction distance · {s.distance.toFixed(1)} m</span>
            <input type="range" min={data.limits.distance[0]} max={data.limits.distance[1]} step={0.5} value={s.distance} onChange={(e) => set({ distance: Number(e.target.value) })} /></label>
          <label className="dl-field"><span className="dl-field-title">Lock again automatically</span>
            <select className="v-input" value={s.autoLock} onChange={(e) => set({ autoLock: Number(e.target.value) })}>
              {[0, 5, 10, 30, 60, 300, 900, 3600].filter((v) => v <= data.limits.autoLock).map((v) => <option key={v} value={v}>{v === 0 ? 'Never' : v < 60 ? `After ${v} seconds` : `After ${v / 60} minute${v === 60 ? '' : 's'}`}</option>)}
            </select></label>
          <label className="dl-check"><input type="checkbox" checked={s.hidePrompt} onChange={(e) => set({ hidePrompt: e.target.checked })} /> Hidden (no prompt; scripts only)</label>
        </section>

        <section className="dl-card">
          <div className="dl-card-title"><Icon name="key" size="1rem" /> Who can open it</div>
          <GradeRows title="Jobs" groups={data.jobs} value={s.access.jobs} onChange={(v) => access({ jobs: v })} hint="Members at or above the chosen grade." />
          <label className="dl-check"><input type="checkbox" checked={s.access.requireDuty} onChange={(e) => access({ requireDuty: e.target.checked })} /> Job members must be on duty</label>
          <GradeRows title="Gangs" groups={data.gangs} value={s.access.gangs} onChange={(v) => access({ gangs: v })} />
          <div className="dl-field">
            <div className="dl-field-title">Specific people</div>
            {s.access.citizens.map((c) => (
              <div key={c.citizenid} className="dl-grade-row"><strong>{c.name}</strong><span className="v-muted dl-mono">{c.citizenid}</span>
                <button className="v-icon-btn" aria-label={`Remove ${c.name}`} onClick={() => access({ citizens: s.access.citizens.filter((x) => x.citizenid !== c.citizenid) })}><Icon name="close" size="0.85rem" /></button></div>
            ))}
            <div className="dl-grade-row">
              <input className="v-input" inputMode="numeric" value={lookup} onChange={(e) => setLookup(e.target.value.replace(/\D/g, ''))} placeholder="Online player server id" />
              <button className="v-btn" disabled={!lookup} onClick={() => void addCitizen()}>Add</button>
              <input className="v-input" value={manual} onChange={(e) => setManual(e.target.value.replace(/[^\w]/g, '').slice(0, 16))} placeholder="or citizen id" />
              <button className="v-btn" disabled={!manual || s.access.citizens.some((c) => c.citizenid === manual)} onClick={() => { access({ citizens: [...s.access.citizens, { citizenid: manual, name: manual }] }); setManual(''); }}>Add</button>
            </div>
          </div>
          <div className="dl-field">
            <div className="dl-field-title">Items that open it</div>
            <div className="dl-chips">{s.access.items.map((i) => <button key={i} className="dl-chip" onClick={() => access({ items: s.access.items.filter((x) => x !== i) })}>{data.items.find((x) => x.name === i)?.label ?? i} ✕</button>)}</div>
            <div className="dl-grade-row">
              <select className="v-input" value={itemAdd} onChange={(e) => setItemAdd(e.target.value)}>
                <option value="">Add an item (e.g. a keycard)…</option>
                {data.items.filter((i) => !s.access.items.includes(i.name)).map((i) => <option key={i.name} value={i.name}>{i.label}</option>)}
              </select>
              <button className="v-btn" disabled={!itemAdd} onClick={() => { access({ items: [...s.access.items, itemAdd] }); setItemAdd(''); }}>Add</button>
            </div>
          </div>
          <label className="dl-check"><input type="checkbox" checked={s.access.keys} onChange={(e) => access({ keys: e.target.checked })} /> Physical keys for this door work</label>
        </section>

        <section className="dl-card">
          <div className="dl-card-title"><Icon name="briefcase" size="1rem" /> Business controls</div>
          <GradeRows title="Managers" groups={data.jobs} value={s.access.managers} onChange={(v) => access({ managers: v })}
            hint="Can keep the door open for business, give people temporary access, cut keys and change the locks." />
          <div className="dl-card-title"><Icon name="shield" size="1rem" /> Breaching</div>
          <label className="dl-check"><input type="checkbox" checked={s.breach.lockpick} onChange={(e) => breach({ lockpick: e.target.checked })} /> Can be lockpicked</label>
          {s.breach.lockpick && (
            <label className="dl-field"><span className="dl-field-title">Lockpick success chance · {Math.round(s.breach.lockpickChance * 100)}%</span>
              <input type="range" min={0.05} max={0.95} step={0.05} value={s.breach.lockpickChance} onChange={(e) => breach({ lockpickChance: Number(e.target.value) })} /></label>
          )}
          <label className="dl-check"><input type="checkbox" checked={s.breach.ram} onChange={(e) => breach({ ram: e.target.checked })} /> Can be breached with a door ram</label>
          {s.breach.ram && <GradeRows title="Ram allowed for (on duty)" groups={data.jobs} value={s.breach.ramJobs} onChange={(v) => breach({ ramJobs: v })} hint="Leave empty to let anyone with a ram breach it." />}
          {(s.breach.lockpick || s.breach.ram) && (
            <label className="dl-field"><span className="dl-field-title">After a breach, lock again</span>
              <select className="v-input" value={s.breach.relock} onChange={(e) => breach({ relock: Number(e.target.value) })}>
                {[0, 60, 120, 300, 600, 1800, 3600].filter((v) => v <= data.limits.autoLock).map((v) => <option key={v} value={v}>{v === 0 ? 'Never (stays open)' : `After ${v / 60} minute${v === 60 ? '' : 's'}`}</option>)}
              </select></label>
          )}
        </section>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Manager panel (business controls)
// ---------------------------------------------------------------------------
function Manage({ initial, say }: { initial: ManageData; say: Say }) {
  const [m, setM] = useState(initial);
  const [target, setTarget] = useState('');
  const [hours, setHours] = useState(8);
  const [busy, setBusy] = useState(false);
  const [confirmLocks, setConfirmLocks] = useState(false);
  const reload = async () => { const r = await api<ManageData>('manage', m.id); if (r.ok && r.data) setM(r.data); };
  const act = async (name: string, ...args: unknown[]) => {
    setBusy(true);
    const r = await api(name, ...args);
    setBusy(false);
    say(r.ok ? 'ok' : 'error', r.message ?? (r.ok ? 'Done' : 'Failed'));
    if (r.ok) await reload();
    return r.ok;
  };
  const digits = target.replace(/\D/g, '');
  const t = m.phone && digits.length === 7 ? { number: `${digits.slice(0, 3)}-${digits.slice(3)}` } : digits.length > 0 && digits.length <= 4 ? { serverId: Number(digits) } : null;
  const left = (ts: number) => { const s = ts - m.serverTime; return s > 3600 ? `${Math.round(s / 3600)} h left` : `${Math.max(1, Math.round(s / 60))} min left`; };
  return (
    <div className="dl-manage v-panel">
      <div className="dl-toolbar"><div><h2>{m.name}</h2><div className={`dl-pill ${m.locked ? 'locked' : 'open'}`}>{m.locked ? 'Locked' : m.businessOpen ? 'Open for business' : 'Unlocked'}</div></div></div>
      <div className="dl-form-grid">
        <section className="dl-card">
          <div className="dl-card-title"><Icon name="briefcase" size="1rem" /> Opening hours</div>
          <p className="v-muted small">Open keeps the door unlocked (no automatic locking) until you close it.</p>
          {m.businessOpen
            ? <button className="v-btn" disabled={busy} onClick={() => void act('businessOpen', m.id, false)}>Close and lock</button>
            : <button className="v-btn primary" disabled={busy} onClick={() => void act('businessOpen', m.id, true)}>Open for business</button>}
        </section>
        <section className="dl-card">
          <div className="dl-card-title"><Icon name="users" size="1rem" /> Temporary access</div>
          {m.grants.length === 0 && <p className="v-muted small">No one has temporary access.</p>}
          {m.grants.map((g) => <div key={g.id} className="dl-grade-row"><strong>{g.name}</strong><span className="v-muted">{left(g.expires)}</span><button className="v-btn" disabled={busy} onClick={() => void act('revoke', g.id)}>Remove</button></div>)}
          <div className="dl-grade-row">
            <input className="v-input" value={target} onChange={(e) => setTarget(e.target.value)} placeholder={m.phone ? 'Phone number or nearby player id' : 'Nearby player id'} />
            <select className="v-input dl-narrow" value={hours} onChange={(e) => setHours(Number(e.target.value))}>{[1, 4, 8, 24, 72, 168].filter((h) => h <= m.maxHours).map((h) => <option key={h} value={h}>{h} h</option>)}</select>
            <button className="v-btn primary" disabled={!t || busy} onClick={() => void act('grant', m.id, t, hours).then((ok) => ok && setTarget(''))}>Give access</button>
          </div>
        </section>
        <section className="dl-card">
          <div className="dl-card-title"><Icon name="key" size="1rem" /> Keys</div>
          {!m.keysEnabled ? <p className="v-muted small">This door does not use physical keys.</p> : (
            <>
              <p className="v-muted small">{m.keys} of {m.maxKeys} keys cut. Keys can be handed to anyone; changing the locks makes all of them useless.</p>
              <button className="v-btn" disabled={busy || m.keys >= m.maxKeys} onClick={() => void act('makeKey', m.id, newOp())}>Cut a key</button>
              <button className="v-btn danger" disabled={busy} onClick={() => setConfirmLocks(true)}>Change the locks</button>
            </>
          )}
        </section>
      </div>
      {confirmLocks && (
        <div className="v-dialog-backdrop" role="dialog" aria-modal="true">
          <div className="v-panel dl-dialog">
            <h3>Change the locks on {m.name}?</h3>
            <p className="v-muted">Every key cut so far stops working. Job, gang and temporary access are not affected.</p>
            <div className="dl-row-end">
              <button className="v-btn" onClick={() => setConfirmLocks(false)}>Cancel</button>
              <button className="v-btn danger" disabled={busy} onClick={() => void act('changeLocks', m.id).then(() => setConfirmLocks(false))}>Change the locks</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
