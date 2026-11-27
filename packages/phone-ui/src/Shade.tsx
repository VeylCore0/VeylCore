// Notification centre: quick settings on top, then the character's notifications. Opened by tapping the status bar.
import { useEffect, useRef } from 'react';
import { api } from './api';
import { followRoute, loadNotifications, updateSettings } from './controller';
import { listTime } from './format';
import { Ico } from './icons';
import { useBack } from './nav';
import { getState, setState, useStore } from './store';
import { APP_LOOK, AppIcon, Empty, IconButton, Slider, cx, say } from './ui';
import type { Notification } from './types';

const LOOK = (app: string) => APP_LOOK[app] ?? (app === 'apartments' ? { icon: 'home', color: '#8b63d6' } : { icon: 'bell', color: '#6f7585' });

export function Shade() {
  const open = useStore((s) => s.shade);
  const settings = useStore((s) => s.settings);
  const items = useStore((s) => s.notifications);
  const unread = useStore((s) => s.unread.notifications);
  const external = useStore((s) => s.external);
  const wasOpen = useRef(false);
  useBack(open, () => { setState({ shade: false }); return true; });

  useEffect(() => {
    if (open) { void loadNotifications(); wasOpen.current = true; return; }
    if (wasOpen.current) {
      wasOpen.current = false;
      if (getState().unread.notifications > 0) {
        void api('notificationsRead', 'all');
        setState((s) => ({ unread: { ...s.unread, notifications: 0 }, notifications: s.notifications?.map((n) => ({ ...n, read: true })) ?? null }));
      }
    }
  }, [open]);

  const clear = async () => {
    if (!say(await api('notificationsClear', 'all'))) return;
    setState((s) => ({ notifications: [], unread: { ...s.unread, notifications: 0 } }));
  };
  const remove = async (n: Notification) => {
    setState((s) => ({ notifications: s.notifications?.filter((x) => x.id !== n.id) ?? null }));
    await api('notificationsClear', [n.id]);
  };
  const look = (app: string) => { const e = external.find((x) => x.id === app); return e ? { icon: e.icon, color: e.color } : LOOK(app); };

  return (
    <div className={cx('ph-shade', open && 'open')} aria-hidden={!open}>
      <div className="ph-shade-top">
        <div className="ph-quick">
          <button className={cx('ph-qtile', settings.airplane && 'on')} onClick={() => updateSettings({ airplane: !settings.airplane })}><Ico name="plane" size={18} /><span>Airplane</span></button>
          <button className={cx('ph-qtile', settings.dnd && 'on')} onClick={() => updateSettings({ dnd: !settings.dnd })}><Ico name="moon" size={18} /><span>Focus</span></button>
          <button className={cx('ph-qtile', settings.silent && 'on')} onClick={() => updateSettings({ silent: !settings.silent })}><Ico name={settings.silent ? 'bellOff' : 'bell'} size={18} /><span>Silent</span></button>
        </div>
        <div className="ph-quick-sliders">
          <div><Ico name="sun" size={16} /><Slider label="Brightness" value={settings.brightness} min={20} onChange={(v) => setState((s) => ({ settings: { ...s.settings, brightness: v } }))} onCommit={(v) => updateSettings({ brightness: v })} /></div>
          <div><Ico name="volume" size={16} /><Slider label="Volume" value={settings.volume} onChange={(v) => setState((s) => ({ settings: { ...s.settings, volume: v } }))} onCommit={(v) => updateSettings({ volume: v })} /></div>
        </div>
      </div>
      <div className="ph-shade-head">
        <h2>Notifications{unread > 0 && <em>{unread}</em>}</h2>
        {!!items?.length && <IconButton icon="trash" label="Clear all" onClick={clear} size={17} />}
      </div>
      <div className="ph-shade-list">
        {items === null && <div className="ph-shade-load">Loading...</div>}
        {items?.length === 0 && <Empty icon="bell" title="All caught up" text="New notifications show up here." />}
        {items?.map((n) => {
          const l = look(n.app);
          return (
            <div key={n.id} className={cx('ph-notif', !n.read && 'new')}>
              <button className="ph-notif-main" onClick={() => { setState({ shade: false }); followRoute(n.app, n.route); }}>
                <AppIcon icon={l.icon} color={l.color} size={34} />
                <span className="ph-notif-text"><strong>{n.title}</strong><span>{n.body}</span></span>
                <time>{listTime(n.time)}</time>
              </button>
              <button className="ph-notif-x" onClick={() => remove(n)} aria-label="Dismiss"><Ico name="x" size={14} /></button>
            </div>
          );
        })}
      </div>
      <button className="ph-shade-grab" onClick={() => setState({ shade: false })} aria-label="Close notifications"><span /></button>
    </div>
  );
}
