import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { Icon, VMark, announceReady, nui, useNuiMessage } from '@veyl/ui';
import { api, playNotify, playRing, stopRing } from './api';
import { APP_STYLE, WEATHER, clock, type AppDef, type CallState, type ConversationItem, type LayoutEntry, type Message, type Notification, type Session, type Settings, type World } from './types';
import { PhoneApp } from './apps/Phone';
import { MessagesApp } from './apps/Messages';
import { ContactsApp } from './apps/Contacts';
import { SettingsApp } from './apps/Settings';
import { StoreApp } from './apps/Store';
import { FlockApp } from './apps/Flock';
import { BankApp } from './apps/Bank';
import { GarageApp } from './apps/Garage';
import { MarketApp } from './apps/Market';
import { NotesApp } from './apps/Notes';
import { CalculatorApp } from './apps/Calculator';
import { MapsApp } from './apps/Maps';
import { ServicesApp } from './apps/Services';
import { MailApp } from './apps/Mail';
import { VoicemailApp } from './apps/Voicemail';
import { BillsApp, CameraApp, JobsApp, MusicApp, NewsApp, RacingApp, loadStations } from './apps/Phase2';
import { syncSpeakers } from './music';

// ---------------------------------------------------------------------------
// Context shared by every app
// ---------------------------------------------------------------------------
interface Ctx {
  session: Session; settings: Settings; saveSettings: (patch: Partial<Settings>) => Promise<boolean>;
  go: (app: string | null, route?: string) => void; route: string; toast: (text: string, kind?: 'ok' | 'error') => void;
  world: World | null | undefined; money: { bank: number } | null | undefined;
  call: CallState | null; startCall: (number: string) => Promise<void>; answer: () => void; decline: () => void; hangup: () => void; mute: () => void;
  unread: number; setUnread: (n: number) => void; badges: Record<string, number>; setAppInstalled: (id: string, on: boolean) => void; onMessage: (fn: (m: Message, title: string) => void) => () => void;
  onReceipt: (fn: (r: { convId: number; id: number; state: Message['state']; delivered: number; total: number }) => void) => () => void;
  openThread: string | null; setOpenThread: (k: string | null) => void;
}
const PhoneCtx = createContext<Ctx | null>(null);
export const usePhone = () => useContext(PhoneCtx)!;

const WALLPAPERS: Record<string, string> = {
  // Purple to peach dusk with an original city-and-hills silhouette (drawn in CSS, see .wp-sunset).
  sunset: "url(\"data:image/svg+xml;utf8,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 400 260' preserveAspectRatio='none'%3E%3Cpath d='M0 120 C60 90 110 70 170 92 C220 110 250 60 300 72 C340 82 370 100 400 96 L400 260 L0 260Z' fill='%23453063' opacity='.85'/%3E%3Cpath d='M0 170 C80 140 140 150 200 160 C260 170 320 140 400 150 L400 260 L0 260Z' fill='%232f2148'/%3E%3Cg fill='%2322183a'%3E%3Crect x='40' y='150' width='14' height='110'/%3E%3Crect x='58' y='132' width='18' height='128'/%3E%3Crect x='80' y='160' width='12' height='100'/%3E%3Crect x='96' y='142' width='16' height='118'/%3E%3Crect x='118' y='170' width='12' height='90'/%3E%3C/g%3E%3Cg fill='%23f6c48f' opacity='.55'%3E%3Crect x='61' y='140' width='2' height='2'/%3E%3Crect x='67' y='150' width='2' height='2'/%3E%3Crect x='99' y='160' width='2' height='2'/%3E%3Crect x='45' y='170' width='2' height='2'/%3E%3Crect x='70' y='176' width='2' height='2'/%3E%3C/g%3E%3Crect x='305' y='60' width='1.5' height='34' fill='%23453063'/%3E%3C/svg%3E\") bottom / 100% 38% no-repeat, linear-gradient(180deg, #2a1c4e 0%, #3a2463 34%, #5b3473 58%, #b4687a 80%, #f0a37f 100%)",
  aurora: 'linear-gradient(160deg, #1a1030 0%, #3b1f6e 45%, #7d4cd6 70%, #1b1330 100%)',
  dusk: 'linear-gradient(180deg, #2a1838 0%, #6a2c5e 40%, #d0705a 75%, #241533 100%)',
  vinewood: 'radial-gradient(circle at 70% 20%, #7a4fd0 0%, transparent 40%), linear-gradient(180deg, #0f1022 0%, #262248 60%, #141325 100%)',
  midnight: 'linear-gradient(170deg, #070911 0%, #121a33 60%, #0a0c16 100%)',
  violet: 'radial-gradient(circle at 30% 30%, #b892f4 0%, #5a35a8 35%, #160f28 80%)',
  mono: 'linear-gradient(180deg, #1c1c22 0%, #2b2b33 100%)',
};

function serverDate(serverTime: number, openedAt: number) {
  const now = new Date((serverTime + (Date.now() - openedAt) / 1000) * 1000);
  return now.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });
}

