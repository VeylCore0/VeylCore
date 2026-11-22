import { useCallback, useEffect, useRef, useState } from 'react';
import { CloseHint, Icon, StateView, Tabs, announceReady, nui, useNuiMessage } from '@veyl/ui';

// ---------------------------------------------------------------------------
// Types (see resources/[veyl]/veyl_dispatch/server/main.lua: callView / stateFor)
// ---------------------------------------------------------------------------
interface Call {
  id: number; code: string; title: string; message?: string; street?: string; priority: number; x: number; y: number; z: number;
  at: number; services: string[]; responders: string[]; panic?: boolean; caller?: { name?: string; phone?: string }; distance?: number;
}
interface Unit { id: number; service: string; name: string; grade?: string; status: string }
interface Status { id: string; label: string }
interface State { service: string; calls: Call[]; units: Unit[]; me: { id: number; status: string }; statuses: Status[]; serviceLabels: Record<string, string> }
interface Alert { call: Call; seconds: number; respondKey: string; shownAt: number }

const ago = (at: number) => {
  const s = Math.max(0, Math.floor(Date.now() / 1000 - at));
  return s < 60 ? 'just now' : s < 3600 ? `${Math.floor(s / 60)} min ago` : `${Math.floor(s / 3600)} h ago`;
};
const prio = (p: number) => (p === 1 ? 'urgent' : p === 2 ? 'high' : 'low');

export function App() {
  const [state, setState] = useState<State | null>(null);
  const [open, setOpen] = useState(false);
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [tab, setTab] = useState<'calls' | 'units'>('calls');
  const [, setTick] = useState(0);
  useEffect(() => announceReady(), []);
  useEffect(() => { const id = window.setInterval(() => setTick((n) => n + 1), 15000); return () => window.clearInterval(id); }, []);

  useNuiMessage<State>('dispatch:open', (s) => { setState(s); setOpen(true); });
  useNuiMessage<State>('dispatch:state', (s) => setState(s));
  useNuiMessage('dispatch:close', () => setOpen(false));
  useNuiMessage<Omit<Alert, 'shownAt'>>('dispatch:alert', (a) => {
    const entry = { ...a, shownAt: Date.now() };
    setAlerts((list) => [entry, ...list.filter((x) => x.call.id !== a.call.id)].slice(0, 3));
    window.setTimeout(() => setAlerts((list) => list.filter((x) => x !== entry)), (a.seconds || 9) * 1000);
  });

  const close = useCallback(() => { void nui('close'); setOpen(false); }, []);
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') close(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, close]);

  const setStatus = async (status: string) => {
    const r = await nui<State>('status', { status });
    if (r.ok && r.data) setState(r.data);
  };

  return (
    <>
      {!open && alerts.length > 0 && (
        <div className="dp-alerts" aria-live="polite">
          {alerts.map((a, i) => <AlertCard key={`${a.call.id}-${a.shownAt}`} alert={a} newest={i === 0} />)}
        </div>
      )}
      {open && state && (
        <aside className="dp-panel v-panel" aria-label="Dispatch">
          <header className="dp-head">
            <div className="dp-title"><Icon name="bell" size="1.1rem" /> Dispatch <span className="dp-svc">{state.serviceLabels[state.service] ?? state.service}</span></div>
            <CloseHint onClose={close} />
          </header>
          <div className="dp-status" role="radiogroup" aria-label="Your status">
            {state.statuses.map((s) => (
              <button key={s.id} role="radio" aria-checked={state.me.status === s.id} className={`dp-st ${s.id}${state.me.status === s.id ? ' on' : ''}`}
                onClick={() => void setStatus(s.id)}>{s.label}</button>
            ))}
          </div>
          <Tabs value={tab} onChange={setTab} tabs={[{ id: 'calls', label: `Calls (${state.calls.length})` }, { id: 'units', label: `Units (${state.units.length})` }]} />
          <div className="dp-list v-scroll">
            {tab === 'calls' && state.calls.length === 0 && <StateView kind="empty" message="No active calls." />}
            {tab === 'calls' && state.calls.map((c) => (
              <div key={c.id} className={`dp-call ${prio(c.priority)}${c.panic ? ' panic' : ''}`}>
                <div className="dp-call-top">
                  <span className="dp-code">{c.code}</span>
                  <strong>{c.title}</strong>
                  <span className="dp-id">#{c.id}</span>
                </div>
                {c.message && <p>{c.message}</p>}
                <div className="dp-meta">
                  {c.street && <span><Icon name="pin" size="0.8rem" /> {c.street}</span>}
                  <span><Icon name="clock" size="0.8rem" /> {ago(c.at)}</span>
                  {c.caller?.phone && <span><Icon name="call" size="0.8rem" /> {c.caller.name} · {c.caller.phone}</span>}
                </div>
                {c.responders.length > 0 && <div className="dp-resp">Responding: {c.responders.join(', ')}</div>}
                <div className="dp-actions">
                  <button className="v-btn primary" onClick={() => void nui('respond', { id: c.id })}>Respond</button>
                  <button className="v-btn" onClick={() => void nui('waypoint', { x: c.x, y: c.y })}><Icon name="pin" size="0.9rem" /> GPS</button>
                </div>
              </div>
            ))}
            {tab === 'units' && state.units.map((u) => (
              <div key={u.id} className={`dp-unit${u.id === state.me.id ? ' me' : ''}`}>
                <span className={`dp-dot ${u.status}`} />
                <div className="dp-unit-main"><strong>{u.name}</strong><span className="v-muted">{state.serviceLabels[u.service] ?? u.service}{u.grade ? ` · ${u.grade}` : ''}</span></div>
                <span className={`dp-st small ${u.status} on`}>{state.statuses.find((s) => s.id === u.status)?.label ?? u.status}</span>
              </div>
            ))}
          </div>
          <footer className="dp-foot v-muted">/callsign to set your callsign · F9 panic</footer>
        </aside>
      )}
    </>
  );
}

function AlertCard({ alert, newest }: { alert: Alert; newest: boolean }) {
  const c = alert.call;
  const bar = useRef<HTMLSpanElement>(null);
  useEffect(() => {
    const el = bar.current;
    if (!el) return;
    el.style.transition = 'none';
    el.style.width = '100%';
    requestAnimationFrame(() => requestAnimationFrame(() => { el.style.transition = `width ${alert.seconds}s linear`; el.style.width = '0%'; }));
  }, [alert]);
  return (
    <div className={`dp-alert ${prio(c.priority)}${c.panic ? ' panic' : ''}`}>
      <div className="dp-alert-top">
        <span className="dp-code">{c.code}</span>
        <strong>{c.title}</strong>
        <span className="dp-id">#{c.id}</span>
      </div>
      {c.message && <p>{c.message}</p>}
      <div className="dp-meta">
        {c.street && <span><Icon name="pin" size="0.8rem" /> {c.street}</span>}
        {c.distance !== undefined && <span>{c.distance < 1000 ? `${c.distance} m` : `${(c.distance / 1000).toFixed(1)} km`}</span>}
      </div>
      {newest && <div className="dp-alert-key"><kbd>{alert.respondKey}</kbd> Respond</div>}
      <span className="dp-alert-bar" ref={bar} />
    </div>
  );
}
