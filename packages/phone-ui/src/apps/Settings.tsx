// Settings: profile, focus modes, appearance (theme, wallpaper, accent, case, brightness), sounds, blocked numbers.
// Every change is applied at once and saved through `settingsSave` (reverted if the server refuses).
import { useEffect, useState } from 'react';
import { api } from '../api';
import { updateSettings } from '../controller';
import { Ico } from '../icons';
import { useBack } from '../nav';
import { playNotify, startRing, stopRing } from '../sound';
import { setState, useStore } from '../store';
import { Avatar, Button, Empty, Group, Header, Row, Segmented, Slider, Spinner, TextInput, Toggle, cx, say, toast } from '../ui';
import { AccountPage } from './Security';
import type { Settings } from '../types';

type Page = 'root' | 'account' | 'appearance' | 'sounds' | 'blocked' | 'profile';
const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
const CASE_COLOR: Record<string, string> = { black: '#16161b', blue: '#2f5fc4', green: '#2f8a63', orange: '#d1692b', pink: '#cc5a8c', purple: '#7048c0', red: '#b53a44', yellow: '#cfa73a' };
const FALLBACK = {
  wallpapers: ['default', 'sunset', 'aurora', 'midnight', 'mono'], accents: ['#8b63d6', '#4f8cff', '#2fbf8a', '#f2b443', '#ef6f7c', '#e3e3ea'],
  ringtones: ['default', 'pulse', 'classic', 'chime'], notifySounds: ['default', 'tap', 'none'], themes: ['dark', 'light'], cases: Object.keys(CASE_COLOR),
};

export function SettingsApp() {
  const [page, setPage] = useState<Page>('root');
  useBack(page !== 'root', () => { stopRing(); setPage('root'); return true; });
  if (page === 'account') return <AccountPage onBack={() => setPage('root')} />;
  if (page === 'appearance') return <Appearance onBack={() => setPage('root')} />;
  if (page === 'sounds') return <Sounds onBack={() => { stopRing(); setPage('root'); }} />;
  if (page === 'blocked') return <Blocked onBack={() => setPage('root')} />;
  if (page === 'profile') return <Profile onBack={() => setPage('root')} />;
  return <Root go={setPage} />;
}

function Root({ go }: { go: (p: Page) => void }) {
  const hello = useStore((s) => s.hello);
  const s = useStore((st) => st.settings);
  const sec = useStore((st) => st.hello?.security);
  const set = (p: Partial<Settings>) => void updateSettings(p);
  return (
    <div className="ph-app">
      <Header title="Settings" />
      <div className="ph-scroll ph-pad">
        <button className="ph-profile" onClick={() => go('profile')}>
          <Avatar name={hello?.name ?? ''} id={hello?.number} size={58} />
          <span><strong>{hello?.name ?? 'Citizen'}</strong><em>{s.streamer ? '•••-••••' : hello?.display}</em></span>
          <Ico name="forward" size={18} style={{ opacity: 0.4 }} />
        </button>
        <Group footer={sec && !sec.email && !sec.hasPin ? 'Create an account and set a PIN to keep your phone private.' : undefined}>
          <Row icon="shield" iconColor="#3a7bf0" title="Account & Security" sub={sec?.email ?? 'Not set up'} right={sec?.hasPin ? <span className="ph-sub">PIN on</span> : undefined} onClick={() => go('account')} chevron />
        </Group>
        <Group footer="Focus silences calls and sounds. Airplane mode stops calls and messages from being sent.">
          <Row icon="plane" iconColor="#e8903a" title="Airplane mode" right={<Toggle on={s.airplane} onChange={(v) => set({ airplane: v })} label="Airplane mode" />} />
          <Row icon="moon" iconColor="#6a6cf0" title="Do Not Disturb" right={<Toggle on={s.dnd} onChange={(v) => set({ dnd: v })} label="Do Not Disturb" />} />
          <Row icon="bellOff" iconColor="#c25661" title="Silent mode" right={<Toggle on={s.silent} onChange={(v) => set({ silent: v })} label="Silent mode" />} />
        </Group>
        <Group>
          <Row icon="sun" iconColor="#3a7bf0" title="Appearance" sub={`${cap(s.theme)} · ${cap(s.wallpaper)}`} onClick={() => go('appearance')} chevron />
          <Row icon="volume" iconColor="#2fc473" title="Sounds" sub={`${cap(s.ringtone)} ringtone`} onClick={() => go('sounds')} chevron />
          <Row icon="block" iconColor="#6f7585" title="Blocked numbers" onClick={() => go('blocked')} chevron />
        </Group>
        <Group footer="Hides your own number on this screen, for streaming. Other people still see it when you call or message.">
          <Row icon="eye" iconColor="#d98a45" title="Streamer mode" right={<Toggle on={s.streamer} onChange={(v) => set({ streamer: v })} label="Streamer mode" />} />
        </Group>
        <Group title="About">
          <Row title="Number" right={<span className="ph-sub">{s.streamer ? '•••-••••' : hello?.display}</span>} />
          <Row title="Voice calls" right={<span className="ph-sub">{hello?.voice.available ? hello.voice.provider ?? 'Available' : 'Unavailable'}</span>} />
        </Group>
      </div>
    </div>
  );
}