function useClock(world: World | null | undefined) {
  const [, force] = useState(0);
  useEffect(() => { const t = window.setInterval(() => force((x) => x + 1), 15000); return () => window.clearInterval(t); }, []);
  if (world) return `${String(world.hour).padStart(2, '0')}:${String(world.minute).padStart(2, '0')}`;
  return new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
}

// ---------------------------------------------------------------------------
// Root
// ---------------------------------------------------------------------------
export function App() {
  const [session, setSession] = useState<Session | null>(null);
  const [visible, setVisible] = useState(false);
  const [settings, setSettings] = useState<Settings | null>(null);
  const [world, setWorld] = useState<World | null | undefined>(null);
  const [money, setMoney] = useState<{ bank: number } | null | undefined>(null);
  const [call, setCall] = useState<CallState | null>(null);
  const [banners, setBanners] = useState<Notification[]>([]);
  const [unread, setUnread] = useState(0);
  const [badges, setBadges] = useState<Record<string, number>>({});
  const [openThread, setOpenThread] = useState<string | null>(null);
  const openedAt = useRef(Date.now());
  const msgListeners = useRef(new Set<(m: Message, title: string) => void>());
  const receiptListeners = useRef(new Set<(r: { convId: number; id: number; state: Message['state']; delivered: number; total: number }) => void>());
  const [nav, setNav] = useState<{ app: string | null; route: string; locked: boolean }>({ app: null, route: '', locked: true });
  const [toastMsg, setToastMsg] = useState<{ text: string; kind: 'ok' | 'error' } | null>(null);
  const settingsRef = useRef<Settings | null>(null);
  settingsRef.current = settings;
  const visibleRef = useRef(visible);
  visibleRef.current = visible;
  const openThreadRef = useRef(openThread);
  openThreadRef.current = openThread;

  useEffect(() => announceReady(), []);

  useNuiMessage<Session>('phone:open', (d) => {
    setSession(d); setSettings(d.settings); setWorld(d.world); setMoney(d.money); setUnread(d.unread); setBadges(d.badges ?? {});
    openedAt.current = Date.now();
    const target = d.open?.app;
    setNav({ app: target ?? null, route: d.open?.route ?? '', locked: !target && !call });
    setVisible(true);
  });
  useNuiMessage<{ settings: Settings; number: string }>('phone:session', (d) => { setSettings(d.settings); });
  useNuiMessage('phone:hidden', () => { setVisible(false); setOpenThread(null); });
  useNuiMessage('phone:close', () => { setVisible(false); setOpenThread(null); });
  useNuiMessage('phone:reset', () => { setVisible(false); setSession(null); setCall(null); stopRing(); setBanners([]); });
  useNuiMessage<{ world: World | null; money: { bank: number } | null }>('phone:tick', (d) => { setWorld(d.world); setMoney(d.money); });

  const pushBanner = useCallback((n: Notification) => {
    setBanners((b) => [n, ...b.filter((x) => x.id !== n.id)].slice(0, 3));
    window.setTimeout(() => setBanners((b) => b.filter((x) => x.id !== n.id)), 4500);
  }, []);

  // Phones playing out loud nearby (volume by distance from the client).
  useNuiMessage<{ id: number; station: string; volume: number }[]>('phone:speakers', (list) => { void loadStations().then(() => syncSpeakers(list ?? [])); });
  useNuiMessage<{ event: string; data: any }>('phone:push', ({ event, data }) => {
    const s = settingsRef.current;
    if (event === 'message') {
      const m = data.message as Message;
      msgListeners.current.forEach((fn) => fn(m, data.title));
      const viewing = visibleRef.current && openThreadRef.current === `c${m.convId}`;
      if (!viewing) {
        setUnread((u) => u + 1);
        const quiet = data.muted || s?.dnd || s?.appPrefs?.messages?.muted;
        if (!quiet) {
          const preview = s?.lockPreview === 'full' || visibleRef.current ? (m.kind === 'text' ? m.body : m.kind === 'location' ? 'Shared a location' : 'Shared a contact') : 'New message';
          const title = s?.lockPreview === 'hidden' && !visibleRef.current ? 'Messages' : data.title;
          pushBanner({ id: -m.id, app: 'messages', title, body: preview, route: `messages/c${m.convId}`, at: m.at });
          if (!s?.silent) playNotify(s?.notifySound ?? 'tap', s?.notifyVolume ?? 60);
        }
      }
    } else if (event === 'badge') {
      const b = data as { app: string; count: number };
      setBadges((cur) => ({ ...cur, [b.app]: b.count }));
    } else if (event === 'receipt') {
      receiptListeners.current.forEach((fn) => fn(data));
    } else if (event === 'notification') {
      const n = data as Notification;
      if (!n.quiet) {
        const priv = !visibleRef.current && s?.lockPreview !== 'full';
        pushBanner({ ...n, body: priv ? (s?.lockPreview === 'hidden' ? '' : n.body) : n.body, title: s?.lockPreview === 'hidden' && !visibleRef.current ? 'Notification' : n.title });
        if (!s?.silent) playNotify(s?.notifySound ?? 'tap', s?.notifyVolume ?? 60);
      }
    } else if (event === 'call') {
      const c = data as { id: number; state: string; number?: string; display?: string; since?: number; reason?: string; quiet?: boolean };
      if (c.state === 'incoming') {
        setCall({ id: c.id, state: 'incoming', number: c.number, display: c.display });
        if (!c.quiet && !s?.silent) playRing(s?.ringtone ?? 'veyl', s?.ringVolume ?? 70);
      } else if (c.state === 'connected') {
        stopRing();
        setCall((cur) => (cur && cur.id === c.id ? { ...cur, state: 'connected', since: Date.now() / 1000 } : cur));
      } else if (c.state === 'ended') {
        stopRing();
        setCall((cur) => (cur && cur.id === c.id ? { ...cur, state: 'ended', reason: c.reason } : cur));
        window.setTimeout(() => setCall((cur) => (cur && cur.id === c.id && cur.state === 'ended' ? null : cur)), 2200);
      }
    }
  });

  const go = useCallback((app: string | null, route = '') => setNav({ app, route, locked: false }), []);
  const toast = useCallback((text: string, kind: 'ok' | 'error' = 'ok') => {
    setToastMsg({ text, kind });
    window.setTimeout(() => setToastMsg(null), 2600);
  }, []);

  const saveSettings = useCallback(async (patch: Partial<Settings>) => {
    if (!settings) return false;
    const next = { ...settings, ...patch };
    setSettings(next);
    const res = await api<Settings>('saveSettings', next);
    if (res.ok && res.data) { setSettings(res.data); return true; }
    toast(res.message ?? 'Could not save', 'error');
    return false;
  }, [settings, toast]);

  const startCall = useCallback(async (number: string) => {
    if (call) return;
    setCall({ id: 0, state: 'outgoing', number, display: number });
    const res = await api<{ id: number; display: string }>('callStart', number);
    if (!res.ok || !res.data) { setCall({ id: 0, state: 'ended', number, reason: res.message ?? 'Call failed' }); window.setTimeout(() => setCall((c) => (c?.id === 0 ? null : c)), 2600); return; }
    setCall((cur) => (cur && cur.id === 0 ? { ...cur, id: res.data!.id, display: res.data!.display } : cur));
  }, [call]);
  const answer = useCallback(() => {
    if (!call) return;
    stopRing();
    void api<{ since: number }>('callAnswer', call.id).then((res) => {
      if (!res.ok) { toast(res.message ?? 'Could not answer', 'error'); setCall(null); return; }
      setCall((cur) => (cur ? { ...cur, state: 'connected', since: Date.now() / 1000 } : cur));
    });
  }, [call, toast]);
  const decline = useCallback(() => { if (call) { stopRing(); void api('callDecline', call.id); setCall(null); } }, [call]);
  const hangup = useCallback(() => { if (call) { stopRing(); void api('callEnd', call.id); setCall({ ...call, state: 'ended', reason: 'hangup' }); window.setTimeout(() => setCall(null), 1500); } }, [call]);
  const mute = useCallback(() => {
    if (!call || call.state !== 'connected') return;
    const on = !call.muted;
    void api('callMute', call.id, on).then((res) => { if (res.ok) setCall((c) => (c ? { ...c, muted: on } : c)); });
  }, [call]);

  // Escape closes the phone (and releases focus). Backspace goes back when not typing.
  useEffect(() => {
    if (!visible) return;
    const typing = (t: EventTarget | null) => t instanceof HTMLInputElement || t instanceof HTMLTextAreaElement;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') { if (typing(e.target)) (e.target as HTMLElement).blur(); else void nui('close'); }
    };
    // Tell Lua when a text field has focus, so typing doesn't walk the character.
    const onIn = (e: FocusEvent) => { if (typing(e.target)) void nui('ui:typing', { typing: true }); };
    const onOut = (e: FocusEvent) => { if (typing(e.target)) void nui('ui:typing', { typing: false }); };
    window.addEventListener('keydown', onKey);
    document.addEventListener('focusin', onIn); document.addEventListener('focusout', onOut);
    return () => { window.removeEventListener('keydown', onKey); document.removeEventListener('focusin', onIn); document.removeEventListener('focusout', onOut); };
  }, [visible]);

  // Closed: passive banners + incoming call pill only (no focus, no pointer events).
  const reduced = settings?.reducedMotion;
  const posClass = `pos-${settings?.position ?? 'bottom-right'}`;
  const style = { '--accent': settings?.accent ?? '#b892f4', '--ph-scale': String(settings?.scale ?? 1), '--ph-ox': `${settings?.offsetX ?? 0}vw`, '--ph-oy': `${settings?.offsetY ?? 0}vh` } as React.CSSProperties;

  if (!visible || !session || !settings) {
    return (
      <div className={`ph-passive ${posClass}${reduced ? ' ph-reduced' : ''}`} style={style}>
        {call && call.state === 'incoming' && (
          <div className="ph-pill" role="status"><Icon name="call" size="1rem" /> <strong>{call.display}</strong> is calling · press your phone key to answer</div>
        )}
        {banners.map((b) => <Banner key={b.id} n={b} />)}
      </div>
    );
  }

  const ctx: Ctx = {
    session, settings, saveSettings, go, route: nav.route, toast, world, money, call, startCall, answer, decline, hangup, mute,
    unread, setUnread, badges,
    setAppInstalled: (id, on) => setSession((s) => (s ? { ...s, apps: s.apps.map((a) => (a.id === id ? { ...a, installed: on } : a)) } : s)),
    onMessage: (fn) => { msgListeners.current.add(fn); return () => { msgListeners.current.delete(fn); }; },
    onReceipt: (fn) => { receiptListeners.current.add(fn); return () => { receiptListeners.current.delete(fn); }; },
    openThread, setOpenThread,
  };

  return (
    <PhoneCtx.Provider value={ctx}>
      <div className={`ph-stage ${posClass}${reduced ? ' ph-reduced' : ''}`} style={style}>
        <div className={`ph-device text-${settings.textSize ?? 'default'}${settings.theme === 'light' ? ' light' : ''}`} role="dialog" aria-label="Phone">
          <div className={`ph-screen wp-${settings.wallpaper}`} style={{ background: WALLPAPERS[settings.wallpaper] ?? WALLPAPERS.sunset }}>
            <Island />
            <StatusBar />
            {call && (call.state === 'incoming' || ((call.state === 'connected' || call.state === 'outgoing' || call.state === 'ended') && nav.app === 'phone' && nav.route === 'call')) ? (
              <CallScreen />
            ) : nav.locked ? (
              <LockScreen onUnlock={() => setNav((n) => ({ ...n, locked: false }))} openedAt={openedAt.current} />
            ) : nav.app ? (
              <AppHost app={nav.app} />
            ) : (
              <Home openedAt={openedAt.current} />
            )}
            {banners.length > 0 && <div className="ph-banners">{banners.map((b) => <Banner key={b.id} n={b} onOpen={() => { const [a, r] = (b.route ?? '').split('/'); if (session.external?.some((e) => e.id === a)) void nui('openExternal', { id: a }); else go(a || null, r ?? ''); }} />)}</div>}
            {toastMsg && <div className={`ph-toast ${toastMsg.kind}`} role="status">{toastMsg.text}</div>}
            <button className="ph-homebar" aria-label="Home" onClick={() => setNav({ app: null, route: '', locked: false })} />
          </div>
        </div>
      </div>
    </PhoneCtx.Provider>
  );
}

