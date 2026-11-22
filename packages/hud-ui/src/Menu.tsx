import { useEffect, useState, type ReactNode } from 'react';
import { Icon, nui } from '@veyl/ui';
import type { Caps, Settings, VehicleMode } from './types';

type Tab = 'overview' | 'player' | 'minimap' | 'vehicle' | 'appearance';
const TABS: { id: Tab; label: string; icon: string }[] = [
  { id: 'overview', label: 'Overview', icon: 'home' }, { id: 'player', label: 'Player', icon: 'user' },
  { id: 'minimap', label: 'Minimap', icon: 'pin' }, { id: 'vehicle', label: 'Vehicle', icon: 'car' },
  { id: 'appearance', label: 'Appearance', icon: 'sparkle' },
];

/** Deep-set a value by path ("player.health") on a copy. */
function set<T>(obj: T, path: string, value: unknown): T {
  const out = JSON.parse(JSON.stringify(obj));
  const keys = path.split('.');
  let cur = out;
  for (let i = 0; i < keys.length - 1; i++) cur = cur[keys[i]];
  cur[keys[keys.length - 1]] = value;
  return out;
}

export function Menu({ draft, saved, defaults, caps, onChange, onEdit }: {
  draft: Settings; saved: Settings; defaults: Settings; caps: Caps; onChange: (s: Settings) => void; onEdit: () => void;
}) {
  const [tab, setTab] = useState<Tab>('overview');
  const [busy, setBusy] = useState(false);
  const up = (path: string, value: unknown) => onChange(set(draft, path, value));
  const cancel = () => { void nui('menu:cancel'); };
  const save = async () => { setBusy(true); await nui('menu:save', { settings: draft }); setBusy(false); };
  const reset = () => onChange(JSON.parse(JSON.stringify(defaults)));

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.preventDefault(); cancel(); } };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const dirty = JSON.stringify(draft) !== JSON.stringify(saved);
  const T = (label: string, path: string, value: boolean, extra?: ReactNode) => <Toggle label={label} value={value} onChange={(v) => up(path, v)} extra={extra} />;

  return (
    <div className="menu-wrap" role="dialog" aria-label="HUD settings">
      <div className="menu">
        <header className="menu-head">
          <h1><i>/</i> HUD SETTINGS</h1>
          <button className="x" aria-label="Close" onClick={cancel}><Icon name="close" size="1.1rem" /></button>
        </header>
        <div className="menu-body">
          <nav className="side" aria-label="Sections">
            {TABS.map((t) => (
              <button key={t.id} className={tab === t.id ? 'on' : ''} aria-current={tab === t.id} onClick={() => setTab(t.id)}>
                <Icon name={t.icon} size="1.1rem" />{t.label}
              </button>
            ))}
          </nav>
          <main className="panes">
            {tab === 'overview' && (
              <>
                <Pane title="Display" icon="gear">
                  {T('Enable HUD', 'enabled', draft.enabled)}
                  <Slider label="HUD scale" value={draft.scale} min={0.7} max={1.5} step={0.05} fmt={(v) => `${Math.round(v * 100)}%`} onChange={(v) => up('scale', v)} />
                  <Slider label="Background opacity" value={draft.opacity} min={0.2} max={1} step={0.01} fmt={(v) => `${Math.round(v * 100)}%`} onChange={(v) => up('opacity', v)} />
                  {T('Show percentages', 'showPercent', draft.showPercent)}
                </Pane>
                <Pane title="Layout" icon="hand">
                  <button className="wide" onClick={onEdit}><Icon name="hand" size="1rem" /> Edit HUD positions</button>
                  <p className="hint">Drag the minimap, status, voice, vehicle, top-right and location groups. Positions are saved for your screen shape.</p>
                </Pane>
              </>
            )}
            {tab === 'player' && (
              <>
                <Pane title="Status bars" icon="heart">
                  {(['health', 'armor', 'hunger', 'thirst', 'stress', 'stamina', 'oxygen', 'voice'] as const).map((k) => T(cap(k), `player.${k}`, draft.player[k]))}
                  {T('Hide full / inactive bars', 'player.hideFull', draft.player.hideFull)}
                  <Seg label="Layout" value={draft.player.layout} options={[['list', 'Bars'], ['compact', 'Icons']]} onChange={(v) => up('player.layout', v)} />
                </Pane>
                <Pane title="Information" icon="card">
                  {(['cash', 'bank', 'playerId', 'clock', 'location'] as const).map((k) => T(k === 'playerId' ? 'Brand and player ID' : cap(k), `player.${k}`, draft.player[k]))}
                  {caps.postal ? T('Postal', 'player.postal', draft.player.postal) : <Unavailable label="Postal" why="No postal dataset on this server" />}
                </Pane>
                <Pane title="Warning thresholds" icon="alert">
                  {(['health', 'armor', 'hunger', 'thirst', 'stamina', 'oxygen'] as const).map((k) => (
                    <Slider key={k} label={`${cap(k)} below`} value={draft.thresholds[k]} min={0} max={100} step={1} fmt={(v) => `${v}%`} onChange={(v) => up(`thresholds.${k}`, v)} />
                  ))}
                  <Slider label="Stress above" value={draft.thresholds.stress} min={0} max={100} step={1} fmt={(v) => `${v}%`} onChange={(v) => up('thresholds.stress', v)} />
                </Pane>
              </>
            )}
            {tab === 'minimap' && (
              <>
                <Pane title="Minimap" icon="pin">
                  <Seg label="Map shape" value={draft.minimap.shape} options={[['square', 'Square'], ['circle', 'Circle']]}
                    disabled={caps.circle ? [] : ['circle']} onChange={(v) => up('minimap.shape', v)} />
                  {draft.minimap.shape === 'circle' && <p className="hint">Circle uses GTA's round clip. A round mask texture (docs/HUD.md) gives a cleaner edge.</p>}
                  <Seg label="Show the map" value={draft.minimap.mode} options={[['always', 'Always'], ['vehicle', 'In vehicles'], ['never', 'Never']]} onChange={(v) => up('minimap.mode', v)} />
                  {T('North up (do not rotate)', 'minimap.northUp', draft.minimap.northUp)}
                  <Slider label="Map size" value={draft.minimap.scale} min={0.75} max={1.4} step={0.05} fmt={(v) => `${Math.round(v * 100)}%`} onChange={(v) => up('minimap.scale', v)} />
                  <button className="wide" onClick={onEdit}><Icon name="hand" size="1rem" /> Move the map</button>
                </Pane>
                <Pane title="Location strip" icon="pin">
                  {T('Street name', 'minimap.street', draft.minimap.street)}
                  {T('Direction', 'minimap.direction', draft.minimap.direction)}
                  {caps.postal ? T('Postal', 'minimap.postal', draft.minimap.postal) : <Unavailable label="Postal" why="No postal dataset" />}
                </Pane>
              </>
            )}
            {tab === 'vehicle' && (
              <>
                <Pane title="Vehicle modes" icon="car">
                  {T('Auto-detect vehicle type', 'vehicle.auto', draft.vehicle.auto)}
                  {(['car', 'motorcycle', 'heli', 'boat', 'bicycle'] as VehicleMode[]).map((m) =>
                    T({ car: 'Cars', motorcycle: 'Motorcycles', heli: 'Helicopters', boat: 'Boats', bicycle: 'BMX and bicycles' }[m], `vehicle.modes.${m}`, draft.vehicle.modes[m]))}
                </Pane>
                <Pane title="Units" icon="gear">
                  <Seg label="Road" value={draft.vehicle.roadUnit} options={[['MPH', 'MPH'], ['KMH', 'KMH']]} onChange={(v) => up('vehicle.roadUnit', v)} />
                  <Seg label="Air and sea" value={draft.vehicle.airSeaUnit} options={[['KTS', 'KTS'], ['MPH', 'MPH'], ['KMH', 'KMH']]} onChange={(v) => up('vehicle.airSeaUnit', v)} />
                  <Seg label="Altitude" value={draft.vehicle.altUnit} options={[['FT', 'FT'], ['M', 'M']]} onChange={(v) => up('vehicle.altUnit', v)} />
                  <Seg label="Altitude from" value={draft.vehicle.altMode} options={[['AGL', 'Ground (AGL)'], ['MSL', 'Sea level']]} onChange={(v) => up('vehicle.altMode', v)} />
                  <Seg label="Vertical speed" value={draft.vehicle.vsUnit} options={[['FPM', 'ft/min'], ['MS', 'm/s']]} onChange={(v) => up('vehicle.vsUnit', v)} />
                </Pane>
                <Pane title="Instruments" icon="bolt">
                  {caps.fuel !== 'none' ? T('Fuel', 'vehicle.fuel', draft.vehicle.fuel) : <Unavailable label="Fuel" why="No fuel provider" />}
                  {T('Engine warnings', 'vehicle.engine', draft.vehicle.engine)}
                  {T('RPM', 'vehicle.rpm', draft.vehicle.rpm)}
                  {T('Gear', 'vehicle.gear', draft.vehicle.gear)}
                  {T('Bicycle stamina', 'vehicle.bikeStamina', draft.vehicle.bikeStamina)}
                  {caps.seatbelt ? <>{T('Seatbelt indicator', 'vehicle.seatbelt', draft.vehicle.seatbelt)}{T('Seatbelt alert', 'vehicle.seatbeltAlert', draft.vehicle.seatbeltAlert)}</>
                    : <Unavailable label="Seatbelt" why="No seatbelt provider" />}
                </Pane>
              </>
            )}
            {tab === 'appearance' && (
              <>
                <Pane title="Colors" icon="sparkle">
                  <Color label="Primary" value={draft.colors.primary} onChange={(v) => up('colors.primary', v)} />
                  <Color label="Secondary" value={draft.colors.secondary} onChange={(v) => up('colors.secondary', v)} />
                  <Color label="Text" value={draft.colors.text} onChange={(v) => up('colors.text', v)} />
                  <button className="wide" onClick={() => onChange({ ...draft, colors: { ...defaults.colors } })}>Mint and pink preset</button>
                </Pane>
                <Pane title="Look" icon="eye">
                  <Slider label="Background opacity" value={draft.opacity} min={0.2} max={1} step={0.01} fmt={(v) => `${Math.round(v * 100)}%`} onChange={(v) => up('opacity', v)} />
                  <Slider label="Border opacity" value={draft.borderOpacity} min={0} max={1} step={0.01} fmt={(v) => `${Math.round(v * 100)}%`} onChange={(v) => up('borderOpacity', v)} />
                  <Slider label="HUD scale" value={draft.scale} min={0.7} max={1.5} step={0.05} fmt={(v) => `${Math.round(v * 100)}%`} onChange={(v) => up('scale', v)} />
                  {T('Reduced motion', 'reducedMotion', draft.reducedMotion)}
                </Pane>
              </>
            )}
          </main>
        </div>
        <footer className="menu-foot">
          <button className="ghost" onClick={reset}><Icon name="reset" size="1rem" /> Reset defaults</button>
          <span className="spacer">{dirty ? 'Unsaved changes (previewing)' : ''}</span>
          <button className="ghost" onClick={cancel}>Cancel</button>
          <button className="primary" disabled={busy} onClick={() => void save()}>Save changes</button>
        </footer>
      </div>
    </div>
  );
}

