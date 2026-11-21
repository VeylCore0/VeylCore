import { useState, type ReactNode } from 'react';
import { Icon } from '@veyl/ui';
import { api, playNotify, playRing, stopRing } from '../api';
import { AppHeader, usePhone } from '../App';
import type { Settings } from '../types';

type Page = 'main' | 'appearance' | 'home' | 'sounds' | 'notifications' | 'privacy' | 'display' | 'about';

const WALLPAPER_LABEL: Record<string, string> = { aurora: 'Aurora', dusk: 'Dusk', vinewood: 'Vinewood', midnight: 'Midnight', violet: 'Violet', mono: 'Mono' };

function Toggle({ label, hint, value, onChange }: { label: string; hint?: string; value: boolean; onChange: (v: boolean) => void }) {
  return (
    <label className="ph-toggle">
      <span><strong>{label}</strong>{hint && <span className="muted">{hint}</span>}</span>
      <input type="checkbox" role="switch" checked={value} onChange={(e) => onChange(e.target.checked)} />
    </label>
  );
}

function Choice<T extends string>({ label, value, options, onChange, render }: { label: string; value: T; options: T[]; onChange: (v: T) => void; render?: (v: T) => ReactNode }) {
  return (
    <div className="ph-choice">
      <div className="ph-section">{label}</div>
      <div className="ph-choice-row" role="radiogroup" aria-label={label}>
        {options.map((o) => <button key={o} role="radio" aria-checked={o === value} className={o === value ? 'on' : ''} onClick={() => onChange(o)}>{render ? render(o) : o}</button>)}
      </div>
    </div>
  );
}

function Slider({ label, value, min, max, step = 1, onChange, format }: { label: string; value: number; min: number; max: number; step?: number; onChange: (v: number) => void; format?: (v: number) => string }) {
  return (
    <label className="ph-slider"><span>{label}<span className="muted">{format ? format(value) : value}</span></span>
      <input type="range" min={min} max={max} step={step} value={value} onChange={(e) => onChange(Number(e.target.value))} /></label>
  );
}

