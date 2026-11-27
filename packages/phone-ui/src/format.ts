// Formatting helpers. Server timestamps are unix seconds; the client clock is corrected with the offset from `hello`.
let offset = 0;
export const setClockOffset = (serverTime: number) => { offset = serverTime - Math.floor(Date.now() / 1000); };
export const nowSec = () => Math.floor(Date.now() / 1000) + offset;

export const pad = (n: number) => String(n).padStart(2, '0');

/** In-game clock for the status bar: 12-hour without am/pm, like a phone. */
export function clockText(hour: number, minute: number) {
  const h = hour % 12 === 0 ? 12 : hour % 12;
  return `${h}:${pad(minute)}`;
}
export const clockSuffix = (hour: number) => (hour >= 12 ? 'PM' : 'AM');

export function timeOfDay(ts: number) {
  const d = new Date(ts * 1000);
  const h = d.getHours() % 12 === 0 ? 12 : d.getHours() % 12;
  return `${h}:${pad(d.getMinutes())} ${d.getHours() >= 12 ? 'PM' : 'AM'}`;
}

const DAY = 86400;
const startOfDay = (ts: number) => { const d = new Date(ts * 1000); d.setHours(0, 0, 0, 0); return Math.floor(d.getTime() / 1000); };

/** List timestamps: today = time, yesterday, this week = weekday, otherwise a short date. */
export function listTime(ts: number) {
  const today = startOfDay(nowSec());
  if (ts >= today) return timeOfDay(ts);
  if (ts >= today - DAY) return 'Yesterday';
  if (ts >= today - 6 * DAY) return new Date(ts * 1000).toLocaleDateString('en-US', { weekday: 'short' });
  return new Date(ts * 1000).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

/** Day separators inside a thread. */
export function dayLabel(ts: number) {
  const today = startOfDay(nowSec());
  if (ts >= today) return 'Today';
  if (ts >= today - DAY) return 'Yesterday';
  return new Date(ts * 1000).toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' });
}
export const sameDay = (a: number, b: number) => startOfDay(a) === startOfDay(b);

export function duration(sec: number) {
  const s = Math.max(0, Math.floor(sec));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
  return h > 0 ? `${h}:${pad(m)}:${pad(s % 60)}` : `${m}:${pad(s % 60)}`;
}

/** '5551234' | '555-12' -> '555-1234' while typing. */
export function formatDigits(d: string) {
  const digits = d.replace(/\D/g, '').slice(0, 7);
  return digits.length > 3 ? `${digits.slice(0, 3)}-${digits.slice(3)}` : digits;
}

export function initials(name: string) {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (!parts.length || /^[\d\s()+-]+$/.test(name)) return '';
  return (parts[0][0] + (parts.length > 1 ? parts[parts.length - 1][0] : '')).toUpperCase();
}

const hash = (s: string) => { let h = 7; for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0; return Math.abs(h); };
export function avatarBg(key: string) {
  const h = hash(key) % 360;
  return `linear-gradient(145deg, hsl(${h} 62% 58%), hsl(${(h + 38) % 360} 66% 38%))`;
}

/** Lighten (amt > 0) or darken (amt < 0) a #rrggbb colour. */
export function shade(hex: string, amt: number) {
  const m = /^#([0-9a-f]{6})$/i.exec(hex);
  if (!m) return hex;
  const n = parseInt(m[1], 16);
  const ch = (v: number) => Math.max(0, Math.min(255, Math.round(amt >= 0 ? v + (255 - v) * amt : v * (1 + amt))));
  return `#${[(n >> 16) & 255, (n >> 8) & 255, n & 255].map((v) => ch(v).toString(16).padStart(2, '0')).join('')}`;
}

export const plural = (n: number, one: string, many = `${one}s`) => `${n} ${n === 1 ? one : many}`;
