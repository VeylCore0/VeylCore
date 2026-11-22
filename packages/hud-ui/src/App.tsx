import { useCallback, useEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { Icon, VMark, announceReady, nui, useNuiMessage } from '@veyl/ui';
import type { Caps, Frame, GroupKey, Layout, Settings, Status, Vehicle, Voice } from './types';
import { Menu } from './Menu';
import { Editor } from './Editor';

/** Lua sends partial frames; each section replaces only itself. */
function merge(prev: Frame, next: Partial<Frame>): Frame { return { ...prev, ...next }; }

const hex = (h: string, a: number) => {
  const n = parseInt(h.slice(1), 16);
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${a})`;
};

export function themeVars(s: Settings): CSSProperties {
  return {
    ['--mint' as string]: s.colors.primary, ['--pink' as string]: s.colors.secondary, ['--ink' as string]: s.colors.text,
    ['--mint-soft' as string]: hex(s.colors.primary, 0.18), ['--pink-soft' as string]: hex(s.colors.secondary, 0.2),
    ['--panel' as string]: `rgba(21, 29, 34, ${s.opacity})`, ['--line' as string]: `rgba(165, 243, 208, ${s.borderOpacity})`,
    ['--hud-scale' as string]: String(s.scale),
  };
}

export function App() {
  const [frame, setFrame] = useState<Frame>({ visible: false });
  const [settings, setSettings] = useState<Settings | null>(null);
  const [caps, setCaps] = useState<Caps | null>(null);
  const [menu, setMenu] = useState<{ saved: Settings; defaults: Settings } | null>(null);
  const [editing, setEditing] = useState(false);
  const [editBase, setEditBase] = useState<Settings | null>(null);
  useEffect(() => announceReady(), []);

  useNuiMessage<Partial<Frame>>('hud:frame', (d) => setFrame((f) => merge(f, d)));
  useNuiMessage('hud:reset', () => setFrame({ visible: false }));
  useNuiMessage<{ settings: Settings; caps: Caps }>('hud:settings', (d) => { setSettings(d.settings); setCaps(d.caps); });
  useNuiMessage<{ open: boolean; settings?: Settings; defaults?: Settings; caps?: Caps }>('hud:menu', (d) => {
    if (d.open && d.settings && d.defaults) { setMenu({ saved: d.settings, defaults: d.defaults }); setSettings(d.settings); if (d.caps) setCaps(d.caps); }
    else { setMenu(null); setEditing(false); }
  });

  // Live preview: the draft is drawn at once; Lua cleans it, moves the native minimap and returns the new layout.
  // Throttled, not debounced: one request in flight, always sending the newest draft, so the native map follows a drag.
  const pending = useRef<{ draft: Settings; moving: boolean } | null>(null);
  const busy = useRef(false);
  const flush = useCallback(async () => {
    if (busy.current || !pending.current) return;
    const { draft, moving } = pending.current;
    pending.current = null;
    busy.current = true;
    const r = await nui<{ settings: Settings; layout: Layout }>('menu:preview', { settings: draft, moving });
    busy.current = false;
    if (r.ok && r.data) setFrame((f) => ({ ...f, layout: { ...(f.layout ?? r.data!.layout), ...r.data!.layout } }));
    if (pending.current) void flush();
  }, []);
  const preview = useCallback((draft: Settings, moving = false) => {
    setSettings(draft);
    pending.current = { draft, moving };
    void flush();
  }, [flush]);

  if (!settings) return null;
  const show = frame.visible || !!menu;
  return (
    <div className={`hud${settings.reducedMotion ? ' still' : ''}`} style={themeVars(settings)}>
      {show && settings.enabled && <Hud frame={frame} s={settings} caps={caps} editing={editing} />}
      {menu && !editing && caps && (
        <Menu draft={settings} saved={menu.saved} defaults={menu.defaults} caps={caps} onChange={preview}
          onEdit={() => { setEditBase(settings); setEditing(true); }} />
      )}
      {menu && editing && frame.layout && editBase && (
        <Editor s={settings} layout={frame.layout} onPreview={preview}
          onDone={(next) => { preview(next ?? editBase); setEditing(false); setEditBase(null); }} />
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// HUD
// ---------------------------------------------------------------------------
const vw = (f: number) => `${f * 100}vw`;
const vh = (f: number) => `${f * 100}vh`;

/** Where a group sits: the saved editor position, or its default anchor. */
export function place(s: Settings, key: GroupKey, fallback: CSSProperties): CSSProperties {
  const p = s.positions[key];
  return p ? { left: vw(p.x), top: vh(p.y) } : fallback;
}

export function defaults(l: Layout | undefined): Record<GroupKey, CSSProperties> {
  const left = l ? l.left : 0.012, bottom = l ? l.bottom : 0.04, width = l ? l.width : 0.14, height = l ? l.height : 0.17;
  const safe = l ? l.safe : 0.0;
  return {
    location: { left: vw(left), bottom: `calc(${vh(bottom + height)} + 0.6rem)` },
    status: { left: `calc(${vw(left + width)} + 0.7rem)`, bottom: `calc(${vh(bottom)} + 2.3rem)` },
    voice: { left: `calc(${vw(left + width)} + 0.7rem)`, bottom: vh(bottom) },
    info: { right: `calc(${vw(safe)} + 1.2rem)`, top: `calc(${vh(safe)} + 1.2rem)` },
    vehicle: { right: `calc(${vw(safe)} + 1.6rem)`, bottom: `calc(${vh(safe)} + 1.6rem)` },
  };
}

/** The layout Lua returned, moved by any minimap offset change it has not answered yet (keeps the frame on the cursor). */
function liveLayout(l: Layout | undefined, s: Settings): Layout | undefined {
  if (!l || l.ox === undefined || l.oy === undefined) return l;
  const xk = (16 / 9) / (window.innerWidth / window.innerHeight);
  return { ...l, left: l.left + (s.minimap.offsetX - l.ox) * xk, bottom: l.bottom + (s.minimap.offsetY - l.oy) };
}

function Hud({ frame, s, caps, editing }: { frame: Frame; s: Settings; caps: Caps | null; editing: boolean }) {
  const l = liveLayout(frame.layout, s);
  const d = defaults(l);
  const p = s.player;
  const veh = frame.vehicle || null;
  return (
    <div className={`hud-root${editing ? ' editing' : ''}`}>
      {l && l.shown && (
        <div className={`mm-frame ${l.shape}`} style={{ left: vw(l.left), bottom: vh(l.bottom), width: vw(l.width), height: vh(l.height) }} />
      )}
      {p.location && frame.location && (s.minimap.street || s.minimap.direction || s.minimap.postal) && (
        <div className="g location" data-group="location" style={place(s, 'location', d.location)}>
          {s.minimap.direction && <span className="dir"><Icon name="pin" size="0.85em" /> {frame.location.dir}</span>}
          {s.minimap.street && <span className="street">{frame.location.street}{frame.location.cross ? ` / ${frame.location.cross}` : ''}</span>}
          {s.minimap.postal && p.postal && caps?.postal && frame.location.postal && <span className="postal">Postal {frame.location.postal}</span>}
        </div>
      )}
      {frame.status && <StatusGroup st={frame.status} s={s} style={place(s, 'status', d.status)} />}
      {p.voice && frame.voice && <VoiceChip v={frame.voice} style={place(s, 'voice', d.voice)} />}
      {frame.info && (p.playerId || p.cash || p.bank || p.clock) && (
        <div className="g info" data-group="info" style={place(s, 'info', d.info)}>
          {p.playerId && <div className="brand"><VMark size="1.05em" /><b>VEYLCORE</b><i>/</i><span>ID {frame.info.id}</span></div>}
          {p.cash && frame.info.cash != null && <div className="pill"><Icon name="money" size="0.95em" /><span>Cash</span><b>{usd(frame.info.cash)}</b></div>}
          {p.bank && frame.info.bank != null && <div className="pill"><Icon name="bank" size="0.95em" /><span>Bank</span><b>{usd(frame.info.bank)}</b></div>}
          {p.clock && <div className="pill small"><Icon name="clock" size="0.95em" /><b>{frame.info.time}</b></div>}
        </div>
      )}
      {veh && <VehicleGroup v={veh} s={s} style={place(s, 'vehicle', d.vehicle)} />}
    </div>
  );
}

const usd = (n: number) => `${n < 0 ? '-' : ''}$${Math.abs(n).toLocaleString('en-US')}`;

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------
const STATS: { key: keyof Status; icon: string; label: string; high?: boolean }[] = [
  { key: 'health', icon: 'heart', label: 'Health' }, { key: 'armor', icon: 'shield', label: 'Armor' },
  { key: 'hunger', icon: 'burger', label: 'Hunger' }, { key: 'thirst', icon: 'drop', label: 'Thirst' },
  { key: 'stress', icon: 'brain', label: 'Stress', high: true }, { key: 'stamina', icon: 'bolt', label: 'Stamina' },
  { key: 'oxygen', icon: 'lungs', label: 'Oxygen' },
];

function StatusGroup({ st, s, style }: { st: Status; s: Settings; style: CSSProperties }) {
  const rows = STATS.filter(({ key }) => {
    const v = st[key];
    if (v === undefined || v === null || !s.player[key as keyof Settings['player']]) return false;
    if (key === 'oxygen') return true;                       // only sent while underwater
    if (s.player.hideFull) {
      if (key === 'stress') return v > 0;
      if (key === 'armor') return v > 0;
      return v < 100;
    }
    return key !== 'armor' || v > 0 || !s.player.hideFull;
  });
  if (rows.length === 0) return null;
  const compact = s.player.layout === 'compact';
  return (
    <div className={`g status ${compact ? 'compact' : 'list'}`} data-group="status" style={style}>
      {rows.map(({ key, icon, label, high }) => {
        const v = Math.round(st[key] as number);
        const t = s.thresholds[key as keyof Settings['thresholds']];
        const warn = high ? v >= t : v <= t;
        return compact ? (
          <div key={key} className={`ring${warn ? ' warn' : ''}`} style={{ ['--v' as string]: v }} aria-label={`${label} ${v}%`}>
            <Icon name={icon} size="0.95em" />
            {s.showPercent && <small>{v}</small>}
          </div>
        ) : (
          <div key={key} className={`bar ${key}${warn ? ' warn' : ''}`} aria-label={`${label} ${v}%`}>
            <Icon name={icon} size="0.95em" />
            <span className="lbl">{label}</span>
            <span className="track"><span style={{ width: `${v}%` }} /></span>
            {s.showPercent && <span className="pct">{v}%</span>}
          </div>
        );
      })}
    </div>
  );
}

function VoiceChip({ v, style }: { v: Voice; style: CSSProperties }) {
  return (
    <div className={`g voice${v.talking ? ' talking' : ''}${v.radio ? ' radio' : ''}`} data-group="voice" style={style}>
      <Icon name={v.radio ? 'bell' : 'mic'} size="0.95em" />
      <span>{v.radio ? 'Radio' : 'Voice'}:</span>
      <b>{v.available ? (v.mode ?? '—') : (v.talking ? 'Talking' : 'Ready')}</b>
      {v.available && <span className="lvl">{[1, 2, 3].map((i) => <i key={i} className={(v.level ?? 0) >= i ? 'on' : ''} />)}</span>}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Vehicle instruments: one layout at a time
// ---------------------------------------------------------------------------
const SCALE_MAX: Record<string, number> = { bicycle: 40, boat: 60, heli: 160 };

function Arc({ value, redline }: { value: number; redline: number }) {
  // 240° gauge. Track, mint fill, and a pink segment past the redline.
  const r = 46, c = 2 * Math.PI * r, sweep = (240 / 360) * c;
  const v = Math.max(0, Math.min(1, value));
  const red = Math.max(0, v - redline);
  return (
    <svg className="arc" viewBox="0 0 120 120" aria-hidden="true">
      <circle cx="60" cy="60" r={r} className="track" strokeDasharray={`${sweep} ${c}`} transform="rotate(150 60 60)" />
      <circle cx="60" cy="60" r={r} className="fill" strokeDasharray={`${Math.min(v, redline) * sweep} ${c}`} transform="rotate(150 60 60)" />
      {red > 0 && <circle cx="60" cy="60" r={r} className="red" strokeDasharray={`${red * sweep} ${c}`} transform={`rotate(${150 + redline * 240} 60 60)`} />}
      <circle cx="60" cy="60" r={r} className="redzone" strokeDasharray={`${(1 - redline) * sweep} ${c}`} transform={`rotate(${150 + redline * 240} 60 60)`} />
    </svg>
  );
}

function ModeIcon({ mode }: { mode: string }) {
  const paths: Record<string, ReactNode> = {
    bicycle: <><circle cx="6" cy="16" r="4" /><circle cx="18" cy="16" r="4" /><path d="M6 16l4-8h5l3 8M10 8l2 8h-6M14 5h3" /></>,
    motorcycle: <><circle cx="5" cy="16" r="3.5" /><circle cx="19" cy="16" r="3.5" /><path d="M5 16h6l3-5h5M14 11l-2-4h-3M17 11l2 5" /></>,
    boat: <><path d="M3 15h18l-3 4H6zM6 15V9h8l3 6M9 9V5" /></>,
    heli: <><path d="M3 5h18M12 5v3M6 11h9a4 4 0 0 1 0 8H9a3 3 0 0 1-3-3zM15 19v2M9 19v2M2 13h4" /></>,
    car: <><path d="M4 16v-3l2-5h12l2 5v3zM4 16v2h3v-2M17 16v2h3v-2M7 13h.01M17 13h.01" /></>,
  };
  return <svg className="mode-ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">{paths[mode] ?? paths.car}</svg>;
}

function VehicleGroup({ v, s, style }: { v: Vehicle; s: Settings; style: CSSProperties }) {
  const hasRpm = v.rpm !== undefined;
  const arcValue = hasRpm ? (v.rpm as number) : Math.min(1, v.speed / (SCALE_MAX[v.mode] ?? 140));
  return (
    <div className={`g vehicle ${v.mode}${v.engine === 'off' ? ' off' : ''}`} data-group="vehicle" style={style}>
      <div className="gauge">
        <Arc value={arcValue} redline={hasRpm ? 0.82 : 0.85} />
        <div className="readout">
          {v.mode === 'bicycle' && <ModeIcon mode="bicycle" />}
          {hasRpm && <span className="rpm-lbl">RPM</span>}
          <span className="speed">{String(Math.max(0, v.speed)).padStart(3, '0')}</span>
          <span className="unit">{v.unit}</span>
          {v.gear !== undefined && <span className="gear">{v.gear}</span>}
        </div>
      </div>
      {v.mode === 'heli' && (
        <div className="panel">
          <span>GS <b>{v.speed}</b> {v.unit}</span>
          <span>{v.altMode === 'AGL' ? 'AGL' : 'ALT'} <b>{v.alt}</b> {v.altUnit === 'FT' ? 'ft' : 'm'}</span>
          <span>HDG <b>{String(v.heading ?? 0).padStart(3, '0')}°</b></span>
          <span>V/S <b>{(v.vs ?? 0) > 0 ? '+' : ''}{v.vs}</b> {v.vsUnit}</span>
        </div>
      )}
      {v.mode === 'boat' && <div className="panel one"><span>HDG <b>{String(v.heading ?? 0).padStart(3, '0')}°</b></span></div>}
      {v.mode === 'bicycle' && v.stamina !== undefined && (
        <div className="row"><span className="lbl">Stamina</span><span className="track"><span style={{ width: `${v.stamina}%` }} /></span>{s.showPercent && <span className="pct">{v.stamina}%</span>}</div>
      )}
      {v.mode !== 'bicycle' && (
        <div className="chips">
          {v.fuel !== undefined && (
            <span className={`chip fuel${v.fuel <= 15 ? ' warn' : ''}`}><Icon name="fuel" size="0.95em" /><span className="track"><span style={{ width: `${v.fuel}%` }} /></span>{v.fuel}%</span>
          )}
          {v.seatbelt && (
            <span className={`chip belt ${v.seatbelt}${v.beltAlert ? ' alert' : ''}`}><Icon name="seatbelt" size="0.95em" />Seatbelt: {v.seatbelt === 'on' ? 'ON' : 'OFF'}</span>
          )}
          {v.engine && <span className={`chip engine ${v.engine}`}><Icon name="engine" size="0.95em" />{v.engine === 'off' ? 'Engine off' : v.engine === 'critical' ? 'Engine failing' : 'Check engine'}</span>}
        </div>
      )}
    </div>
  );
}
