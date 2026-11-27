// Clock: the city's time on an analogue face, a stopwatch and a timer. The stopwatch and timer keep running while you
// are in other apps (their state lives outside the component); a finished timer rings and shows a banner.
import { useEffect, useState } from 'react';
import { timerDone } from '../controller';
import { clockSuffix, clockText, pad } from '../format';
import { Ico } from '../icons';
import { useStore } from '../store';
import { Header, Segmented, cx } from '../ui';

type Tab = 'world' | 'stopwatch' | 'timer';

// ---- shared state (module level) -------------------------------------------------------------------------------------
const sw = { running: false, startedAt: 0, base: 0, laps: [] as number[] };
const tm = { total: 5 * 60, end: 0, left: 5 * 60, running: false };
let tmTimer: number | undefined;
const swElapsed = () => sw.base + (sw.running ? Date.now() - sw.startedAt : 0);

function ensureTimerLoop() {
  if (tmTimer !== undefined) return;
  tmTimer = window.setInterval(() => {
    if (!tm.running) return;
    tm.left = Math.max(0, Math.ceil((tm.end - Date.now()) / 1000));
    if (tm.left <= 0) {
      tm.running = false; tm.left = tm.total;
      window.clearInterval(tmTimer); tmTimer = undefined;
      timerDone('Your timer finished');
    }
  }, 250);
}

function useTick(ms: number) {
  const [, force] = useState(0);
  useEffect(() => { const t = window.setInterval(() => force((n) => n + 1), ms); return () => window.clearInterval(t); }, [ms]);
}

export function ClockApp() {
  const [tab, setTab] = useState<Tab>('world');
  return (
    <div className="ph-app">
      <Header title="Clock" />
      <div className="ph-pad"><Segmented options={[{ id: 'world', label: 'City' }, { id: 'stopwatch', label: 'Stopwatch' }, { id: 'timer', label: 'Timer' }]} value={tab} onChange={setTab} /></div>
      <div className="ph-scroll">
        {tab === 'world' && <City />}
        {tab === 'stopwatch' && <Stopwatch />}
        {tab === 'timer' && <TimerTab />}
      </div>
    </div>
  );
}

function City() {
  const world = useStore((s) => s.world);
  const h = world?.hour ?? 12, m = world?.minute ?? 0;
  const hourDeg = ((h % 12) + m / 60) * 30, minDeg = m * 6;
  return (
    <div className="ph-city">
      <svg viewBox="-100 -100 200 200" className="ph-analog" role="img" aria-label={`${clockText(h, m)} ${clockSuffix(h)}`}>
        <circle r="96" className="face" />
        {Array.from({ length: 60 }, (_, i) => <line key={i} x1="0" x2="0" y1={i % 5 === 0 ? -86 : -90} y2="-93" transform={`rotate(${i * 6})`} className={i % 5 === 0 ? 'tick big' : 'tick'} />)}
        <line x1="0" y1="8" x2="0" y2="-50" transform={`rotate(${hourDeg})`} className="hand hour" />
        <line x1="0" y1="10" x2="0" y2="-76" transform={`rotate(${minDeg})`} className="hand min" />
        <circle r="5" className="pin" />
      </svg>
      <div className="ph-city-time">{clockText(h, m)}<small>{clockSuffix(h)}</small></div>
      <div className="ph-sub">Los Santos{world?.weather ? ` · ${world.weather.toLowerCase()}` : ''}</div>
    </div>
  );
}

const sw2 = (ms: number) => { const t = Math.floor(ms / 10); return `${pad(Math.floor(t / 6000))}:${pad(Math.floor((t % 6000) / 100))}.${pad(t % 100)}`; };

function Stopwatch() {
  useTick(50);
  const start = () => { sw.startedAt = Date.now(); sw.running = true; };
  const stop = () => { sw.base = swElapsed(); sw.running = false; };
  const lap = () => { sw.laps = [swElapsed(), ...sw.laps]; };
  const reset = () => { sw.running = false; sw.base = 0; sw.laps = []; };
  return (
    <div className="ph-sw">
      <div className="ph-sw-time">{sw2(swElapsed())}</div>
      <div className="ph-sw-actions">
        <button className="ph-round" onClick={sw.running ? lap : reset} disabled={!sw.running && swElapsed() === 0}>{sw.running ? 'Lap' : 'Reset'}</button>
        <button className={cx('ph-round', sw.running ? 'stop' : 'go')} onClick={sw.running ? stop : start}>{sw.running ? 'Stop' : 'Start'}</button>
      </div>
      <ul className="ph-laps">
        {sw.laps.map((l, i) => <li key={i}><span>Lap {sw.laps.length - i}</span><span>{sw2(l - (sw.laps[i + 1] ?? 0))}</span></li>)}
      </ul>
    </div>
  );
}

const PRESETS = [60, 5 * 60, 10 * 60, 15 * 60, 30 * 60];
const mmss = (s: number) => `${pad(Math.floor(s / 60))}:${pad(s % 60)}`;

function TimerTab() {
  useTick(250);
  const [, setN] = useState(0);
  const redraw = () => setN((n) => n + 1);
  const left = tm.running ? Math.max(0, Math.ceil((tm.end - Date.now()) / 1000)) : tm.left;
  const R = 82, C = 2 * Math.PI * R;
  const frac = tm.total > 0 ? left / tm.total : 0;
  const start = () => { tm.end = Date.now() + tm.left * 1000; tm.running = true; ensureTimerLoop(); redraw(); };
  const pause = () => { tm.left = Math.max(1, Math.ceil((tm.end - Date.now()) / 1000)); tm.running = false; redraw(); };
  const cancel = () => { tm.running = false; tm.left = tm.total; redraw(); };
  const pick = (s: number) => { if (tm.running) return; tm.total = s; tm.left = s; redraw(); };
  const adjust = (d: number) => { if (tm.running) return; tm.total = Math.max(10, Math.min(5940, tm.total + d)); tm.left = tm.total; redraw(); };
  const idle = !tm.running && tm.left === tm.total;
  return (
    <div className="ph-timer">
      <div className="ph-ring">
        <svg viewBox="-100 -100 200 200"><circle r={R} className="bg" /><circle r={R} className="fg" strokeDasharray={C} strokeDashoffset={C * (1 - frac)} transform="rotate(-90)" /></svg>
        <div className="ph-ring-time">{mmss(left)}</div>
        {idle && <div className="ph-ring-adj"><button onClick={() => adjust(-30)} aria-label="Less time"><Ico name="minus" size={18} /></button><button onClick={() => adjust(30)} aria-label="More time"><Ico name="plus" size={18} /></button></div>}
      </div>
      {idle && <div className="ph-presets">{PRESETS.map((p) => <button key={p} className={cx(tm.total === p && 'on')} onClick={() => pick(p)}>{p >= 60 ? `${p / 60}m` : `${p}s`}</button>)}</div>}
      <div className="ph-sw-actions">
        <button className="ph-round" onClick={cancel} disabled={idle}>Cancel</button>
        <button className={cx('ph-round', tm.running ? 'stop' : 'go')} onClick={tm.running ? pause : start}>{tm.running ? 'Pause' : tm.left < tm.total ? 'Resume' : 'Start'}</button>
      </div>
    </div>
  );
}