const SIZES: { id: string; label: string; value: number }[] = [{ id: 's', label: 'Small', value: 80 }, { id: 'm', label: 'Default', value: 100 }, { id: 'l', label: 'Large', value: 120 }];

function Appearance({ onBack }: { onBack: () => void }) {
  const s = useStore((st) => st.settings);
  const [size, setSize] = useState(s.size);
  const applySize = (v: number) => { setSize(v); void updateSettings({ size: v }); };
  const preset = SIZES.find((p) => p.value === size)?.id ?? '';
  const presets = useStore((st) => st.hello?.presets) ?? FALLBACK;
  return (
    <div className="ph-app">
      <Header title="Appearance" onBack={onBack} backLabel="Settings" />
      <div className="ph-scroll ph-pad">
        <Group title="Theme">
          <div className="ph-group-pad"><Segmented options={presets.themes.map((t) => ({ id: t, label: cap(t), icon: t === 'dark' ? 'moon' : 'sun' }))} value={s.theme} onChange={(theme) => void updateSettings({ theme: theme as Settings['theme'] })} /></div>
        </Group>
        <Group title="Wallpaper">
          <div className="ph-wps">
            {presets.wallpapers.map((w) => (
              <button key={w} className={cx('ph-wpthumb', `wp-${w}`, s.wallpaper === w && 'on')} onClick={() => void updateSettings({ wallpaper: w })} aria-label={cap(w)} aria-pressed={s.wallpaper === w}>
                <i /><span>{cap(w)}</span>
              </button>
            ))}
          </div>
        </Group>
        <Group title="Accent colour">
          <div className="ph-swatches">
            {presets.accents.map((a) => (
              <button key={a} className={cx('ph-swatch', s.accent === a && 'on')} style={{ background: a }} onClick={() => void updateSettings({ accent: a })} aria-label={`Accent ${a}`} aria-pressed={s.accent === a}>{s.accent === a && <Ico name="check" size={16} stroke={3} />}</button>
            ))}
          </div>
        </Group>
        <Group title="Phone case">
          <div className="ph-swatches">
            {presets.cases.map((c) => (
              <button key={c} className={cx('ph-swatch', s.case === c && 'on')} style={{ background: CASE_COLOR[c] ?? '#222' }} onClick={() => void updateSettings({ case: c })} aria-label={cap(c)} aria-pressed={s.case === c}>{s.case === c && <Ico name="check" size={16} stroke={3} />}</button>
            ))}
          </div>
        </Group>
        <Group title="Phone size" footer="Makes the whole phone bigger or smaller on your screen. It always fits your screen.">
          <div className="ph-group-pad"><Segmented options={SIZES.map((p) => ({ id: p.id, label: p.label }))} value={preset} onChange={(id) => applySize(SIZES.find((p) => p.id === id)!.value)} /></div>
          <div className="ph-group-pad ph-slide">
            <Ico name="minus" size={16} /><Slider label="Phone size" value={size} min={60} max={140} onChange={setSize} onCommit={applySize} /><Ico name="plus" size={16} />
            <span className="ph-size-val">{size}%</span>
          </div>
        </Group>
        <Group title="Brightness">
          <div className="ph-group-pad ph-slide"><Ico name="sun" size={16} /><Slider label="Brightness" value={s.brightness} min={20} onChange={(v) => setState((st) => ({ settings: { ...st.settings, brightness: v } }))} onCommit={(v) => void updateSettings({ brightness: v })} /></div>
        </Group>
      </div>
    </div>
  );
}

