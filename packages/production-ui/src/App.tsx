import { useCallback, useEffect, useRef, useState } from 'react';
import { announceReady, nui, useNuiMessage, type NuiResponse } from '@veyl/ui';
import type { Ctx, Page } from './ctx';
import type { Bench, ShopView, TabletState } from './types';
import { api, Bar, Button, cx, ErrorBox, Ico, ITEM_LABELS, Loading, Ring, Toast } from './ui';
import { Botanical, Dashboard, Production, Progression, Stats } from './Pages';
import { Properties } from './Properties';
import { BenchPanel } from './Bench';
import { Shop } from './Shop';

const NAV: { id: Page; label: string; icon: string }[] = [
  { id: 'dashboard', label: 'Dashboard', icon: 'dashboard' }, { id: 'botanical', label: 'Botanical', icon: 'leaf' }, { id: 'production', label: 'Production', icon: 'gear' },
  { id: 'properties', label: 'Properties', icon: 'home' }, { id: 'progression', label: 'Progression', icon: 'star' }, { id: 'stats', label: 'Statistics', icon: 'chart' },
];

type Open = { view: 'tablet'; state: TabletState; page: Page } | { view: 'shop' | 'buyer'; shop: ShopView } | { view: 'bench'; bench: Bench; labels: Record<string, string> };

export function App() {
  const [open, setOpen] = useState<Open | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [toast, setToast] = useState<{ kind: 'ok' | 'error'; text: string } | null>(null);
  const [placement, setPlacement] = useState<{ visible: boolean; valid?: boolean; reason?: string; label?: string }>({ visible: false });
  const timer = useRef<number>();
  const openRef = useRef<Open | null>(null);
  openRef.current = open;
  useEffect(() => announceReady(), []);

  const say = useCallback((kind: 'ok' | 'error', text: string) => {
    setToast({ kind, text });
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setToast(null), 3200);
  }, []);

  // Fetch what the current view shows again (after any action, and when the server says something changed).
  const refresh = useCallback(async () => {
    const o = openRef.current;
    if (!o) return;
    if (o.view === 'tablet') {
      const r = await api<TabletState>('state');
      if (r.ok && r.data) { setOpen({ ...o, state: r.data }); setError(null); } else setError(r.message ?? 'Could not reach the server');
    } else if (o.view === 'bench') {
      const r = await api<Bench>('wsOpen', o.bench.id);
      if (r.ok && r.data) setOpen({ ...o, bench: r.data }); else setOpen(null);
    } else {
      const r = await api<ShopView>(o.view === 'shop' ? 'shopView' : 'buyerView');
      if (r.ok && r.data) setOpen({ ...o, shop: r.data });
    }
  }, []);

  useNuiMessage<{ view: string; data: any }>('production:open', (d) => {
    setError(null);
    if (d.view === 'tablet') setOpen({ view: 'tablet', state: d.data.state, page: (d.data.page as Page) ?? 'dashboard' });
    else if (d.view === 'shop' || d.view === 'buyer') setOpen({ view: d.view, shop: d.data });
    else if (d.view === 'bench') setOpen({ view: 'bench', bench: d.data, labels: ITEM_LABELS });
  });
  useNuiMessage('production:close', () => setOpen(null));
  useNuiMessage('production:refresh', () => { void refresh(); });
  useNuiMessage<typeof placement>('production:placement', (d) => setPlacement(d));

  const close = useCallback(() => { void nui('close'); }, []);
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') close(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, close]);

  const run = useCallback(async (name: string, ...args: unknown[]): Promise<NuiResponse<unknown>> => {
    setBusy(true);
    const r = await api(name, ...args);
    setBusy(false);
    if (r.message) say(r.ok ? 'ok' : 'error', r.message); else if (!r.ok) say('error', 'That did not work');
    if (r.ok || r.code === 'OUT_OF_STOCK') await refresh();
    return r;
  }, [refresh, say]);
  const waypoint = useCallback((x: number, y: number) => { void nui('waypoint', { x, y }); }, []);

  return (
    <>
      {placement.visible && (
        <div className={cx('pr-placement', placement.valid ? 'ok' : 'bad')} role="status">
          <b>{placement.label}</b>
          <span>{placement.valid ? 'Press E to place' : placement.reason}</span>
          <small><kbd>E</kbd> place · <kbd>R</kbd> or scroll rotate · <kbd>Esc</kbd> cancel</small>
        </div>
      )}
      {open && (
        <div className="pr-root">
          {open.view === 'tablet' ? <Tablet open={open} setPage={(p) => setOpen({ ...open, page: p })} run={run} refresh={refresh} waypoint={waypoint} busy={busy} close={close} error={error} />
            : open.view === 'bench' ? (
              <div className="pr-panel narrow"><Head title="Workstation" close={close} /><div className="pr-body"><BenchPanel bench={open.bench} labels={open.labels} act run={run} /></div></div>
            ) : (
              <div className="pr-panel"><Head title={open.view === 'shop' ? 'Garden Supplier' : 'Buyer'} close={close} /><div className="pr-body"><Shop view={open.shop} mode={open.view} run={run as never} /></div></div>
            )}
          <Toast toast={toast} />
        </div>
      )}
    </>
  );
}

