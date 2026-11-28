import { useEffect, useState, type CSSProperties } from 'react';
import { loadStations, syncSpeakers } from './music';
import { announceReady, useNuiMessage } from '@veyl/ui';
import { post } from './api';
import { VIEWS } from './apps';
import { CallScreen, useSecondTick } from './CallScreen';
import { closePhone, dismissBanner, followRoute, goHome, onApps, onClosed, onNavigate, onOpen, onPushEvent, onReset, onSession, onTick } from './controller';
import { Home } from './Home';
import { LockScreen } from './LockScreen';
import { Setup } from './Setup';
import { clockText, duration, nowSec } from './format';
import { Battery, Ico, SignalBars } from './icons';
import { goBack } from './nav';
import { Shade } from './Shade';
import { getState, setState, useStore } from './store';
import { api } from './api';
import { useBack } from './nav';
import { Avatar, Button, say } from './ui';
import { APP_LOOK, AppIcon, ToastHost, cx } from './ui';
import type { Banner, ExternalApp, Hello, PushEvent, World } from './types';

const SCALE_BASE = 940;
/** Automatic scale for the screen height, times the player's size setting (percent), never taller than the screen. */
const calcScale = (size: number) => {
  const auto = Math.max(0.6, Math.min(1.25, window.innerHeight / SCALE_BASE));
  return Math.min(auto * (size / 100), (window.innerHeight - 24) / 800);
};
function useScale(size: number) {
  const [s, set] = useState(() => calcScale(size));
  useEffect(() => {
    const f = () => set(calcScale(size));
    f();
    window.addEventListener('resize', f);
    return () => window.removeEventListener('resize', f);
  }, [size]);
  return s;
}

/** Readable text colour on the accent. */
function inkFor(hex: string) {
  const m = /^#([0-9a-f]{6})$/i.exec(hex);
  if (!m) return '#fff';
  const n = parseInt(m[1], 16);
  const lum = (0.299 * ((n >> 16) & 255) + 0.587 * ((n >> 8) & 255) + 0.114 * (n & 255)) / 255;
  return lum > 0.62 ? '#14121c' : '#ffffff';
}

const lookOf = (app: string, external: ExternalApp[]) => {
  const e = external.find((x) => x.id === app);
  if (e) return { icon: e.icon, color: e.color };
  return APP_LOOK[app] ?? (app === 'apartments' ? { icon: 'home', color: '#8b63d6' } : { icon: 'bell', color: '#6f7585' });
};

function StatusBar() {
  const world = useStore((s) => s.world);
  const settings = useStore((s) => s.settings);
  const unread = useStore((s) => s.unread.notifications);
  const call = useStore((s) => s.call);
  const callMin = useStore((s) => s.callMin);
  const shade = useStore((s) => s.shade);
  const locked = useStore((s) => !!s.hello?.locked);
  const noSim = useStore((s) => s.hello?.sim === false && !s.hello.locked);
  const pill = !!call && callMin && call.state !== 'ended';
  useSecondTick(pill && call?.state === 'connected');
  return (
    <div className="ph-status">
      <button className="ph-status-time" onClick={() => !locked && setState({ shade: !shade })} aria-label="Notifications">
        {world ? clockText(world.hour, world.minute) : ''}
        {unread > 0 && <i className="ph-status-dot" />}
      </button>
      <button className={cx('ph-island', pill && 'pill')} onClick={() => (pill ? setState({ callMin: false }) : !locked && setState({ shade: !shade }))}
        aria-label={pill ? 'Return to call' : 'Notifications'}>
        {pill && call ? (
          <>
            <span className="ph-island-wave"><i /><i /><i /><i /></span>
            <span className="ph-island-name">{call.peer.display}</span>
            <span className="ph-island-time">{call.state === 'connected' ? duration(nowSec() - (call.answeredAt ?? call.startedAt)) : '...'}</span>
          </>
        ) : <span className="ph-island-cam" />}
      </button>
      <div className="ph-status-right">
        {settings.airplane && <Ico name="plane" size={14} />}
        {settings.dnd && <Ico name="moon" size={13} />}
        {settings.silent && <Ico name="bellOff" size={13} />}
        {noSim && <span className="ph-nosim">No SIM</span>}
        <SignalBars off={settings.airplane || noSim} />
        <Battery />
      </div>
    </div>
  );
}

function BannerCard({ b, external }: { b: Banner; external: ExternalApp[] }) {
  const look = lookOf(b.app, external);
  const open = () => { dismissBanner(b.id); followRoute(b.app, b.route); };
  return (
    <button className={cx('ph-banner', b.kind)} onClick={open}>
      <AppIcon icon={look.icon} color={look.color} size={34} />
      <span className="ph-banner-text"><strong>{b.title}</strong><span>{b.body}</span></span>
      <time>now</time>
    </button>
  );
}

function Banners({ inside }: { inside: boolean }) {
  const banners = useStore((s) => s.banners);
  const external = useStore((s) => s.external);
  const list = inside ? banners.filter((b) => b.kind !== 'call') : banners;
  if (!list.length) return null;
  return (
    <div className={cx('ph-banners', inside ? 'inside' : 'outside')}>
      {list.map((b) => <BannerCard key={b.id} b={b} external={external} />)}
      {!inside && banners.some((b) => b.kind === 'call') && <div className="ph-banner-hint">Press F1 to answer</div>}
    </div>
  );
}

