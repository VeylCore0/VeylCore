import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { BrandHeader, CloseHint, Icon, SearchBox, StateView, Tabs, announceReady, money, nui, useNuiMessage, type NuiResponse } from '@veyl/ui';

// ---------------------------------------------------------------------------
// Types (see resources/[veyl]/veyl_management/server/main.lua: view)
// ---------------------------------------------------------------------------
interface Grade { grade: number; name: string; pay?: number; isboss: boolean }
interface Member { citizenid: string; name: string; grade: number; gradeName: string; online: boolean; onduty: boolean; primary: boolean; self: boolean; manageable: boolean }
interface Nearby { id: number; distance: number }
interface View { kind: 'job' | 'gang'; name: string; label: string; myGrade: number; grades: Grade[]; members: Member[]; nearby: Nearby[]; offerSeconds: number }
type Tab = 'members' | 'hire';

const api = <T,>(name: string, ...args: unknown[]) => nui<T>('api', { name, args }) as Promise<NuiResponse<T>>;

export function App() {
  const [view, setView] = useState<View | null>(null);
  const [tab, setTab] = useState<Tab>('members');
  const [toast, setToast] = useState<{ kind: 'ok' | 'error'; text: string } | null>(null);
  const timer = useRef<number>();
  useEffect(() => announceReady(), []);
  const say = useCallback((kind: 'ok' | 'error', text: string) => {
    setToast({ kind, text });
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setToast(null), 3500);
  }, []);

  useNuiMessage<View>('management:open', (v) => { setView(v); setTab('members'); });
  useNuiMessage('management:close', () => setView(null));

  const close = useCallback(() => { void nui('close'); setView(null); }, []);
  useEffect(() => {
    if (!view) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      const t = e.target as HTMLElement;
      if (t && ['INPUT', 'SELECT'].includes(t.tagName)) { t.blur(); return; }
      if (document.querySelector('.v-dialog-backdrop')) return;
      close();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [view, close]);

  if (!view) return toast ? <Toast toast={toast} /> : null;
  const refresh = async () => { const r = await api<View>('open', view.kind, view.name); if (r.ok && r.data) setView(r.data); };
  const apply = (r: NuiResponse<View>) => {
    if (r.ok && r.data) setView(r.data);
    say(r.ok ? 'ok' : 'error', r.message ?? (r.ok ? 'Done' : 'Something went wrong'));
  };

  return (
    <>
      <div className="mg-root">
        <header className="mg-header"><BrandHeader section={view.kind === 'gang' ? 'Gang' : 'Management'} /><CloseHint onClose={close} /></header>
        <main className="mg-main v-panel">
          <div className="mg-toolbar">
            <div>
              <h2>{view.label}</h2>
              <div className="v-muted small">{view.members.length} member{view.members.length === 1 ? '' : 's'} · {view.members.filter((m) => m.online).length} online
                {view.kind === 'job' && <> · {view.members.filter((m) => m.onduty).length} on duty</>}</div>
            </div>
            <Tabs<Tab> value={tab} onChange={setTab} tabs={[{ id: 'members', label: view.kind === 'gang' ? 'Members' : 'Employees' }, { id: 'hire', label: view.kind === 'gang' ? 'Recruit' : 'Hire' }]} />
          </div>
          {tab === 'members' ? <Members view={view} apply={apply} /> : <Hire view={view} say={say} refresh={refresh} />}
        </main>
      </div>
      {toast && <Toast toast={toast} />}
    </>
  );
}

function Toast({ toast }: { toast: { kind: 'ok' | 'error'; text: string } }) {
  return <div className={`v-toast-inline ${toast.kind === 'error' ? 'error' : 'success'}`} role="alert"><Icon name={toast.kind === 'error' ? 'alert' : 'check'} size="1rem" />{toast.text}</div>;
}