function Head({ title, close }: { title: string; close: () => void }) {
  return <header className="pr-top"><span className="pr-logo"><Ico name="leaf" size={22} /></span><strong>{title}</strong><button className="pr-keyhint" onClick={close}><kbd>ESC</kbd>Close</button></header>;
}

function Tablet({ open, setPage, run, refresh, waypoint, busy, close, error }: { open: Extract<Open, { view: 'tablet' }>; setPage: (p: Page) => void; run: Ctx['run']; refresh: Ctx['refresh']; waypoint: Ctx['waypoint']; busy: boolean; close: () => void; error: string | null }) {
  const ctx: Ctx = { s: open.state, go: setPage, run, refresh, waypoint, busy };
  const s = open.state;
  const rep = s.progress.reputation;
  const bot = s.progress.branches.botanical;
  const title = NAV.find((n) => n.id === open.page)?.label ?? '';
  const initials = s.player.name.split(' ').map((w) => w[0]).slice(0, 2).join('').toUpperCase();
  return (
    <div className="pr-tablet" role="application" aria-label="Production tablet">
      <nav className="pr-side" aria-label="Sections">
        <div className="pr-brand"><span className="pr-logo"><Ico name="leaf" size={24} /></span><div><b>VEYL</b><i>PRODUCTION</i></div></div>
        <span className="pr-navlabel">WORKSPACE</span>
        {NAV.slice(0, 3).map((n) => <button key={n.id} className={cx('pr-nav', open.page === n.id && 'on')} onClick={() => setPage(n.id)} aria-current={open.page === n.id ? 'page' : undefined}><Ico name={n.icon} size={19} />{n.label}</button>)}
        <span className="pr-navlabel">ASSETS</span>
        {NAV.slice(3, 4).map((n) => <button key={n.id} className={cx('pr-nav', open.page === n.id && 'on')} onClick={() => setPage(n.id)} aria-current={open.page === n.id ? 'page' : undefined}><Ico name={n.icon} size={19} />{n.label}</button>)}
        <span className="pr-navlabel">YOU</span>
        {NAV.slice(4).map((n) => <button key={n.id} className={cx('pr-nav', open.page === n.id && 'on')} onClick={() => setPage(n.id)} aria-current={open.page === n.id ? 'page' : undefined}><Ico name={n.icon} size={19} />{n.label}</button>)}
        {Object.entries(s.branches).filter(([, b]) => !b.enabled).map(([id, b]) => <span key={id} className="pr-nav soon" title="Not built yet"><Ico name="lock" size={17} />{b.label}</span>)}
        <div className="pr-usercard">
          <Ring value={bot?.progress ?? 0} size={42} stroke={4} color={bot?.color}><b className="sm">{initials}</b></Ring>
          <div><strong>{s.player.name}</strong><em>Level {rep.level} · {rep.name}</em></div>
        </div>
      </nav>
      <main className="pr-main">
        <header className="pr-top">
          <div className="pr-title"><small>PRODUCTION</small><h1>{title}</h1></div>
          <div className="pr-xp"><span>{bot?.label} level {bot?.level}</span><Bar value={bot?.progress ?? 0} color={bot?.color} label="Botanical progress" /></div>
          <button className="pr-icon" onClick={() => void refresh()} aria-label="Sync" title="Sync"><Ico name="bolt" size={16} /></button>
          <button className="pr-keyhint" onClick={close}><kbd>ESC</kbd>Close</button>
        </header>
        <div className="pr-body" key={open.page}>
          {error ? <ErrorBox message={error} onRetry={() => void refresh()} /> : !s ? <Loading /> : open.page === 'dashboard' ? <Dashboard c={ctx} />
            : open.page === 'botanical' ? <Botanical c={ctx} /> : open.page === 'production' ? <Production c={ctx} />
            : open.page === 'properties' ? <Properties c={ctx} /> : open.page === 'progression' ? <Progression c={ctx} /> : <Stats c={ctx} />}
        </div>
      </main>
    </div>
  );
}
