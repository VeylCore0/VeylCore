import { nui, type NuiResponse } from '@veyl/ui';

/** Calls one of the whitelisted server callbacks through the client bridge. */
export function api<T = unknown>(name: string, ...args: unknown[]): Promise<NuiResponse<T>> {
  return nui<T>('api', { name, args });
}

export const newClientOp = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;

// ---------------------------------------------------------------------------
// Sounds: generated with WebAudio (no audio files), so volume settings are real.
// ---------------------------------------------------------------------------
let ctx: AudioContext | null = null;
let ringTimer: number | null = null;

function audio() {
  if (!ctx) ctx = new (window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext)();
  return ctx;
}

function tone(freq: number, start: number, dur: number, vol: number, type: OscillatorType = 'sine') {
  const a = audio();
  const o = a.createOscillator();
  const g = a.createGain();
  o.type = type;
  o.frequency.value = freq;
  g.gain.setValueAtTime(0, a.currentTime + start);
  g.gain.linearRampToValueAtTime(vol, a.currentTime + start + 0.02);
  g.gain.exponentialRampToValueAtTime(0.0001, a.currentTime + start + dur);
  o.connect(g).connect(a.destination);
  o.start(a.currentTime + start);
  o.stop(a.currentTime + start + dur + 0.05);
}

const RINGS: Record<string, [number, number, number][]> = {
  veyl: [[659, 0, 0.18], [784, 0.2, 0.18], [988, 0.4, 0.3]],
  pulse: [[523, 0, 0.12], [523, 0.16, 0.12], [523, 0.32, 0.12], [698, 0.5, 0.25]],
  classic: [[880, 0, 0.08], [880, 0.1, 0.08], [880, 0.2, 0.08], [880, 0.3, 0.08], [880, 0.4, 0.08], [880, 0.5, 0.08]],
  chime: [[1046, 0, 0.4], [784, 0.25, 0.4], [659, 0.5, 0.5]],
};

export function playRing(name: string, volume: number) {
  stopRing();
  if (volume <= 0) return;
  const v = (volume / 100) * 0.25;
  const play = () => (RINGS[name] ?? RINGS.veyl).forEach(([f, s, d]) => tone(f, s, d, v, 'triangle'));
  play();
  ringTimer = window.setInterval(play, 2200);
}

export function stopRing() {
  if (ringTimer !== null) { window.clearInterval(ringTimer); ringTimer = null; }
}

export function playNotify(name: string, volume: number) {
  if (name === 'none' || volume <= 0) return;
  const v = (volume / 100) * 0.2;
  if (name === 'bell') { tone(1318, 0, 0.35, v); tone(1760, 0.08, 0.4, v * 0.6); } else { tone(880, 0, 0.09, v, 'triangle'); tone(1175, 0.09, 0.12, v, 'triangle'); }
}