const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

function Pane({ title, icon, children }: { title: string; icon: string; children: ReactNode }) {
  return <section className="pane"><h2><Icon name={icon} size="1.1rem" />{title}</h2>{children}</section>;
}

function Toggle({ label, value, onChange, extra }: { label: string; value: boolean; onChange: (v: boolean) => void; extra?: ReactNode }) {
  return (
    <label className="row">
      <span>{label}</span>{extra}
      <button role="switch" aria-checked={value} className={`sw${value ? ' on' : ''}`} onClick={(e) => { e.preventDefault(); onChange(!value); }}><i /></button>
    </label>
  );
}

function Unavailable({ label, why }: { label: string; why: string }) {
  return <div className="row off"><span>{label}</span><em>{why}</em></div>;
}

function Slider({ label, value, min, max, step, fmt, onChange }: { label: string; value: number; min: number; max: number; step: number; fmt: (v: number) => string; onChange: (v: number) => void }) {
  return (
    <label className="row">
      <span>{label}</span>
      <input type="range" min={min} max={max} step={step} value={value} onChange={(e) => onChange(Number(e.target.value))} />
      <b className="val">{fmt(value)}</b>
    </label>
  );
}

function Seg<T extends string>({ label, value, options, onChange, disabled = [] }: { label: string; value: T; options: [T, string][]; onChange: (v: T) => void; disabled?: T[] }) {
  return (
    <div className="row">
      <span>{label}</span>
      <div className="seg" role="radiogroup" aria-label={label}>
        {options.map(([v, l]) => (
          <button key={v} role="radio" aria-checked={value === v} className={value === v ? 'on' : ''} disabled={disabled.includes(v)} onClick={() => onChange(v)}>{l}</button>
        ))}
      </div>
    </div>
  );
}

function Color({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  return (
    <label className="row">
      <span>{label}</span>
      <span className="color"><input type="color" value={value} onChange={(e) => onChange(e.target.value.toUpperCase())} /><code>{value}</code></span>
    </label>
  );
}