/** Someone nearby shared their number: save them or not. Lives on the server for 60 seconds. */
function SharePrompt() {
  const share = useStore((s) => s.share);
  const locked = useStore((s) => !!s.hello?.locked);
  useBack(!!share && !locked, () => { setState({ share: null }); return true; });
  if (!share || locked) return null;
  const answer = async (accept: boolean) => {
    setState({ share: null });
    const r = await api('shareAnswer', share.id, accept);
    if (accept || !r.ok) say(r);
  };
  return (
    <div className="ph-share-wrap">
      <div className="ph-share-dim" onClick={() => setState({ share: null })} />
      <div className="ph-share-card" role="dialog" aria-label="Number shared with you">
        <Avatar name={share.from.name} id={share.from.number} size={72} />
        <strong>{share.from.name}</strong>
        <span>wants to share their number</span>
        <b>{share.from.display}</b>
        <div className="ph-share-actions">
          <Button kind="ghost" onClick={() => answer(false)}>Not now</Button>
          <Button kind="primary" onClick={() => answer(true)}>Save contact</Button>
        </div>
      </div>
    </div>
  );
}

function AppHost() {
  const app = useStore((s) => s.app);
  const route = useStore((s) => s.route);
  const openId = useStore((s) => s.openId);
  const locked = useStore((s) => !!s.hello?.locked);
  const View = app ? VIEWS[app] : undefined;
  useEffect(() => { if (app && !View) goHome(); }, [app, View]);
  if (!app || !View || locked) return null;
  return <div className="ph-appview" key={`${openId}:${app}`}><View route={route} /></div>;
}

export function App() {
  const open = useStore((s) => s.open);
  const app = useStore((s) => s.app);
  const settings = useStore((s) => s.settings);
  const locked = useStore((s) => !!s.hello?.locked);
  const needsSetup = useStore((s) => !!s.hello && !s.hello.locked && !!s.hello.security && !s.hello.security.setupDone);
  const darkTop = useStore((s) => s.shade || (!!s.call && !s.callMin) || !!s.hello?.locked || (!!s.hello && !!s.hello.security && !s.hello.security.setupDone));
  const scale = useScale(settings.size);

  useEffect(() => announceReady(), []);
  // Phones playing out loud nearby (volume by distance, sent by the game client).
  useNuiMessage<{ id: number; station: string; volume: number }[]>('phone:speakers', (list) => { void loadStations().then(() => syncSpeakers(list ?? [])); });
  useNuiMessage<Hello>('phone:session', (d) => d && onSession(d));
  useNuiMessage<Hello>('phone:open', (d) => d && onOpen(d));
  useNuiMessage('phone:close', () => { onClosed(); void post('ui:typing', { typing: false }); });
  useNuiMessage<{ app: string; route?: string }>('phone:navigate', (d) => d && onNavigate(d.app, d.route));
  useNuiMessage<{ world: World }>('phone:tick', (d) => d?.world && onTick(d.world));
  useNuiMessage<{ external: ExternalApp[] }>('phone:apps', (d) => d && onApps(d.external ?? []));
  useNuiMessage<{ event: PushEvent['event']; data: unknown }>('phone:push', (d) => d && onPushEvent(d as PushEvent));
  useNuiMessage('phone:reset', () => onReset());

  // Escape: close the innermost thing; then go home; then put the phone away.
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      e.preventDefault();
      if (goBack()) return;
      const s = getState();
      if (s.app && !locked && !needsSetup) goHome(); else closePhone();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, locked, needsSetup]);

  const homeBar = () => {
    if (locked || needsSetup) return;
    const s = getState();
    if (s.call && !s.callMin && s.call.state !== 'incoming') setState({ callMin: true });
    setState({ shade: false });
    goHome();
  };

  const vars = { '--ph-accent': settings.accent, '--ph-accent-ink': inkFor(settings.accent), '--ph-scale': scale } as CSSProperties;
  const dim = Math.max(0, (100 - settings.brightness) / 100) * 0.72;

  return (
    <div className="ph-root" style={vars}>
      <div className="ph-stage">
        <div className={cx('ph-device', open && 'open', `case-${settings.case}`)}>
          <div className="ph-side l1" /><div className="ph-side l2" /><div className="ph-side r1" />
          <div className={cx('ph-screen', `wp-${settings.wallpaper}`, app ? 'in-app' : 'on-home', darkTop && 'dark-top')} data-theme={settings.theme}>
            <div className="ph-wall"><i /><i /></div>
            <div className="ph-view-home"><Home /></div>
            <AppHost />
            <StatusBar />
            <Banners inside />
            <Setup />
            <LockScreen />
            <Shade />
            <SharePrompt />
            <CallScreen />
            <ToastHost />
            <button className="ph-homebar" onClick={homeBar} aria-label="Home"><span /></button>
            <div className="ph-dim" style={{ opacity: dim }} />
          </div>
        </div>
      </div>
      {!open && <Banners inside={false} />}
    </div>
  );
}