function Members({ view, apply }: { view: View; apply: (r: NuiResponse<View>) => void }) {
  const [search, setSearch] = useState('');
  const [busy, setBusy] = useState<string | null>(null);
  const [firing, setFiring] = useState<Member | null>(null);
  const lower = view.grades.filter((g) => g.grade < view.myGrade);
  const list = useMemo(() => {
    const q = search.trim().toLowerCase();
    return view.members.filter((m) => !q || m.name.toLowerCase().includes(q) || m.gradeName.toLowerCase().includes(q))
      .sort((a, b) => b.grade - a.grade || Number(b.online) - Number(a.online) || a.name.localeCompare(b.name));
  }, [view.members, search]);

  const setGrade = async (m: Member, grade: number) => {
    setBusy(m.citizenid);
    apply(await api<View>('setGrade', view.kind, view.name, m.citizenid, grade));
    setBusy(null);
  };

  return (
    <>
      <div className="mg-sub"><SearchBox value={search} onChange={setSearch} placeholder="Search name or rank…" /></div>
      <div className="mg-list v-scroll">
        {list.length === 0 && <StateView kind="empty" message={view.members.length ? 'Nobody matches.' : 'No members yet.'} />}
        {list.map((m) => (
          <div key={m.citizenid} className="mg-row">
            <span className={`mg-dot ${m.onduty ? 'duty' : m.online ? 'online' : ''}`} title={m.onduty ? 'On duty' : m.online ? 'Online' : 'Offline'} />
            <div className="mg-row-main">
              <div className="mg-name">{m.name}{m.self && <span className="mg-pill">You</span>}{!m.primary && <span className="mg-pill muted" title="This is not their main job">Side job</span>}</div>
              <div className="v-muted small">{m.onduty ? 'On duty' : m.online ? 'Online' : 'Offline'}</div>
            </div>
            <div className="mg-row-actions">
              {m.manageable ? (
                <>
                  <select className="v-input mg-select" aria-label={`Rank for ${m.name}`} value={m.grade} disabled={busy === m.citizenid}
                    onChange={(e) => void setGrade(m, Number(e.target.value))}>
                    {lower.map((g) => <option key={g.grade} value={g.grade}>{g.name}</option>)}
                  </select>
                  <button className="v-btn danger" disabled={busy === m.citizenid} onClick={() => setFiring(m)}>{view.kind === 'gang' ? 'Kick' : 'Fire'}</button>
                </>
              ) : <span className="mg-rank">{m.gradeName}</span>}
            </div>
          </div>
        ))}
      </div>
      <div className="mg-ranks">
        {view.grades.map((g) => <span key={g.grade} className={g.grade === view.myGrade ? 'mine' : ''}>{g.name}{g.isboss && <Icon name="star" size="0.75rem" />}{g.pay !== undefined && <em>{money(g.pay)}</em>}</span>)}
      </div>
      {firing && (
        <div className="v-dialog-backdrop" role="dialog" aria-modal="true">
          <div className="v-panel mg-dialog">
            <h3>{view.kind === 'gang' ? 'Kick' : 'Fire'} {firing.name}?</h3>
            <p className="v-muted">They lose their {firing.gradeName} rank at {view.label}{firing.online ? ' and are told right away' : ''}. You can hire them again later.</p>
            <div className="mg-end">
              <button className="v-btn" onClick={() => setFiring(null)}>Cancel</button>
              <button className="v-btn danger" disabled={busy !== null} onClick={async () => {
                const m = firing;
                setBusy(m.citizenid);
                apply(await api<View>('fire', view.kind, view.name, m.citizenid));
                setBusy(null);
                setFiring(null);
              }}>{view.kind === 'gang' ? 'Kick out' : 'Fire'}</button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}

function Hire({ view, say, refresh }: { view: View; say: (k: 'ok' | 'error', t: string) => void; refresh: () => Promise<void> }) {
  const lower = view.grades.filter((g) => g.grade < view.myGrade);
  const [grade, setGrade] = useState(lower[0]?.grade ?? 0);
  const [busy, setBusy] = useState<number | null>(null);
  const [sent, setSent] = useState<Record<number, boolean>>({});

  return (
    <div className="mg-hire">
      <div className="mg-hire-head">
        <p className="v-muted">Stand next to the person and send them an offer. They have {view.offerSeconds} seconds to accept.</p>
        <label className="mg-field">
          <span className="v-muted small">Starting rank</span>
          <select className="v-input mg-select" value={grade} onChange={(e) => setGrade(Number(e.target.value))}>
            {lower.map((g) => <option key={g.grade} value={g.grade}>{g.name}{g.pay !== undefined ? ` · ${money(g.pay)}` : ''}</option>)}
          </select>
        </label>
        <button className="v-btn" onClick={() => void refresh()}><Icon name="reset" size="1rem" /> Refresh</button>
      </div>
      <div className="mg-list v-scroll">
        {lower.length === 0 && <StateView kind="restricted" message="There is no rank below yours to hire into." />}
        {lower.length > 0 && view.nearby.length === 0 && <StateView kind="empty" message="Nobody is close enough. Stand next to the person and press Refresh." />}
        {lower.length > 0 && view.nearby.map((p) => (
          <div key={p.id} className="mg-row">
            <span className="mg-avatar"><Icon name="user" size="1rem" /></span>
            <div className="mg-row-main"><div className="mg-name">Person #{p.id}</div><div className="v-muted small">{p.distance} m away</div></div>
            <div className="mg-row-actions">
              <button className="v-btn primary" disabled={busy !== null || sent[p.id]} onClick={async () => {
                setBusy(p.id);
                const r = await api('hire', view.kind, view.name, p.id, grade);
                setBusy(null);
                if (r.ok) setSent((s) => ({ ...s, [p.id]: true }));
                say(r.ok ? 'ok' : 'error', r.message ?? (r.ok ? 'Offer sent' : 'Could not send the offer'));
              }}>{sent[p.id] ? 'Offer sent' : busy === p.id ? 'Sending…' : 'Send offer'}</button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
