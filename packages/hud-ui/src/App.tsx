import { useEffect, useState } from 'react';
import { Icon, VMark, announceReady, money, useNuiMessage, type HudFrame, type HudSettings } from '@veyl/ui';

const DEFAULT_SETTINGS: HudSettings = { scale: 1, showMoney: true, showCompass: true, showStatus: true, showVehicle: true, showBrand: true, unit: 'MPH' };

/** Lua sends partial frames; each section replaces only itself, so unchanged values are never re-sent. */
function merge(prev: HudFrame, next: Partial<HudFrame>): HudFrame {
  const out = { ...prev };
  for (const k of Object.keys(next) as (keyof HudFrame)[]) (out as Record<string, unknown>)[k] = next[k];
  return out;
}

export function App() {
  const [frame, setFrame] = useState<HudFrame>({ visible: false });
  useEffect(() => announceReady(), []);
  useNuiMessage<Partial<HudFrame>>('hud:frame', (d) => setFrame((f) => merge(f, d)));
  useNuiMessage('hud:reset', () => setFrame({ visible: false }));

  if (!frame.visible) return null;
  const s = frame.settings ?? DEFAULT_SETTINGS;
  return (
    <div className="hud-root" style={{ ['--hud-scale' as string]: String(s.scale) }}>
      {s.showCompass && frame.compass && <Compass heading={frame.compass.heading} street={frame.compass.street} zone={frame.compass.zone} />}
      {(s.showBrand || s.showMoney) && frame.info && <Info info={frame.info} showMoney={s.showMoney} showBrand={s.showBrand} />}
      {frame.minimap && <div className="hud-minimap-frame" style={{ left: `${frame.minimap.left * 100}vw`, bottom: `${frame.minimap.bottom * 100}vh`, width: `${frame.minimap.width * 100}vw`, height: `${frame.minimap.height * 100}vh` }} />}
      {s.showStatus && frame.status && <Status frame={frame} />}
      {s.showVehicle && frame.vehicle && <Vehicle v={frame.vehicle} />}
    </div>
  );
}

const DIRS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

function Compass({ heading, street, zone }: { heading: number; street: string; zone?: string }) {
  // Show labels within ±100° of the current heading, positioned proportionally.
  const marks: { label: string; offset: number }[] = [];
  DIRS.forEach((label, i) => {
    let d = i * 45 - heading;
    d = ((d + 540) % 360) - 180;
    if (Math.abs(d) <= 100) marks.push({ label, offset: d });
  });
  return (
    <div className="hud-compass">
      <div className="hud-compass-strip">
        {marks.map((m) => (
          <span key={m.label} className={`hud-dir${m.label.length === 1 ? ' major' : ''}`} style={{ left: `${50 + (m.offset / 100) * 50}%`, opacity: 1 - Math.abs(m.offset) / 130 }}>{m.label}</span>
        ))}
      </div>
      <div className="hud-street">{street}{zone ? <span className="hud-zone"> · {zone}</span> : null}</div>
    </div>
  );
}

function Info({ info, showMoney, showBrand }: { info: NonNullable<HudFrame['info']>; showMoney: boolean; showBrand: boolean }) {
  return (
    <div className="hud-info">
      {showBrand && (
        <div className="hud-brand"><VMark size="1.1rem" /><span>VEYLCORE</span><span className="hud-sep" /><span>ID {info.serverId}</span></div>
      )}
      {showMoney && info.bank !== null && <div className="hud-money"><span>BANK</span><strong>{money(info.bank)}</strong></div>}
      {showMoney && info.cash !== null && <div className="hud-money"><span>CASH</span><strong>{money(info.cash)}</strong></div>}
    </div>
  );
}

function Bar({ icon, value, tone, label }: { icon: string; value: number; tone?: 'warn' | 'danger'; label: string }) {
  const v = Math.max(0, Math.min(100, value));
  return (
    <div className={`hud-stat${tone ? ` ${tone}` : ''}`} title={`${label} ${Math.round(v)}%`} aria-label={`${label} ${Math.round(v)}%`}>
      <Icon name={icon} size="1rem" />
      <span className="hud-bar"><span style={{ width: `${v}%` }} /></span>
    </div>
  );
}

function Status({ frame }: { frame: HudFrame }) {
  const st = frame.status!;
  const left = frame.minimap ? `${frame.minimap.left * 100}vw` : '1.2vw';
  const voice = frame.voice;
  const level = voice?.range ?? 0;
  return (
    <div className="hud-status" style={{ left }}>
      <Bar icon="heart" label="Health" value={st.health} tone={st.health < 25 ? 'danger' : undefined} />
      <Bar icon="shield" label="Armor" value={st.armor} />
      <Bar icon="burger" label="Hunger" value={st.hunger} tone={st.hunger < 15 ? 'warn' : undefined} />
      <Bar icon="drop" label="Thirst" value={st.thirst} tone={st.thirst < 15 ? 'warn' : undefined} />
      <Bar icon="brain" label="Stress" value={st.stress} tone={st.stress > 80 ? 'warn' : undefined} />
      {st.stamina !== undefined && st.stamina < 100 && <Bar icon="bolt" label="Stamina" value={st.stamina} />}
      {st.oxygen !== undefined && <Bar icon="lungs" label="Oxygen" value={st.oxygen} tone={st.oxygen < 25 ? 'danger' : undefined} />}
      {voice && (
        <div className={`hud-voice${voice.talking ? ' talking' : ''}${voice.available ? '' : ' unavailable'}`} title={voice.available ? 'Voice' : 'Voice range unavailable'}>
          <span className="hud-divider" />
          <Icon name="mic" size="1rem" />
          <span className="hud-signal">{[1, 2, 3, 4].map((i) => <span key={i} className={voice.available && level >= i ? 'on' : ''} style={{ height: `${0.3 + i * 0.2}rem` }} />)}</span>
        </div>
      )}
    </div>
  );
}

function Vehicle({ v }: { v: NonNullable<HudFrame['vehicle']> }) {
  return (
    <div className="hud-vehicle">
      <div className="hud-speed-row">
        <span className="hud-speed">{String(Math.max(0, Math.round(v.speed))).padStart(3, '0')}</span>
        <span className="hud-unit">{v.unit}</span>
        <span className="hud-gear">{v.gear}</span>
      </div>
      <span className="hud-rpm"><span style={{ width: `${Math.max(0, Math.min(1, v.rpm)) * 100}%` }} /></span>
      <div className="hud-veh-row">
        <span className={`hud-fuel${v.fuel !== null && v.fuel < 15 ? ' low' : ''}`}><Icon name="fuel" size="1rem" />{v.fuel === null ? '--' : `${Math.round(v.fuel)}%`}</span>
        <span className={`hud-belt ${v.seatbelt}`} title={v.seatbelt === 'unavailable' ? 'Seatbelt: no provider' : `Seatbelt ${v.seatbelt}`}>
          <Icon name="seatbelt" size="1.1rem" />
        </span>
      </div>
    </div>
  );
}
