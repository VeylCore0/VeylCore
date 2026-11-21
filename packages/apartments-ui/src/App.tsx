import { useCallback, useEffect, useRef, useState } from 'react';
import { BrandHeader, CloseHint, Icon, announceReady, money, nui, useNuiMessage } from '@veyl/ui';
import { Leasing } from './views/Leasing';
import { DashboardView } from './views/Dashboard';
import { FurnitureView } from './views/Furniture';
import { WardrobeView } from './views/Wardrobe';
import { DeskView, type DeskData } from './views/Desk';
import type { Catalog, Dashboard, FurnitureCatalog, LeaseView } from './types';

type View =
  | { view: 'leasing'; data: Catalog } | { view: 'dashboard'; data: Dashboard } | { view: 'furniture'; data: FurnitureCatalog }
  | { view: 'wardrobe'; data: { outfits: { id: number; name: string }[]; max?: number } } | { view: 'desk'; data: DeskData }
  | { view: 'doorbell'; data: Visit };
interface Visit { id: number; name: string; expires: number }
interface Placement { visible: boolean; valid?: boolean; reason?: string | null; label?: string; price?: number | null; moving?: boolean }

const TITLES: Record<string, string> = { leasing: 'Leasing', dashboard: 'My home', furniture: 'Furniture', wardrobe: 'Wardrobe', desk: 'Front desk' };

