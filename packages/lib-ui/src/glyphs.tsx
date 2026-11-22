// Line icons for notifications and progress (local SVG, no icon font or CDN). Unknown names fall back to "info".
const P: Record<string, string> = {
  success: 'M5 12.5l4.2 4.2L19 7', check: 'M5 12.5l4.2 4.2L19 7',
  info: 'M12 11v6 M12 7.2v.1 M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z',
  warning: 'M12 7v7 M12 17.2v.1', error: 'M7 7l10 10 M17 7L7 17', close: 'M7 7l10 10 M17 7L7 17',
  wrench: 'M14.7 6.3a4 4 0 0 0-5.3 5.3L4 17l3 3 5.4-5.4a4 4 0 0 0 5.3-5.3l-2.5 2.5-2.3-.6-.6-2.3z',
  money: 'M3 7h18v10H3z M12 14.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z M6 10v.1 M18 14v.1',
  car: 'M5 16h14 M6 16l1.5-5h9L18 16 M6 16v2 M18 16v2 M8 13.5h.1 M16 13.5h.1',
  lock: 'M7 11V8a5 5 0 0 1 10 0v3 M5 11h14v9H5z', key: 'M14 10a4 4 0 1 0-1.2 2.8L20 20 M17 17l2-2',
  hand: 'M8 13V6a1.5 1.5 0 0 1 3 0v5 M11 11V4.5a1.5 1.5 0 0 1 3 0V11 M14 11V6a1.5 1.5 0 0 1 3 0v8a6 6 0 0 1-6 6h-1a5 5 0 0 1-4-2l-3-4a1.5 1.5 0 0 1 2.3-2L8 14',
  box: 'M4 8l8-4 8 4v8l-8 4-8-4z M4 8l8 4 8-4 M12 12v8', fuel: 'M5 20V5h9v15 M5 11h9 M14 8l4 3v7a1.5 1.5 0 0 1-3 0v-4h-1',
  heart: 'M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z', clock: 'M12 7v5l3 2 M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z',
  bell: 'M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15z M10 20h4', message: 'M4 5h16v11H9l-5 4z',
};

export function Glyph({ name, size = '1em' }: { name: string; size?: string }) {
  const d = P[name] ?? P.info;
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      {d.split(' M').map((seg, i) => <path key={i} d={i ? `M${seg}` : seg} />)}
    </svg>
  );
}

export interface UIConfig {
  Theme: { background: string; backgroundOpacity: number; text: string; textSecondary: string; success: string; info: string; warning: string; error: string; scale: number; reducedMotion: boolean };
  Notifications: { position: string; offsetX: number; offsetY: number; width: number; maxVisible: number; maxQueue: number; duplicates: string; restartOnUpdate: boolean; sound: boolean; volume: number };
  Progress: { offsetY: number; width: number; completeMs: number };
  Hold: { releaseText: string };
}

/** Theme -> CSS variables (validated: only #rrggbb colours and clamped numbers are applied). */
export function themeVars(t?: UIConfig['Theme']): React.CSSProperties {
  const hex = (v: string | undefined, d: string) => (typeof v === 'string' && /^#[0-9a-f]{6}$/i.test(v) ? v : d);
  const rgb = (h: string) => `${parseInt(h.slice(1, 3), 16)}, ${parseInt(h.slice(3, 5), 16)}, ${parseInt(h.slice(5, 7), 16)}`;
  const bg = hex(t?.background, '#151D22');
  return {
    '--vn-bg': rgb(bg), '--vn-alpha': String(Math.max(0.5, Math.min(1, t?.backgroundOpacity ?? 0.86))),
    '--vn-text': hex(t?.text, '#F7FAFC'), '--vn-text-2': hex(t?.textSecondary, '#AAB6BF'),
    '--vn-success': hex(t?.success, '#A5F3D0'), '--vn-info': hex(t?.info, '#8BD4EE'), '--vn-warning': hex(t?.warning, '#F0C374'), '--vn-error': hex(t?.error, '#EF9298'),
    '--vn-scale': String(Math.max(0.75, Math.min(1.5, t?.scale ?? 1))),
  } as React.CSSProperties;
}
