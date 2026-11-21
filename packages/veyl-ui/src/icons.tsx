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
  // Appearance
  dna: 'M7 3c0 6 10 6 10 12s-10 6-10 6M17 3c0 6-10 6-10 12M8 7h8M8 17h8',
  face: 'M12 3a7 8 0 1 0 0 16 7 8 0 0 0 0-16zM9 10h.01M15 10h.01M9.5 14.5a3.5 3.5 0 0 0 5 0',
  eye: 'M2 12s3.6-6 10-6 10 6 10 6-3.6 6-10 6S2 12 2 12zM12 9.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5z',
  scissors: 'M6 4a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5zM6 15a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5zM8.1 8.1L20 18M8.1 15.9L20 6',
  beard: 'M5 6v4a7 8 0 0 0 14 0V6M9 13h6M10 16h4',
  sparkle: 'M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8zM19 16l.7 2 2 .7-2 .7-.7 2-.7-2-2-.7 2-.7z',
  shirt: 'M8 4l-5 3 2 4 2-1v10h10V10l2 1 2-4-5-3a4 4 0 0 1-8 0z',
  pants: 'M7 3h10l1 18h-4l-2-11-2 11H6z',
  shoe: 'M3 16v-6l4 1 3-4 3 6 6 1.5a2 2 0 0 1 2 2V16zM3 16v3h18v-3',
  bag: 'M5 8h14l-1 12H6zM9 8V6a3 3 0 0 1 6 0v2',
  jewel: 'M6 4h12l3 5-9 11L3 9zM3 9h18M9 4l3 5 3-5',
  mask: 'M4 7c3-2 13-2 16 0 0 6-3 10-8 10S4 13 4 7zM8.5 10.5h2M13.5 10.5h2',
  hat: 'M3 17h18M6 17c0-5 2-9 6-9s6 4 6 9M10 8V6h4v2',
  glasses: 'M3 11h18M6.5 10a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7zM17.5 10a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7zM10 13.5h4',
  watch: 'M12 7a5 5 0 1 0 0 10 5 5 0 0 0 0-10zM9 7l1-4h4l1 4M9 17l1 4h4l1-4M12 10v2l1.5 1',
  hanger: 'M12 7a2 2 0 1 1 2-2M12 7v2L3 16h18l-9-7',
  rotate_left: 'M4 4v5h5M4.6 9A8 8 0 1 1 6 16.5',
  rotate_right: 'M20 4v5h-5M19.4 9A8 8 0 1 0 18 16.5',
  reset: 'M3 12a9 9 0 1 0 3-6.7L3 8M3 3v5h5',
  camera: 'M3 8h4l2-3h6l2 3h4v11H3zM12 10a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7z',
  // Vehicles
  wrench: 'M14.5 6.5a4 4 0 0 0 5 5L21 13l-8 8-3-3 8-8-1.5-1.5a4 4 0 0 1-5-5L13 2l1.5 4.5zM5 19l-2 2',
  receipt: 'M6 3h12v18l-3-2-3 2-3-2-3 2zM9 8h6M9 12h6M9 16h3',
  garage: 'M3 21V9l9-5 9 5v12M7 21v-8h10v8M7 16h10',
  fuel_drop: 'M12 3s-6 7-6 11a6 6 0 0 0 12 0c0-4-6-11-6-11z',
  engine: 'M4 10h3l2-3h6v3h2l2 2v5h-2l-2 2H8l-2-2H4zM12 7V4M10 4h4',
  tag: 'M3 12V4h8l10 10-8 8zM7.5 8.5h.01',
  // Phone
  call: 'M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2z',
  hang: 'M3 14c5-5 13-5 18 0l-2 3-4-1.5v-2.5a10 10 0 0 0-6 0v2.5L5 17z',
  chat: 'M4 5h16v11H9l-5 4z',
  send: 'M4 12l16-8-6 16-2.5-6.5z',
  mic_off: 'M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3zM5 11a7 7 0 0 0 14 0M12 18v3M4 4l16 16',
  dialpad: 'M6 5h.01M12 5h.01M18 5h.01M6 11h.01M12 11h.01M18 11h.01M6 17h.01M12 17h.01M18 17h.01M12 21h.01',
  star: 'M12 3l2.8 5.8 6.2.9-4.5 4.4 1 6.2L12 17.4 6.5 20.3l1-6.2L3 9.7l6.2-.9z',
  block: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM5.6 5.6l12.8 12.8',
  folder: 'M3 6h6l2 2h10v11H3z',
  bell: 'M6 16V11a6 6 0 0 1 12 0v5l2 2H4zM10 21h4',
  bell_off: 'M6 16V11a6 6 0 0 1 9.5-4.9M18 11v5l2 2H8M10 21h4M4 4l16 16',
  moon: 'M20 14A8 8 0 0 1 10 4a8 8 0 1 0 10 10z',
  back: 'M15 5l-7 7 7 7',
  edit: 'M4 20h4L19 9l-4-4L4 16zM14 6l4 4',
  sun: 'M12 7a5 5 0 1 0 0 10 5 5 0 0 0 0-10zM12 1v2M12 21v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M1 12h2M21 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4',
  cloud: 'M7 18h10a4 4 0 0 0 .5-8A6 6 0 0 0 6 9.5 4.3 4.3 0 0 0 7 18z',
  rain: 'M7 14h10a4 4 0 0 0 .5-8A6 6 0 0 0 6 5.5 4.3 4.3 0 0 0 7 14zM8 17l-1 3M12 17l-1 3M16 17l-1 3',
  share: 'M12 3v12M7 8l5-5 5 5M5 13v7h14v-7',
  more: 'M5 12h.01M12 12h.01M19 12h.01',
  users: 'M9 4a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7zM2 20a7 7 0 0 1 14 0M16 4.5a3.5 3.5 0 0 1 0 6.5M18 14a6 6 0 0 1 4 6',
  phone_size: 'M8 2h8a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2zM11 18h2',
  // Grow
  leaf: 'M5 19c0-8 5-14 15-15-1 10-7 15-15 15zM5 19l8-8',
  gear: 'M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z',
  pin: 'M12 21s-6-5.5-6-11a6 6 0 0 1 12 0c0 5.5-6 11-6 11zM12 8a2 2 0 1 0 0 4 2 2 0 0 0 0-4z',
  // Phone apps
  key: 'M15 3a6 6 0 0 0-5.7 7.9L3 17.2V21h3.8v-2.4h2.4v-2.4h2.2l1.7-1.7A6 6 0 1 0 15 3zM16.5 6.2a1.3 1.3 0 1 0 0 2.6 1.3 1.3 0 0 0 0-2.6z',
  bird: 'M4 17c3 1 7 .5 10-2.5 2-2 3-4.5 3-7l3-1.5-3-.5a3.5 3.5 0 0 0-6 1.5c-3 0-6-1.5-8-4 0 3 1 5.5 3 7-1 .3-2 .2-3-.2.5 2 2 3.5 4 4-1 .7-2 1-3 1.2z',
  note: 'M6 3h9l4 4v14H6zM15 3v4h4M9 11h7M9 15h7M9 19h4',
  calc: 'M6 3h12v18H6zM9 6.5h6v3H9zM9 13h.01M12 13h.01M15 13h.01M9 16.5h.01M12 16.5h.01M15 16.5h.01',
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