function Banner({ n, onOpen }: { n: Notification; onOpen?: () => void }) {
  const style = APP_STYLE[n.app];
  return (
    <button className="ph-banner" onClick={onOpen} tabIndex={onOpen ? 0 : -1}>
      <span className="ph-banner-icon" style={{ background: style?.color ?? '#3a3346' }}><Icon name={style?.icon ?? 'bell'} size="0.95rem" /></span>
      <span className="ph-banner-text"><strong>{n.title}</strong>{n.body && <span>{n.body}</span>}</span>
    </button>
  );
}

// Status bar. Signal and battery are cosmetic (there is no signal or battery simulation): always full, never fake drain.
function StatusBar() {
  const { world, settings } = usePhone();
  const time = useClock(world);
  return (
    <div className="ph-status" aria-hidden="true">
      <span className="ph-status-time">{time}</span>
      <span className="ph-status-icons">
        {settings.dnd && <Icon name="moon" size="0.75rem" />}
        {settings.silent && <Icon name="bell_off" size="0.75rem" />}
        <span className="ph-signal"><i /><i /><i /><i /></span>
        <svg className="ph-wifi" viewBox="0 0 16 12" width="15" height="11"><path d="M8 11.2 5.6 8.8a3.4 3.4 0 0 1 4.8 0L8 11.2Zm-4.2-4.2-1.3-1.3a7.8 7.8 0 0 1 11 0l-1.3 1.3a6 6 0 0 0-8.4 0ZM1.3 4.5 0 3.2a11.3 11.3 0 0 1 16 0l-1.3 1.3a9.5 9.5 0 0 0-13.4 0Z" fill="currentColor" /></svg>
        <span className="ph-battery"><i /></span>
      </span>
    </div>
  );
}