function Sounds({ onBack }: { onBack: () => void }) {
  const s = useStore((st) => st.settings);
  const presets = useStore((st) => st.hello?.presets) ?? FALLBACK;
  const pickRing = (r: string) => { startRing({ ...s, ringtone: r }, true); void updateSettings({ ringtone: r }); };
  const pickNotify = (n: string) => { playNotify({ ...s, notifySound: n, silent: false, dnd: false }); void updateSettings({ notifySound: n }); };
  return (
    <div className="ph-app">
      <Header title="Sounds" onBack={onBack} backLabel="Settings" />
      <div className="ph-scroll ph-pad">
        <Group title="Volume">
          <div className="ph-group-pad ph-slide"><Ico name="mute" size={16} /><Slider label="Volume" value={s.volume} onChange={(v) => setState((st) => ({ settings: { ...st.settings, volume: v } }))} onCommit={(v) => void updateSettings({ volume: v })} /><Ico name="volume" size={16} /></div>
        </Group>
        <Group title="Ringtone">
          {presets.ringtones.map((r) => <Row key={r} title={cap(r)} onClick={() => pickRing(r)} right={s.ringtone === r ? <Ico name="check" size={18} style={{ color: 'var(--ph-accent)' }} /> : undefined} />)}
        </Group>
        <Group title="Notification sound">
          {presets.notifySounds.map((n) => <Row key={n} title={n === 'none' ? 'None' : cap(n)} onClick={() => pickNotify(n)} right={s.notifySound === n ? <Ico name="check" size={18} style={{ color: 'var(--ph-accent)' }} /> : undefined} />)}
        </Group>
      </div>
    </div>
  );
}

function Blocked({ onBack }: { onBack: () => void }) {
  const [list, setList] = useState<{ number: string; display: string }[] | null>(null);
  const [num, setNum] = useState('');
  const load = async () => { const r = await api<{ number: string; display: string }[]>('blocks'); setList(r.ok ? r.data ?? [] : []); };
  useEffect(() => { void load(); }, []);
  const unblock = async (n: string) => { if (say(await api('block', n, false))) { toast('Unblocked'); void load(); } };
  const add = async () => { if (say(await api('block', num, true))) { setNum(''); void load(); } };
  return (
    <div className="ph-app">
      <Header title="Blocked" onBack={onBack} backLabel="Settings" />
      <div className="ph-scroll ph-pad">
        <Group title="Block a number">
          <div className="ph-group-pad ph-inline">
            <TextInput value={num} onChange={(v) => setNum(v.replace(/[^\d-]/g, '').slice(0, 8))} placeholder="555-1234" inputMode="tel" onEnter={add} />
            <Button kind="primary" onClick={add} disabled={num.replace(/\D/g, '').length !== 7}>Block</Button>
          </div>
        </Group>
        {list === null && <Spinner />}
        {list?.length === 0 && <Empty icon="block" title="Nobody is blocked" text="Blocked numbers cannot call you and their messages are not delivered." />}
        {!!list?.length && <Group title="Blocked">{list.map((b) => <Row key={b.number} title={b.display} right={<button className="ph-link" onClick={() => unblock(b.number)}>Unblock</button>} />)}</Group>}
      </div>
    </div>
  );
}

function Profile({ onBack }: { onBack: () => void }) {
  const hello = useStore((s) => s.hello);
  const [name, setName] = useState(hello?.name ?? '');
  const [busy, setBusy] = useState(false);
  const save = async () => {
    setBusy(true);
    const r = await api<{ name: string }>('profileSave', name);
    setBusy(false);
    if (say(r) && r.data && hello) setState({ hello: { ...hello, name: r.data.name } });
  };
  return (
    <div className="ph-app">
      <Header title="Profile" onBack={onBack} backLabel="Settings" />
      <div className="ph-scroll ph-pad">
        <div className="ph-info-head"><Avatar name={name} id={hello?.number} size={84} /><span className="ph-sub">{hello?.display}</span></div>
        <Group title="Display name" footer="Shown to people you message or call who have not saved you.">
          <div className="ph-group-pad ph-inline">
            <TextInput value={name} onChange={setName} maxLength={hello?.limits.name ? 48 : 48} onEnter={save} />
            <Button kind="primary" onClick={save} disabled={busy || name.trim().length < 2 || name === hello?.name}>Save</Button>
          </div>
        </Group>
      </div>
    </div>
  );
}
