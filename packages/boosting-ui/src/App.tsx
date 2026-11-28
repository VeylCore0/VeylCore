import { useCallback, useEffect, useRef, useState } from 'react';
import { announceReady, nui, useNuiMessage, type NuiResponse } from '@veyl/ui';
import type { Ctx, Tab } from './ctx';
import type { MinigameStage, TabletState } from './types';
import { Bar, Button, ErrorBox, Ico, Loading, Toast, api, cx, heatVars, usd } from './ui';
import { Dashboard } from './Dashboard';
import { Contracts } from './Contracts';
import { Active } from './Active';
import { Vehicles } from './Vehicles';
import { Heat, Reputation, Stats } from './Progress';
import { Crew } from './Crew';
import { Help } from './Help';
import { Minigame } from './Minigame';

const NAV: { id: Tab; label: string; icon: string }[] = [
  { id: 'dashboard', label: 'Dashboard', icon: 'dashboard' },
  { id: 'contracts', label: 'Contracts', icon: 'contracts' },
  { id: 'active', label: 'Active Job', icon: 'play' },
  { id: 'vehicles', label: 'Vehicles', icon: 'car' },
  { id: 'reputation', label: 'Reputation', icon: 'star' },
  { id: 'crew', label: 'Crew', icon: 'crew' },
  { id: 'heat', label: 'Heat', icon: 'flame' },
  { id: 'stats', label: 'Statistics', icon: 'chart' },
  { id: 'help', label: 'Settings', icon: 'gear' },
];

export function App() {
  const [s, setS] = useState<TabletState | null>(null);
  const [open, setOpen] = useState(false);
  const [mini, setMini] = useState<MinigameStage | null>(null);
  const [tab, setTab] = useState<Tab>('dashboard');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [toast, setToast] = useState<{ kind: 'ok' | 'error'; text: string } | null>(null);
  const timer = useRef<number>();
  useEffect(() => announceReady(), []);

  const say = useCallback((kind: 'ok' | 'error', text: string) => {
    setToast({ kind, text });
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setToast(null), 3200);
  }, []);

  const refresh = useCallback(async () => {
    const r = await api<TabletState>('state');
    if (r.ok && r.data) { setS(r.data); setError(null); } else setError(r.message ?? 'The tablet could not reach the server.');
  }, []);

  useNuiMessage<TabletState>('boosting:open', (d) => { setS(d); setOpen(true); setMini(null); setError(null); setTab(d.active ? 'active' : 'dashboard'); });
  useNuiMessage<MinigameStage>('boosting:minigame', (d) => { setMini(d); setOpen(true); });
  useNuiMessage('boosting:close', () => { setOpen(false); setMini(null); setS(null); });
  useNuiMessage('boosting:refresh', () => { void refresh(); });

  const close = useCallback(() => { void nui('close'); }, []);
  useEffect(() => {
    if (!open || mini) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') close(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, mini, close]);

  const run = useCallback(async (name: string, ...args: unknown[]): Promise<NuiResponse<unknown>> => {
    setBusy(true);
    const r = await api(name, ...args);
    setBusy(false);
    if (r.message) say(r.ok ? 'ok' : 'error', r.message); else if (!r.ok) say('error', 'That did not work');
    await refresh();
    return r;
  }, [refresh, say]);

  const waypoint = useCallback((x: number, y: number) => { void nui('waypoint', { x, y }); }, []);

  if (!open) return null;
  if (mini) return <Minigame first={mini} />;

  const ctx: Ctx | null = s ? { s, go: setTab, run, refresh, waypoint, busy } : null;
  const activeDot = !!s?.active;

  return (
    <div className="bst-root">
      <div className="bst-tablet" role="application" aria-label="Boosting tablet">
        <nav className="bst-side" aria-label="Sections">
          <div className="bst-brand"><svg viewBox="0 0 48 40" aria-hidden="true"><path d="M2 4h14l8 22 8-22h14L28 36H20z" fill="url(#bg)" /><defs><linearGradient id="bg" x1="0" x2="1"><stop offset="0" stopColor="#b892f4" /><stop offset="1" stopColor="#6a3fc7" /></linearGradient></defs></svg><b>VEYL</b><i>BOOSTING</i></div>
          {NAV.map((n) => (
            <button key={n.id} className={cx('bst-nav', tab === n.id && 'on')} onClick={() => setTab(n.id)} aria-current={tab === n.id ? 'page' : undefined}>
              <Ico name={n.icon} size={19} />{n.label}
              {n.id === 'active' && activeDot && <span className="bst-dot" />}
              {n.id === 'crew' && s?.invite && <span className="bst-dot warn" />}
            </button>
          ))}
          <span className="bst-ver">v2.0</span>
        </nav>

        <main className="bst-main">
          <header className="bst-top">
            <span className="bst-crest"><Ico name="crown" size={26} /></span>
            <div className="bst-id"><strong>{s?.player.name ?? 'Operator'}</strong><em>{s?.player.rank.toUpperCase() ?? ''}</em></div>
            <div className="bst-rep">
              <span>Reputation · {s?.player.rank}</span>
              <Bar value={s?.player.progress ?? 0} label="Reputation progress" />
              <small>{s ? `${s.player.rep.toLocaleString()} / ${(s.player.nextRep ?? s.player.rep).toLocaleString()}` : ''}</small>
            </div>
            {s && (
              <button className="bst-heatbox" style={heatVars(s.heat.color)} onClick={() => setTab('heat')} aria-label={`Heat level ${s.heat.label}`}>
                <Ico name="flame" size={28} /><span><small>Heat Level</small><b>{s.heat.label.toUpperCase()}</b></span>
                <i>{Array.from({ length: 5 }, (_, i) => <u key={i} className={i < Math.ceil((s.heat.value / s.heat.max) * 5) ? 'on' : ''} />)}</i>
              </button>
            )}
            <button className="bst-icon" onClick={() => setTab('crew')} aria-label="Notifications">{s?.invite && <span className="bst-dot warn" />}<Ico name="bell" size={18} /></button>
            <button className="bst-icon" onClick={close} aria-label="Close the tablet"><Ico name="x" size={18} /></button>
          </header>
          <div className="bst-body">
            {error && !s ? <ErrorBox message={error} onRetry={() => void refresh()} />
              : !ctx ? <Loading text="Connecting" />
              : tab === 'dashboard' ? <Dashboard c={ctx} />
              : tab === 'contracts' ? <Contracts c={ctx} />
              : tab === 'active' ? <Active c={ctx} />
              : tab === 'vehicles' ? <Vehicles c={ctx} />
              : tab === 'reputation' ? <Reputation c={ctx} />
              : tab === 'crew' ? <Crew c={ctx} />
              : tab === 'heat' ? <Heat c={ctx} />
              : tab === 'stats' ? <Stats c={ctx} />
              : <Help c={ctx} />}
          </div>
          {s && s.stats && <footer className="bst-foot"><span>{usd(s.stats.earnings)} earned</span><span>{s.stats.completed} completed</span><Button kind="ghost" onClick={() => void refresh()}><Ico name="refresh" size={14} />Sync</Button></footer>}
        </main>
      </div>
      <Toast toast={toast} />
    </div>
  );
}