export function App() {
  const [screen, setScreen] = useState<View | null>(null);
  const [openId, setOpenId] = useState(0); // remounts the view on every open (no state leaks between sessions)
  const [toast, setToast] = useState<{ kind: 'ok' | 'error'; text: string } | null>(null);
  const [visit, setVisit] = useState<(Visit & { until: number }) | null>(null);
  const [placement, setPlacement] = useState<Placement>({ visible: false });
  const [tour, setTour] = useState<{ until: number; label: string } | null>(null);
  const [revoked, setRevoked] = useState<{ until?: number } | null>(null);
  const [, tick] = useState(0);
  const timer = useRef<number>();

  useEffect(() => announceReady(), []);
  useEffect(() => { const t = window.setInterval(() => tick((x) => x + 1), 1000); return () => window.clearInterval(t); }, []);

  const say = useCallback((kind: 'ok' | 'error', text: string) => {
    setToast({ kind, text });
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setToast(null), 3800);
  }, []);

  useNuiMessage<{ view: View['view']; data: unknown }>('apt:open', (d) => {
    setScreen(d as View);
    setOpenId((n) => n + 1);
    if (d.view === 'doorbell') { const v = d.data as Visit; setVisit({ ...v, until: Date.now() + v.expires * 1000 }); }
  });
  useNuiMessage('apt:close', () => { setScreen(null); setVisit(null); });
  useNuiMessage<Visit>('apt:doorbell', (v) => setVisit({ ...v, until: Date.now() + v.expires * 1000 }));
  useNuiMessage<Placement>('apt:placement', (p) => setPlacement(p ?? { visible: false }));
  useNuiMessage<{ seconds: number; label: string } | null>('apt:tour', (t) => setTour(t ? { until: Date.now() + t.seconds * 1000, label: t.label } : null));
  useNuiMessage<{ seconds?: number } | null>('apt:revoked', (r) => setRevoked(r ? { until: r.seconds ? Date.now() + r.seconds * 1000 : undefined } : null));

  const close = useCallback(() => { void nui('close'); setScreen(null); setVisit(null); }, []);
  useEffect(() => {
    if (!screen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      const t = e.target as HTMLElement;
      if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT')) { t.blur(); return; }
      if (document.querySelector('.v-dialog-backdrop')) return; // dialogs handle their own cancel
      close();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [screen, close]);

  const answer = async (action: 'allow' | 'decline' | 'block') => {
    if (!visit) return;
    const r = await nui('doorbellAnswer', { id: visit.id, action });
    setVisit(null);
    if (!r.ok) say('error', r.message ?? 'That request has expired');
    if (screen?.view === 'doorbell') close();
  };
  const visitLeft = visit ? Math.max(0, Math.ceil((visit.until - Date.now()) / 1000)) : 0;
  useEffect(() => { if (visit && visitLeft <= 0) { setVisit(null); if (screen?.view === 'doorbell') close(); } }, [visit, visitLeft, screen, close]);

  const doorbellCard = visit && visitLeft > 0 && (
    <div className="apt-doorbell v-panel" role="alertdialog" aria-label="Visitor at the door">
      <div className="apt-doorbell-icon"><Icon name="bell" size="1.4rem" /></div>
      <div className="apt-doorbell-text"><strong>{visit.name}</strong> is requesting access.<span className="v-muted"> {visitLeft}s</span></div>
      <div className="apt-doorbell-actions">
        <button className="v-btn" onClick={() => { setVisit(null); if (screen?.view === 'doorbell') close(); }}>Ignore</button>
        <button className="v-btn" onClick={() => void answer('decline')}>Decline</button>
        <button className="v-btn primary" autoFocus onClick={() => void answer('allow')}>Allow entry</button>
      </div>
      <button className="apt-doorbell-block" onClick={() => void answer('block')}>Block this visitor</button>
    </div>
  );

  return (
    <>
      {/* Passive layer: never takes focus */}
      {placement.visible && (
        <div className="apt-placement v-panel" aria-live="polite">
          <div className="apt-placement-title">{placement.moving ? 'Moving' : 'Placing'} {placement.label}{placement.price ? ` · ${money(placement.price)}` : ''}</div>
          <div className={`apt-placement-state ${placement.valid ? 'ok' : 'bad'}`}>{placement.valid ? 'Good spot' : placement.reason}</div>
          <div className="apt-keys">
            <span><kbd>Mouse</kbd> aim</span><span><kbd>↑↓←→</kbd> nudge</span><span><kbd>Wheel</kbd>/<kbd>Q</kbd><kbd>E</kbd> rotate</span>
            <span><kbd>PgUp</kbd><kbd>PgDn</kbd> height</span><span><kbd>Shift</kbd> fine</span><span><kbd>G</kbd> follow aim</span>
            <span><kbd>Enter</kbd> {placement.moving ? 'save' : 'buy & place'}</span><span><kbd>Backspace</kbd> cancel</span>
          </div>
        </div>
      )}
      {tour && !screen && (
        <div className="apt-tourbar v-panel"><Icon name="eye" size="1rem" /> Touring {tour.label} · {Math.max(0, Math.ceil((tour.until - Date.now()) / 1000))}s left · use the door to leave</div>
      )}
      {revoked && (
        <div className="apt-tourbar danger v-panel"><Icon name="alert" size="1rem" /> Your access ended.{revoked.until ? ` Returning you outside in ${Math.max(0, Math.ceil((revoked.until - Date.now()) / 1000))}s.` : ' Please leave.'}</div>
      )}
      {screen && screen.view === 'doorbell' && <div className="apt-doorbell-wrap">{doorbellCard}</div>}
      {screen && screen.view !== 'doorbell' && (
        <div className="apt-root">
          <header className="apt-header">
            <BrandHeader section={TITLES[screen.view] ?? 'Apartments'} />
            <CloseHint onClose={close} />
          </header>
          <main key={openId} className={`apt-main apt-view-${screen.view}`}>
            {screen.view === 'leasing' && <Leasing data={screen.data} toast={say} onLeased={(l: LeaseView) => setScreen({ view: 'leasing', data: { ...screen.data, myLease: l, canLease: false } })} />}
            {screen.view === 'dashboard' && <div className="v-panel apt-panel"><DashboardView initial={screen.data} toast={say} /></div>}
            {screen.view === 'furniture' && <div className="v-panel apt-panel"><FurnitureView initial={screen.data} toast={say} /></div>}
            {screen.view === 'wardrobe' && <div className="v-panel apt-panel narrow"><WardrobeView initial={screen.data} toast={say} /></div>}
            {screen.view === 'desk' && <div className="v-panel apt-panel"><div className="apt-desk-title">{screen.data.label}</div><DeskView data={screen.data} toast={say} /></div>}
          </main>
          {visit && <div className="apt-doorbell-float">{doorbellCard}</div>}
        </div>
      )}
      {toast && <div className={`v-toast-inline ${toast.kind === 'error' ? 'error' : 'success'}`} role="alert"><Icon name={toast.kind === 'error' ? 'alert' : 'check'} size="1rem" />{toast.text}</div>}
    </>
  );
}