export function SettingsApp() {
  const { settings, saveSettings, session, toast } = usePhone();
  const [page, setPage] = useState<Page>('main');
  const set = (patch: Partial<Settings>) => void saveSettings(patch);
  const back = () => { stopRing(); setPage('main'); };

  if (page === 'main') {
    const rows: { id: Page; label: string; icon: string }[] = [
      { id: 'appearance', label: 'Wallpaper & colour', icon: 'sparkle' }, { id: 'home', label: 'Home screen', icon: 'home' },
      { id: 'sounds', label: 'Sounds & focus', icon: 'bell' }, { id: 'notifications', label: 'Notifications', icon: 'chat' },
      { id: 'privacy', label: 'Privacy', icon: 'lock' }, { id: 'display', label: 'Size & position', icon: 'phone_size' }, { id: 'about', label: 'About', icon: 'user' },
    ];
    return (
      <div className="ph-appview">
        <AppHeader title="Settings" />
        <div className="ph-body">
          <Profile />
          <ul className="ph-list">
            {rows.map((r) => <li key={r.id}><button className="ph-row" onClick={() => setPage(r.id)}><span className="ph-row-icon"><Icon name={r.icon} size="0.95rem" /></span><span className="ph-row-main"><strong>{r.label}</strong></span><Icon name="chevron" size="0.9rem" /></button></li>)}
          </ul>
        </div>
      </div>
    );
  }

  return (
    <div className="ph-appview">
      <AppHeader title={page === 'appearance' ? 'Wallpaper & colour' : page === 'home' ? 'Home screen' : page === 'sounds' ? 'Sounds & focus' : page === 'notifications' ? 'Notifications'
        : page === 'privacy' ? 'Privacy' : page === 'display' ? 'Size & position' : 'About'} onBack={back} />
      <div className="ph-body ph-form">
        {page === 'appearance' && (
          <>
            <Choice label="Wallpaper" value={settings.wallpaper} options={session.presets.wallpapers} onChange={(v) => set({ wallpaper: v })}
              render={(v) => <span className={`ph-wall-swatch w-${v}`}>{WALLPAPER_LABEL[v] ?? v}</span>} />
            <Choice label="Accent colour" value={settings.accent} options={session.presets.accents} onChange={(v) => set({ accent: v })}
              render={(v) => <span className="ph-accent" style={{ background: v }} aria-label={v} />} />
          </>
        )}
        {page === 'home' && (
          <>
            <Toggle label="Clock & weather widget" value={settings.widgets.clock} onChange={(v) => set({ widgets: { ...settings.widgets, clock: v } })} />
            <Toggle label="Recent conversations widget" value={settings.widgets.recent} onChange={(v) => set({ widgets: { ...settings.widgets, recent: v } })} />
            <Toggle label="Bank balance widget" hint="Hidden until you tap it (see Privacy)" value={settings.widgets.bank} onChange={(v) => set({ widgets: { ...settings.widgets, bank: v } })} />
            <p className="ph-help">To rearrange apps or make folders, hold an app on the home screen.</p>
            <button className="ph-btn" onClick={() => { set({ layout: null }); toast('Home screen reset'); }}>Reset home screen layout</button>
          </>
        )}
        {page === 'sounds' && (
          <>
            <Toggle label="Silent" hint="No ringtone or notification sounds" value={settings.silent} onChange={(v) => set({ silent: v })} />
            <Toggle label="Do not disturb" hint="Calls go to missed calls; no banners or sounds" value={settings.dnd} onChange={(v) => set({ dnd: v })} />
            <Choice label="Ringtone" value={settings.ringtone} options={session.presets.ringtones} onChange={(v) => { set({ ringtone: v }); playRing(v, settings.ringVolume); window.setTimeout(stopRing, 2000); }} />
            <Slider label="Ringtone volume" value={settings.ringVolume} min={0} max={100} format={(v) => `${v}%`} onChange={(v) => set({ ringVolume: v })} />
            <Choice label="Notification sound" value={settings.notifySound} options={session.presets.notifySounds} onChange={(v) => { set({ notifySound: v }); playNotify(v, settings.notifyVolume); }} />
            <Slider label="Notification volume" value={settings.notifyVolume} min={0} max={100} format={(v) => `${v}%`} onChange={(v) => set({ notifyVolume: v })} />
            <button className="ph-btn" onClick={() => playNotify(settings.notifySound, settings.notifyVolume)}>Test notification sound</button>
          </>
        )}
        {page === 'notifications' && (
          <>
            <p className="ph-help">Muted apps still keep their notifications in history; they just don't show banners or play sounds.</p>
            {session.apps.map((a) => (
              <Toggle key={a.id} label={a.label} hint={settings.appPrefs[a.id]?.muted ? 'Muted' : 'Banners and sounds on'} value={!settings.appPrefs[a.id]?.muted}
                onChange={(v) => set({ appPrefs: { ...settings.appPrefs, [a.id]: { muted: !v } } })} />
            ))}
          </>
        )}
        {page === 'privacy' && (
          <>
            <Choice label="Lock screen & banner previews" value={settings.lockPreview} options={['full', 'sender', 'hidden'] as const as unknown as Settings['lockPreview'][]}
              onChange={(v) => set({ lockPreview: v })} render={(v) => (v === 'full' ? 'Show all' : v === 'sender' ? 'Sender only' : 'Hide')} />
            <Toggle label="Read receipts" hint="Let people see when you've read their messages" value={settings.readReceipts} onChange={(v) => set({ readReceipts: v })} />
            <Toggle label="Show bank balance" hint="Shown on the home screen widget" value={settings.showBank} onChange={(v) => set({ showBank: v })} />
          </>
        )}
        {page === 'display' && (
          <>
            <Slider label="Phone size" value={settings.scale} min={0.75} max={1.3} step={0.05} format={(v) => `${Math.round(v * 100)}%`} onChange={(v) => set({ scale: v })} />
            <Choice label="Position" value={settings.position} options={['bottom-right', 'center-right', 'bottom-left'] as Settings['position'][]} onChange={(v) => set({ position: v })}
              render={(v) => (v === 'bottom-right' ? 'Bottom right' : v === 'center-right' ? 'Middle right' : 'Bottom left')} />
            <Toggle label="Reduce motion" hint="No sliding or bouncing animations" value={settings.reducedMotion} onChange={(v) => set({ reducedMotion: v })} />
          </>
        )}
        {page === 'about' && (
          <>
            <div className="ph-about"><span className="muted">My number</span><strong>{session.display}</strong></div>
            <div className="ph-about"><span className="muted">Calls</span><strong>{session.voice.available ? `Available (${session.voice.provider})` : 'Unavailable'}</strong></div>
            {!session.voice.available && <p className="ph-help">{session.voice.reason}</p>}
            <p className="ph-help">Your number and phone data belong to your character. A replacement phone restores everything; someone else's phone does not give access to their account.</p>
          </>
        )}
      </div>
    </div>
  );
}

function Profile() {
  const { session, toast } = usePhone();
  const [name, setName] = useState(session.name);
  const [editing, setEditing] = useState(false);
  const save = async () => {
    const r = await api<{ name: string }>('setProfile', name);
    toast(r.message ?? (r.ok ? 'Saved' : 'Failed'), r.ok ? 'ok' : 'error');
    if (r.ok) setEditing(false);
  };
  return (
    <div className="ph-profile">
      <div className="ph-avatar xl">{name.split(' ').map((w) => w[0]).slice(0, 2).join('').toUpperCase()}</div>
      {editing ? (
        <div className="ph-inline"><input className="ph-input" value={name} maxLength={48} onChange={(e) => setName(e.target.value)} /><button className="ph-btn primary" onClick={() => void save()}>Save</button></div>
      ) : (
        <button className="ph-profile-name" onClick={() => setEditing(true)}>{name} <Icon name="edit" size="0.8rem" /></button>
      )}
      <div className="muted">{session.display}</div>
    </div>
  );
}
