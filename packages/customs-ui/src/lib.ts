import { nui, type NuiResponse } from '@veyl/ui';

export type Value = number | boolean | RGB | Paint | Neon;
export interface RGB { r: number; g: number; b: number }
export interface Paint { index: number; rgb?: RGB | null }
export interface Neon { l: boolean; r: boolean; f: boolean; b: boolean }
export interface Opt { key: string; label: string; cat: string; kind: string; camera?: string; values?: { value: number; label: string }[]; toggle?: boolean }
export interface Line { key?: string; id?: number; label: string; price: number; installed?: boolean; cat?: string }
export interface Totals { lines: Line[]; subtotal: number; labor: number; tax: number; total: number }

/** Server call through the client's whitelisted pass-through (the server prices and authorises everything). */
export function api<T = unknown>(name: string, ...args: unknown[]): Promise<NuiResponse<T>> { return nui<T>('api', { name, args }); }

export const money = (n?: number) => `$${Math.round(n ?? 0).toLocaleString('en-US')}`;

export function hexToRgb(hex: string): RGB | null {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim());
  if (!m) return null;
  const n = parseInt(m[1], 16);
  return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
}
export const rgbToHex = (c: RGB) => `#${[c.r, c.g, c.b].map((v) => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')).join('').toUpperCase()}`;

export function hsvToRgb(h: number, s: number, v: number): RGB {
  const f = (n: number) => { const k = (n + h / 60) % 6; return v - v * s * Math.max(0, Math.min(k, 4 - k, 1)); };
  return { r: Math.round(f(5) * 255), g: Math.round(f(3) * 255), b: Math.round(f(1) * 255) };
}
export function rgbToHsv({ r, g, b }: RGB): { h: number; s: number; v: number } {
  const R = r / 255, G = g / 255, B = b / 255, max = Math.max(R, G, B), min = Math.min(R, G, B), d = max - min;
  let h = 0;
  if (d) h = max === R ? ((G - B) / d) % 6 : max === G ? (B - R) / d + 2 : (R - G) / d + 4;
  return { h: (h * 60 + 360) % 360, s: max ? d / max : 0, v: max };
}

export const same = (a: unknown, b: unknown) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null);

export const STATUS: Record<string, { label: string; tone: string }> = {
  draft: { label: 'Draft, not sent', tone: 'muted' }, sent: { label: 'Awaiting approval', tone: 'warn' }, approved: { label: 'Approved, queued', tone: 'ok' },
  in_progress: { label: 'In progress', tone: 'ok' }, completed: { label: 'Completed', tone: 'muted' }, rejected: { label: 'Rejected', tone: 'bad' },
  expired: { label: 'Expired', tone: 'bad' }, cancelled: { label: 'Cancelled', tone: 'bad' },
};
