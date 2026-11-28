// Music: built-in stations are generated live with WebAudio (no audio files or streams needed);
// stations with a `url` play internet radio. One player for your own listening, one per nearby speaker.

import { post } from './api';

export interface Station { id: string; label: string; style?: 'synth' | 'lofi' | 'night'; url?: string }

let ctx: AudioContext | null = null;
const ac = () => (ctx ??= new AudioContext());

const STYLES = {
  synth: { bpm: 104, root: 45, prog: [[0, 3, 7, 10], [-4, 0, 3, 7], [-2, 2, 5, 9], [-7, -3, 0, 5]], wave: 'sawtooth' as OscillatorType, hat: true, cutoff: 1800 },
  lofi: { bpm: 78, root: 50, prog: [[0, 4, 7, 11], [-3, 0, 4, 9], [2, 5, 9, 12], [-5, -1, 2, 7]], wave: 'triangle' as OscillatorType, hat: true, cutoff: 1100 },
  night: { bpm: 92, root: 40, prog: [[0, 3, 7, 12], [-2, 3, 7, 10], [-4, 0, 3, 8], [-5, -1, 2, 7]], wave: 'square' as OscillatorType, hat: false, cutoff: 900 },
};
const hz = (midi: number) => 440 * 2 ** ((midi - 69) / 12);

class Player {
  private out: GainNode;
  private timer: number | null = null;
  private audio: HTMLAudioElement | null = null;
  private nextAt = 0;
  private step = 0;
  station: Station | null = null;

  constructor(volume: number) {
    this.out = ac().createGain();
    this.out.gain.value = volume;
    this.out.connect(ac().destination);
  }

  setVolume(v: number) {
    this.out.gain.setTargetAtTime(Math.max(0, Math.min(1, v)) * 0.6, ac().currentTime, 0.2);
    if (this.audio) this.audio.volume = Math.max(0, Math.min(1, v));
  }

  play(st: Station) {
    this.stop();
    this.station = st;
    void ac().resume();
    if (st.url) {
      this.audio = new Audio(st.url);
      this.audio.crossOrigin = 'anonymous';
      this.audio.volume = this.out.gain.value / 0.6;
      void this.audio.play().catch(() => undefined);
      return;
    }
    const s = STYLES[st.style ?? 'synth'];
    const beat = 60 / s.bpm / 2; // eighth notes
    this.nextAt = ac().currentTime + 0.1;
    this.step = 0;
    const tick = () => {
      while (this.nextAt < ac().currentTime + 0.3) { this.note(s, this.step, this.nextAt, beat); this.nextAt += beat; this.step++; }
    };
    tick();
    this.timer = window.setInterval(tick, 100);
  }

  private note(s: (typeof STYLES)['synth'], step: number, t: number, beat: number) {
    const a = ac();
    const chord = s.prog[Math.floor(step / 16) % s.prog.length];
    const env = (g: GainNode, peak: number, dur: number) => { g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(peak, t + 0.02); g.gain.exponentialRampToValueAtTime(0.0001, t + dur); };
    const voice = (freq: number, type: OscillatorType, peak: number, dur: number, cutoff: number) => {
      const o = a.createOscillator(); const f = a.createBiquadFilter(); const g = a.createGain();
      o.type = type; o.frequency.value = freq; f.type = 'lowpass'; f.frequency.value = cutoff;
      env(g, peak, dur); o.connect(f).connect(g).connect(this.out); o.start(t); o.stop(t + dur + 0.05);
    };
    if (step % 16 === 0) for (const n of chord) voice(hz(s.root + 12 + n), s.wave, 0.05, beat * 16, s.cutoff * 0.6); // pad
    if (step % 2 === 0) voice(hz(s.root - 12 + chord[0] + (step % 8 === 6 ? 7 : 0)), 'sine', 0.22, beat * 1.6, 600); // bass
    // Arpeggio follows a fixed pattern through the chord.
    const arp = [0, 2, 1, 3, 2, 1, 3, 0][step % 8];
    if ((step * 7) % 5 !== 0) voice(hz(s.root + 24 + chord[arp]), 'triangle', 0.06, beat * 0.9, s.cutoff);
    if (step % 4 === 0) { // kick
      const o = a.createOscillator(); const g = a.createGain();
      o.frequency.setValueAtTime(120, t); o.frequency.exponentialRampToValueAtTime(40, t + 0.15);
      env(g, 0.35, 0.18); o.connect(g).connect(this.out); o.start(t); o.stop(t + 0.2);
    }
    if (s.hat && step % 2 === 1) { // hat
      const len = Math.floor(a.sampleRate * 0.04); const buf = a.createBuffer(1, len, a.sampleRate); const d = buf.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / len);
      const src = a.createBufferSource(); const f = a.createBiquadFilter(); const g = a.createGain();
      src.buffer = buf; f.type = 'highpass'; f.frequency.value = 7000; g.gain.value = 0.05;
      src.connect(f).connect(g).connect(this.out); src.start(t);
    }
  }

  stop() {
    if (this.timer !== null) window.clearInterval(this.timer);
    this.timer = null;
    if (this.audio) { this.audio.pause(); this.audio.src = ''; this.audio = null; }
    this.station = null;
  }

  dispose() { this.stop(); this.out.disconnect(); }
}

// ---------------------------------------------------------------------------
// Your own player (keeps playing with the phone closed)
// ---------------------------------------------------------------------------
let mine: Player | null = null;
let myVolume = 0.5;
const listeners = new Set<() => void>();
const emit = () => listeners.forEach((fn) => fn());

export const music = {
  get station() { return mine?.station ?? null; },
  get volume() { return myVolume; },
  play(st: Station) { (mine ??= new Player(myVolume * 0.6)).play(st); mine.setVolume(myVolume); emit(); },
  stop() { mine?.stop(); emit(); },
  setVolume(v: number) { myVolume = v; mine?.setVolume(v); emit(); },
  subscribe(fn: () => void) { listeners.add(fn); return () => { listeners.delete(fn); }; },
};

// ---------------------------------------------------------------------------
// Other players' speakers (the client sends the list with a volume by distance)
// ---------------------------------------------------------------------------
let stations: Station[] = [];
export const setStations = (list: Station[]) => { stations = list; };
const speakers = new Map<number, Player>();

export function syncSpeakers(list: { id: number; station: string; volume: number }[]) {
  const seen = new Set<number>();
  for (const s of list) {
    const st = stations.find((x) => x.id === s.station);
    if (!st) continue;
    seen.add(s.id);
    let p = speakers.get(s.id);
    if (!p) { p = new Player(0); speakers.set(s.id, p); }
    if (p.station?.id !== st.id) p.play(st);
    p.setVolume(s.volume * 0.7);
  }
  for (const [id, p] of speakers) if (!seen.has(id)) { p.dispose(); speakers.delete(id); }
}

/** Station list from the server config (once). */
let loaded = false;
export async function loadStations(): Promise<Station[]> {
  if (!loaded) {
    const r = await post<Station[]>('musicStations');
    if (r.ok && Array.isArray(r.data)) { stations = r.data; loaded = true; }
  }
  return stations;
}
export const getStations = () => stations;