// Dynamic Island: idle pill; during a call it shows the caller and the call time, and expands to call controls.
function Island() {
  const { call, go, hangup, mute } = usePhone();
  const [open, setOpen] = useState(false);
  const [, tick] = useState(0);
  const active = call && (call.state === 'connected' || call.state === 'outgoing');
  useEffect(() => { if (!active) { setOpen(false); return; } const t = window.setInterval(() => tick((x) => x + 1), 1000); return () => window.clearInterval(t); }, [active]);
  if (!active || !call) return <div className="ph-island" aria-hidden="true" />;
  const secs = call.state === 'connected' && call.since ? Math.max(0, Math.floor(Date.now() / 1000 - call.since)) : 0;
  const elapsed = call.state === 'connected' ? `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, '0')}` : 'Calling…';
  return (
    <div className={`ph-island live${open ? ' open' : ''}`} role="status" aria-label={`Call with ${call.display}, ${elapsed}`}>
      <button className="ph-island-row" onClick={() => setOpen((o) => !o)} aria-expanded={open}>
        <span className="ph-island-ico"><Icon name="call" size="0.7rem" /></span>
        <span className="ph-island-name">{call.display}</span>
        <span className="ph-island-time">{elapsed}</span>
      </button>
      {open && (
        <div className="ph-island-ctrl">
          {call.state === 'connected' && <button onClick={mute} aria-pressed={!!call.muted} className={call.muted ? 'on' : ''}><Icon name={call.muted ? 'mic_off' : 'mic'} size="0.95rem" /></button>}
          <button onClick={() => { setOpen(false); go('phone', 'call'); }} aria-label="Open call"><Icon name="phone_size" size="0.95rem" /></button>
          <button className="end" onClick={hangup} aria-label="End call"><Icon name="hang" size="0.95rem" /></button>
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Lock screen
// ---------------------------------------------------------------------------
function LockScreen({ onUnlock, openedAt }: { onUnlock: () => void; openedAt: number }) {
  const { world, session, settings } = usePhone();
  const time = useClock(world);
  const [items, setItems] = useState<Notification[]>([]);
  useEffect(() => { void api<{ items: Notification[] }>('notifications').then((r) => { if (r.ok && r.data) setItems(r.data.items.filter((n) => !n.is_read).slice(0, 3)); }); }, []);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Enter' || e.key === 'ArrowUp' || e.key === ' ') { e.preventDefault(); onUnlock(); } };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onUnlock]);
  const w = world && WEATHER[world.weather];
  return (
    <div className="ph-lock" onClick={onUnlock}>
      <div className="ph-lock-city">LOS SANTOS</div>
      <div className="ph-lock-time">{time}</div>
      <div className="ph-lock-date">{serverDate(session.serverTime, openedAt)}</div>
      {w && <div className="ph-lock-weather"><Icon name={w.icon} size="1rem" /> {w.label}</div>}
      <div className="ph-lock-notes">
        {items.map((n) => (
          <div key={n.id} className="ph-lock-note">
            <Icon name={APP_STYLE[n.app]?.icon ?? 'bell'} size="0.95rem" />
            <div><strong>{settings.lockPreview === 'hidden' ? 'Notification' : n.title}</strong>{settings.lockPreview === 'full' && <span>{n.body}</span>}</div>
          </div>
        ))}
      </div>
      <button className="ph-unlock" onClick={onUnlock}>Click or press Enter to unlock</button>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Home: widgets, searchable launcher, grid with edit mode + folders, dock
// ---------------------------------------------------------------------------
function allApps(session: Session): AppDef[] {
  const ext = (session.external ?? []).map((e) => ({ id: e.id, label: e.label, external: true, icon: e.icon, color: e.color }));
  return [...session.apps.filter((a) => a.installed !== false), ...ext];
}

function AppIcon({ app, badge, onClick, onPointerDown, editing, size = 'md' }: { app: AppDef; badge?: number; onClick?: () => void; onPointerDown?: (e: React.PointerEvent) => void; editing?: boolean; size?: 'md' | 'sm' }) {
  const st = APP_STYLE[app.id] ?? { icon: app.icon ?? 'box', color: app.color ?? '#3a3346' };
  return (
    <button className={`ph-app ${size}${editing ? ' editing' : ''}`} onClick={onClick} onPointerDown={onPointerDown} aria-label={badge ? `${app.label}, ${badge} unread` : app.label}>
      <span className="ph-app-icon" style={{ '--c': st.color } as React.CSSProperties}><Icon name={st.icon} size={size === 'sm' ? '1.55rem' : '1.55rem'} />{!!badge && <em>{badge > 99 ? '99+' : badge}</em>}</span>
      {size === 'md' && <span className="ph-app-label">{app.label}</span>}
    </button>
  );
}

const PAGE_SIZE = 16; // 4 columns x 4 rows per home page

function Home({ openedAt }: { openedAt: number }) {
  const { session, settings, saveSettings, go, world, unread, badges } = usePhone();
  const apps = useMemo(() => allApps(session), [session]);
  const byId = useMemo(() => Object.fromEntries(apps.map((a) => [a.id, a])), [apps]);
  const [search, setSearch] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  const [folderOpen, setFolderOpen] = useState<number | null>(null);
  const [menuFor, setMenuFor] = useState<string | null>(null);
  const [page, setPage] = useState(0);
  const [area, setArea] = useState<string | null>(null);
  const [dragFrom, setDragFrom] = useState<number | null>(null);
  const holdTimer = useRef<number>();
  const swipe = useRef<number | null>(null);
  const dock = apps.filter((a) => a.dock);

  // Layout: saved order (apps + folders), plus any new non-dock apps appended. Unknown ids are dropped.
  const layout: LayoutEntry[] = useMemo(() => {
    const valid = new Set(apps.filter((a) => !a.dock).map((a) => a.id));
    const out: LayoutEntry[] = [];
    const used = new Set<string>();
    for (const e of settings.layout ?? []) {
      if (typeof e === 'string') { if (valid.has(e) && !used.has(e)) { out.push(e); used.add(e); } }
      else { const inside = e.apps.filter((id) => valid.has(id) && !used.has(id)); inside.forEach((id) => used.add(id)); if (inside.length) out.push({ folder: e.folder, apps: inside }); }
    }
    for (const a of apps) if (!a.dock && !used.has(a.id)) out.push(a.id);
    return out;
  }, [apps, settings.layout]);
  const pages = Math.max(1, Math.ceil(layout.length / PAGE_SIZE));
  useEffect(() => { if (page >= pages) setPage(pages - 1); }, [page, pages]);

  // Weather widget: the area you are in (from the game) and the server weather. No temperature is shown: the server
  // does not provide one, and an invented number would be wrong.
  useEffect(() => {
    if (!settings.widgets.weather) return;
    void nui<{ label: string }>('locationLabel').then((r) => { if (r.ok && r.data) setArea(r.data.label.split(', ').pop() ?? r.data.label); });
  }, [settings.widgets.weather]);

  const badgeOf = (id: string) => (id === 'messages' ? unread : badges[id] ?? 0);
  const open = (a: AppDef) => {
    if (editing) { setMenuFor(a.id); return; }
    if (a.external) { void nui('openExternal', { id: a.id }); return; }
    go(a.id);
  };
  const startHold = (i: number) => (e: React.PointerEvent) => {
    if (editing) { setDragFrom(i); (e.currentTarget as HTMLElement).releasePointerCapture?.(e.pointerId); return; }
    holdTimer.current = window.setTimeout(() => setEditing(true), 550);
  };
  const endHold = () => window.clearTimeout(holdTimer.current);
  // Drag to reorder (edit mode): drop an app or folder on another cell to move it there.
  const dropOn = (to: number) => {
    if (dragFrom === null || dragFrom === to) { setDragFrom(null); return; }
    const next = [...layout];
    const [item] = next.splice(dragFrom, 1);
    next.splice(to, 0, item);
    setDragFrom(null);
    void saveSettings({ layout: next });
  };
  const moveBy = (id: string, dir: -1 | 1) => {
    const i = layout.indexOf(id);
    const j = i + dir;
    if (i < 0 || j < 0 || j >= layout.length) return;
    const next = [...layout];
    [next[i], next[j]] = [next[j], next[i]];
    void saveSettings({ layout: next });
  };
  const toFolder = (id: string, target: number | 'new') => {
    let next = layout.filter((e) => e !== id).map((e) => (typeof e === 'string' ? e : { ...e, apps: e.apps.filter((x) => x !== id) })).filter((e) => typeof e === 'string' || e.apps.length > 0);
    if (target === 'new') next = [...next, { folder: 'Folder', apps: [id] }];
    else next = next.map((e, i) => (i === target && typeof e !== 'string' ? { ...e, apps: [...e.apps, id] } : e));
    setMenuFor(null);
    void saveSettings({ layout: next });
  };
  const outOfFolder = (id: string) => {
    const next = layout.map((e) => (typeof e === 'string' ? e : { ...e, apps: e.apps.filter((x) => x !== id) })).filter((e) => typeof e === 'string' || e.apps.length > 0);
    void saveSettings({ layout: [...next, id] });
    setMenuFor(null);
  };
  const renameFolder = (i: number, name: string) => {
    const next = layout.map((e, j) => (j === i && typeof e !== 'string' ? { ...e, folder: name.slice(0, 20) || 'Folder' } : e));
    void saveSettings({ layout: next });
  };

  const q = (search ?? '').trim().toLowerCase();
  const found = q ? apps.filter((a) => a.label.toLowerCase().includes(q)) : [];
  const w = world && WEATHER[world.weather];
  const now = new Date((session.serverTime + (Date.now() - openedAt) / 1000) * 1000);
  const folders = layout.map((e, i) => (typeof e === 'string' ? null : { i, e })).filter(Boolean) as { i: number; e: { folder: string; apps: string[] } }[];
  const showWidgets = page === 0 && (settings.widgets.weather || settings.widgets.clock);

  return (
    <div className="ph-home" onWheel={(e) => { if (search === null && Math.abs(e.deltaY) > 30) setPage((p) => Math.max(0, Math.min(pages - 1, p + (e.deltaY > 0 ? 1 : -1)))); }}
      onPointerDown={(e) => { swipe.current = e.clientX; }} onPointerUp={(e) => {
        endHold();
        if (swipe.current !== null && dragFrom === null) { const dx = e.clientX - swipe.current; if (Math.abs(dx) > 60) setPage((p) => Math.max(0, Math.min(pages - 1, p + (dx < 0 ? 1 : -1)))); }
        swipe.current = null;
      }} onPointerLeave={endHold}>
      {search !== null ? (
        <>
          <label className="ph-search"><Icon name="search" size="0.9rem" /><input autoFocus placeholder="Search apps" value={search} onChange={(e) => setSearch(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Escape') { e.stopPropagation(); setSearch(null); } if (e.key === 'Enter' && found[0]) open(found[0]); }} /><button className="ph-link" onClick={() => setSearch(null)}>Cancel</button></label>
          <div className="ph-grid">
            {q && found.length === 0 && <div className="ph-empty">No apps match “{search}”.</div>}
            {(q ? found : apps).map((a) => <AppIcon key={a.id} app={a} badge={badgeOf(a.id)} onClick={() => open(a)} />)}
          </div>
        </>
      ) : (
        <>
          {showWidgets && (
            <div className="ph-widgets">
              {settings.widgets.weather && (
                <div className="ph-widget ph-weather">
                  <div className="ph-w-place"><Icon name="pin" size="0.8rem" /> {area ?? 'Los Santos'}</div>
                  {w ? <><div className="ph-w-big"><Icon name={w.icon} size="1.9rem" /></div><div className="ph-w-cond"><Icon name={w.icon} size="0.85rem" /> {w.label}</div></>
                    : <div className="ph-w-cond">Weather unavailable</div>}
                </div>
              )}
              {settings.widgets.clock && (
                <div className="ph-widget ph-calendar">
                  <div className="ph-w-day"><Icon name="clock" size="0.8rem" /> {now.toLocaleDateString('en-US', { weekday: 'long' }).toUpperCase()}</div>
                  <div className="ph-w-date">{now.getDate()}</div>
                  <div className="ph-w-month">{now.toLocaleDateString('en-US', { month: 'long' })}</div>
                </div>
              )}
            </div>
          )}

          <div className="ph-pages">
            <div className="ph-pages-track" style={{ transform: `translateX(-${page * 100}%)` }}>
              {Array.from({ length: pages }, (_, p) => (
                <div className="ph-grid ph-page" key={p} aria-hidden={p !== page}>
                  {layout.slice(p * PAGE_SIZE, (p + 1) * PAGE_SIZE).map((e, k) => {
                    const i = p * PAGE_SIZE + k;
                    const cellProps = { className: `ph-cell${dragFrom === i ? ' dragging' : ''}${dragFrom !== null && dragFrom !== i ? ' drop' : ''}`, onPointerUp: () => { if (dragFrom !== null) dropOn(i); } };
                    return typeof e === 'string' ? (
                      byId[e] && <div key={e} {...cellProps}><AppIcon app={byId[e]} badge={badgeOf(e)} editing={editing} onClick={() => open(byId[e])} onPointerDown={startHold(i)} /></div>
                    ) : (
                      <div key={`f${i}`} {...cellProps}>
                        <button className={`ph-app md${editing ? ' editing' : ''}`} onClick={() => setFolderOpen(i)} onPointerDown={startHold(i)} aria-label={`Folder ${e.folder}`}>
                          <span className="ph-app-icon ph-folder">{e.apps.slice(0, 4).map((id) => <i key={id} style={{ background: (APP_STYLE[id] ?? { color: byId[id]?.color ?? '#555' }).color }} />)}</span>
                          <span className="ph-app-label">{e.folder}</span>
                        </button>
                      </div>
                    );
                  })}
                </div>
              ))}
            </div>
          </div>

          {editing ? <button className="ph-done" onClick={() => { setEditing(false); setMenuFor(null); setDragFrom(null); }}>Done</button>
            : <button className="ph-searchpill" onClick={() => setSearch('')}><Icon name="search" size="0.8rem" /> Search</button>}
          {pages > 1 && <div className="ph-dots" role="tablist" aria-label="Home pages">{Array.from({ length: pages }, (_, p) => <button key={p} role="tab" aria-selected={p === page} aria-label={`Page ${p + 1}`} className={p === page ? 'on' : ''} onClick={() => setPage(p)} />)}</div>}
          {editing && <div className="ph-hint">Drag an app onto another spot to move it. Tap an app for folders.</div>}
        </>
      )}

      <div className="ph-dock">
        {dock.map((a) => <AppIcon key={a.id} app={a} size="sm" badge={badgeOf(a.id)} onClick={() => open(a)} />)}
      </div>

      {menuFor && (
        <div className="ph-sheet" role="dialog" aria-label="App options">
          <div className="ph-sheet-title">{byId[menuFor]?.label}</div>
          {layout.includes(menuFor) && <><button onClick={() => moveBy(menuFor, -1)}>Move earlier</button><button onClick={() => moveBy(menuFor, 1)}>Move later</button></>}
          <button onClick={() => toFolder(menuFor, 'new')}><Icon name="folder" size="1rem" /> New folder</button>
          {folders.map(({ i, e }) => <button key={i} onClick={() => toFolder(menuFor, i)}><Icon name="folder" size="1rem" /> Move to {e.folder}</button>)}
          {folders.some(({ e }) => e.apps.includes(menuFor)) && <button onClick={() => outOfFolder(menuFor)}>Remove from folder</button>}
          <button className="muted" onClick={() => setMenuFor(null)}>Cancel</button>
        </div>
      )}
      {folderOpen !== null && typeof layout[folderOpen] !== 'string' && layout[folderOpen] && (
        <div className="ph-folder-open" onClick={(ev) => { if (ev.target === ev.currentTarget) setFolderOpen(null); }}>
          <div className="ph-folder-box">
            {editing ? <input className="ph-input" defaultValue={(layout[folderOpen] as { folder: string }).folder} onBlur={(ev) => renameFolder(folderOpen, ev.target.value)} aria-label="Folder name" />
              : <div className="ph-folder-name">{(layout[folderOpen] as { folder: string }).folder}</div>}
            <div className="ph-grid">
              {(layout[folderOpen] as { apps: string[] }).apps.map((id) => byId[id] && <AppIcon key={id} app={byId[id]} badge={badgeOf(id)} editing={editing} onClick={() => { setFolderOpen(null); open(byId[id]); }} />)}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Apps
// ---------------------------------------------------------------------------
function AppHost({ app }: { app: string }) {
  switch (app) {
    case 'phone': return <PhoneApp />;
    case 'messages': return <MessagesApp />;
    case 'contacts': return <ContactsApp />;
    case 'settings': return <SettingsApp />;
    case 'store': return <StoreApp />;
    case 'flock': return <FlockApp />;
    case 'bank': return <BankApp />;
    case 'garage': return <GarageApp />;
    case 'market': return <MarketApp />;
    case 'notes': return <NotesApp />;
    case 'calculator': return <CalculatorApp />;
    case 'maps': return <MapsApp />;
    case 'services': return <ServicesApp />;
    case 'mail': return <MailApp />;
    case 'voicemail': return <VoicemailApp />;
    case 'camera': return <CameraApp />;
    case 'jobs': return <JobsApp />;
    case 'bills': return <BillsApp />;
    case 'music': return <MusicApp />;
    case 'news': return <NewsApp />;
    case 'racing': return <RacingApp />;
    default: return <div className="ph-empty">This app is not available.</div>;
  }
}

export function AppHeader({ title, onBack, right }: { title: ReactNode; onBack?: () => void; right?: ReactNode }) {
  const { go } = usePhone();
  return (
    <div className="ph-header">
      <button className="ph-icon-btn" aria-label="Back" onClick={onBack ?? (() => go(null))}><Icon name="back" size="1.1rem" /></button>
      <div className="ph-header-title">{title}</div>
      <div className="ph-header-right">{right}</div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Call screen (incoming / outgoing / connected / ended)
// ---------------------------------------------------------------------------
function CallScreen() {
  const { call, answer, decline, hangup, mute } = usePhone();
  const [, tick] = useState(0);
  useEffect(() => { const t = window.setInterval(() => tick((x) => x + 1), 1000); return () => window.clearInterval(t); }, []);
  if (!call) return null;
  const secs = call.since ? Math.floor(Date.now() / 1000 - call.since) : 0;
  const timer = `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, '0')}`;
  const REASONS: Record<string, string> = { declined: 'Declined', timeout: 'No answer', cancelled: 'Cancelled', hangup: 'Call ended', busy: 'Line busy',
    unavailable: 'Unavailable', dropped: 'Call dropped', voice_failed: 'Audio could not connect', character_changed: 'Call ended' };
  const status = call.state === 'incoming' ? 'Incoming call' : call.state === 'outgoing' ? 'Calling…' : call.state === 'connected' ? timer : (REASONS[call.reason ?? ''] ?? call.reason ?? 'Call ended');
  return (
    <div className="ph-call">
      <div className="ph-call-avatar"><VMark size="2.4rem" /></div>
      <div className="ph-call-name">{call.display}</div>
      <div className="ph-call-status" aria-live="polite">{status}</div>
      {call.state === 'incoming' ? (
        <div className="ph-call-actions">
          <button className="ph-round red" onClick={decline} aria-label="Decline"><Icon name="hang" size="1.5rem" /></button>
          <button className="ph-round green" onClick={answer} aria-label="Answer" autoFocus><Icon name="call" size="1.5rem" /></button>
        </div>
      ) : call.state === 'ended' ? null : (
        <div className="ph-call-actions">
          {call.state === 'connected' && (
            <button className={`ph-round${call.muted ? ' on' : ''}`} onClick={mute} aria-label={call.muted ? 'Unmute' : 'Mute'} title="Muting stops the other person hearing you">
              <Icon name={call.muted ? 'mic_off' : 'mic'} size="1.4rem" />
            </button>
          )}
          <button className="ph-round red" onClick={hangup} aria-label="Hang up"><Icon name="hang" size="1.5rem" /></button>
        </div>
      )}
    </div>
  );
}
