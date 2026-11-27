// Phone sounds, synthesised with WebAudio (no audio files). Everything respects volume, silent mode and Do Not Disturb.
import type { Settings } from './types';

let ctx: AudioContext | null = null;
function ac(): AudioContext | null {
  try {
    ctx ??= new AudioContext();
    if (ctx.state === 'suspended') void ctx.resume();
    return ctx;
  } catch { return null; }
}

function tone(freq: number, at: number, dur: number, vol: number, wave: OscillatorType = 'sine') {
  const c = ac();
  if (!c || vol <= 0) return;
  const o = c.createOscillator(), g = c.createGain();
  o.type = wave; o.frequency.value = freq;
  const t0 = c.currentTime + at;
  g.gain.setValueAtTime(0.0001, t0);
  g.gain.exponentialRampToValueAtTime(vol, t0 + 0.012);
  g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
  o.connect(g).connect(c.destination);
  o.start(t0); o.stop(t0 + dur + 0.05);
}

const level = (s: Settings, scale = 0.16) => (s.silent || s.dnd ? 0 : (s.volume / 100) * scale);

export function playNotify(s: Settings, silentPush = false) {
  const v = silentPush ? 0 : level(s);
  if (!v || s.notifySound === 'none') return;
  if (s.notifySound === 'tap') { tone(1500, 0, 0.06, v, 'triangle'); return; }
  tone(988, 0, 0.14, v); tone(1480, 0.1, 0.22, v);
}

export function playTap(s: Settings) {
  const v = level(s, 0.05);
  if (v) tone(1800, 0, 0.03, v, 'triangle');
}

const RINGS: Record<string, { every: number; play: (v: number) => void }> = {
  default: { every: 2400, play: (v) => [659, 784, 988, 1319].forEach((f, i) => tone(f, i * 0.13, 0.28, v)) },
  pulse: { every: 1800, play: (v) => { tone(392, 0, 0.22, v, 'square'); tone(392, 0.32, 0.22, v, 'square'); } },
  classic: { every: 3000, play: (v) => { for (let r = 0; r < 2; r++) for (let i = 0; i < 6; i++) tone(i % 2 ? 660 : 880, r * 0.7 + i * 0.07, 0.07, v, 'square'); } },
  chime: { every: 2600, play: (v) => [1047, 1319, 1568, 2093].forEach((f, i) => tone(f, i * 0.16, 0.7, v * 0.8)) },
};

let ringTimer: number | undefined;
/** Rings until stopRing(). `preview` plays once at the chosen volume even in silent mode (Settings ringtone picker). */
export function startRing(s: Settings, preview = false) {
  stopRing();
  const r = RINGS[s.ringtone] ?? RINGS.default;
  const v = preview ? (s.volume / 100) * 0.16 : level(s, 0.2);
  if (!v) return;
  r.play(v);
  if (!preview) ringTimer = window.setInterval(() => r.play(v), r.every);
}
export function stopRing() { if (ringTimer !== undefined) { window.clearInterval(ringTimer); ringTimer = undefined; } }

export function playTimerDone(s: Settings) {
  const v = level(s, 0.2) || 0.1;
  for (let i = 0; i < 4; i++) tone(1175, i * 0.28, 0.14, v, 'triangle');
}
