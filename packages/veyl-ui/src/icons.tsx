// Consistent 24px line icon set (stroke = currentColor). Names are used by Lua configs (e.g. target option `icon`).
import type { CSSProperties } from 'react';

const P: Record<string, string> = {
  search: 'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14zM21 21l-4.35-4.35',
  close: 'M6 6l12 12M18 6L6 18',
  plus: 'M12 5v14M5 12h14',
  minus: 'M5 12h14',
  check: 'M5 12.5l4.5 4.5L19 7',
  alert: 'M12 4l9 16H3L12 4zM12 10v4M12 17.5v.5',
  chevron: 'M9 6l6 6-6 6',
  home: 'M4 11l8-7 8 7M6 9.5V20h12V9.5M10 20v-5h4v5',
  card: 'M3 6h18v12H3zM3 10h18M7 15h4',
  transfer: 'M4 8h14M14 4l4 4-4 4M20 16H6M10 12l-4 4 4 4',
  clock: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM12 7v5l3 2',
  briefcase: 'M4 8h16v11H4zM9 8V5h6v3M4 13h16',
  cart: 'M3 4h2l2.4 11h10.2L20 8H6.2M9 20a1 1 0 1 0 0-.01M17 20a1 1 0 1 0 0-.01',
  car: 'M5 16V12l2-5h10l2 5v4M3 16h18v2H3zM7.5 13.5h.01M16.5 13.5h.01M6 18v2M18 18v2',
  lock: 'M6 11h12v9H6zM8.5 11V8a3.5 3.5 0 0 1 7 0v3',
  unlock: 'M6 11h12v9H6zM8.5 11V8a3.5 3.5 0 0 1 6.8-1.2',
  trunk: 'M4 9h16v10H4zM4 9l2-4h12l2 4M10 13h4',
  inspect: 'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14zM21 21l-4.35-4.35M11 8v6M8 11h6',
  heart: 'M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.5-7 10-7 10z',
  shield: 'M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6l7-3z',
  burger: 'M4 11a8 6 0 0 1 16 0zM4 14h16M5 17h14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2z',
  drop: 'M12 3s6 6.5 6 11a6 6 0 0 1-12 0c0-4.5 6-11 6-11z',
  brain: 'M9 4a3 3 0 0 0-3 3 3 3 0 0 0-2 5 3 3 0 0 0 2 5 3 3 0 0 0 6 1V5a2 2 0 0 0-3-1zM15 4a3 3 0 0 1 3 3 3 3 0 0 1 2 5 3 3 0 0 1-2 5 3 3 0 0 1-6 1',
  bolt: 'M13 3L5 14h6l-1 7 8-11h-6l1-7z',
  lungs: 'M12 4v8M12 12c-2 0-3-2-5-2-2 0-3 3-3 6 0 2 1 4 3 4 3 0 5-2 5-5M12 12c2 0 3-2 5-2 2 0 3 3 3 6 0 2-1 4-3 4-3 0-5-2-5-5',
  mic: 'M12 3a3 3 0 0 1 3 3v5a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3zM6 11a6 6 0 0 0 12 0M12 17v4',
  fuel: 'M5 20V5a1 1 0 0 1 1-1h7a1 1 0 0 1 1 1v15M4 20h11M6 9h7M14 10h2a1 1 0 0 1 1 1v5a1.5 1.5 0 0 0 3 0V9l-3-3',
  seatbelt: 'M12 3a2 2 0 1 1 0 4 2 2 0 0 1 0-4zM8 21v-8l2-4h4l2 4v8M7 9l10 10',
  mouse: 'M12 3a5 5 0 0 1 5 5v8a5 5 0 0 1-10 0V8a5 5 0 0 1 5-5zM12 7v3',
  box: 'M4 8l8-4 8 4v8l-8 4-8-4zM4 8l8 4 8-4M12 12v8',
  bank: 'M3 9l9-5 9 5M5 10v8M9.5 10v8M14.5 10v8M19 10v8M3 20h18',
  user: 'M12 4a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM4 20a8 8 0 0 1 16 0',
  hand: 'M8 13V6a1.5 1.5 0 0 1 3 0v5M11 11V4.5a1.5 1.5 0 0 1 3 0V11M14 11V6a1.5 1.5 0 0 1 3 0v8a6 6 0 0 1-6 6h-.5A5.5 5.5 0 0 1 6 17l-2-4a1.5 1.5 0 0 1 2.6-1.5L8 13',
  door: 'M6 21V4h10v17M4 21h16M13 12h.01',
  gas: 'M5 20V5a1 1 0 0 1 1-1h7a1 1 0 0 1 1 1v15M4 20h11M6 9h7M14 10h2a1 1 0 0 1 1 1v5a1.5 1.5 0 0 0 3 0V9l-3-3',
  money: 'M3 7h18v10H3zM12 9.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5zM6 10v.01M18 14v.01',
  basket: 'M5 10h14l-1.5 9h-11zM9 10l3-6 3 6',
  hotbar: 'M4 8h16v8H4zM9 8v8M15 8v8',
  give: 'M4 14h4l3 2h4a2 2 0 0 0 0-4h-3M4 20h12l5-4M15 3v6M12 6h6',
  drop_item: 'M12 3v11M8 10l4 4 4-4M5 20h14',
  use: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM10 8.5l5 3.5-5 3.5z',
};

export type IconName = keyof typeof P | string;

export function Icon({ name, size = 18, style, strokeWidth = 1.6 }: { name: IconName; size?: number | string; style?: CSSProperties; strokeWidth?: number }) {
  const d = P[name] ?? P.box;
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={strokeWidth}
      strokeLinecap="round" strokeLinejoin="round" style={style} aria-hidden="true">
      <path d={d} />
    </svg>
  );
}

/** The VeylCore "V" mark (two-tone violet chevron). */
export function VMark({ size = 22 }: { size?: number | string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" aria-hidden="true">
      <path d="M3 6h7l6 13 6-13h7L18.5 27h-5z" fill="#9b72d5" />
      <path d="M10 6h4l2 4.5L18 6h4l-6 13z" fill="#c9adf7" />
    </svg>
  );
}
