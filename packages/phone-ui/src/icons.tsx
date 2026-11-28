import type { CSSProperties, ReactNode } from 'react';

// Feather-style 24x24 stroke icons. Names the phone uses and the icon hints other resources pass to RegisterApp all
// resolve here; unknown names fall back to a box.
const circle = (cx: number, cy: number, r: number) => <circle key={`${cx}${cy}${r}`} cx={cx} cy={cy} r={r} />;
const p = (d: string) => <path key={d} d={d} />;

const ICONS: Record<string, ReactNode[]> = {
  phone: [p('M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z')],
  chat: [p('M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z')],
  users: [p('M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2'), circle(9, 7, 4), p('M23 21v-2a4 4 0 0 0-3-3.87'), p('M16 3.13a4 4 0 0 1 0 7.75')],
  user: [p('M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2'), circle(12, 7, 4)],
  userplus: [p('M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2'), circle(8.5, 7, 4), p('M20 8v6M23 11h-6')],
  sliders: [p('M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6')],
  mail: [p('M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z'), p('M22 6l-10 7L2 6')],
  bag: [p('M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z'), p('M3 6h18'), p('M16 10a4 4 0 0 1-8 0')],
  calc: [p('M6 2h12a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2z'), p('M8 6h8M8 10h.01M12 10h.01M16 10h.01M8 14h.01M12 14h.01M16 14h.01M8 18h.01M12 18h.01M16 18h.01')],
  clock: [circle(12, 12, 10), p('M12 6v6l4 2')],
  search: [circle(11, 11, 8), p('M21 21l-4.35-4.35')],
  plus: [p('M12 5v14M5 12h14')],
  x: [p('M18 6L6 18M6 6l12 12')],
  back: [p('M15 18l-6-6 6-6')],
  forward: [p('M9 18l6-6-6-6')],
  down: [p('M6 9l6 6 6-6')],
  check: [p('M20 6L9 17l-5-5')],
  send: [p('M22 2L11 13'), p('M22 2l-7 20-4-9-9-4 20-7z')],
  star: [p('M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z')],
  trash: [p('M3 6h18'), p('M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6'), p('M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2')],
  mic: [p('M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z'), p('M19 10v2a7 7 0 0 1-14 0v-2M12 19v4M8 23h8')],
  image: [p('M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z'), circle(8.5, 8.5, 1.5), p('M21 15l-5-5L5 21')],
  radio: [circle(12, 12, 2), p('M16.24 7.76a6 6 0 0 1 0 8.49M7.76 16.24a6 6 0 0 1 0-8.49M19.07 4.93a10 10 0 0 1 0 14.14M4.93 19.07a10 10 0 0 1 0-14.14')],
  pin: [p('M21 10c0 7-9 13-9 13S3 17 3 10a9 9 0 0 1 18 0z'), circle(12, 10, 3)],
  bell: [p('M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9'), p('M13.73 21a2 2 0 0 1-3.46 0')],
  bellOff: [p('M13.73 21a2 2 0 0 1-3.46 0'), p('M18.63 13A17.89 17.89 0 0 1 18 8'), p('M6.26 6.26A5.86 5.86 0 0 0 6 8c0 7-3 9-3 9h14'), p('M18 8a6 6 0 0 0-9.33-5'), p('M1 1l22 22')],
  moon: [p('M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z')],
  plane: [p('M17.8 19.2L16 11l3.5-3.5C21 6 21.5 4 21 3c-1-.5-3 0-4.5 1.5L13 8 4.8 6.2c-.5-.1-.9.1-1.1.5l-.3.5c-.2.5-.1 1 .3 1.3L9 12l-2 3H4l-1 1 3 2 2 3 1-1v-3l3-2 3.5 5.3c.3.4.8.5 1.3.3l.5-.2c.4-.3.6-.7.5-1.2z')],
  volume: [p('M11 5L6 9H2v6h4l5 4V5z'), p('M19.07 4.93a10 10 0 0 1 0 14.14M15.54 8.46a5 5 0 0 1 0 7.07')],
  mute: [p('M11 5L6 9H2v6h4l5 4V5z'), p('M23 9l-6 6M17 9l6 6')],
  sun: [circle(12, 12, 5), p('M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42')],
  backspace: [p('M21 4H8l-7 8 7 8h13a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2z'), p('M18 9l-6 6M12 9l6 6')],
  edit: [p('M12 20h9'), p('M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z')],
  nav: [p('M3 11l19-9-9 19-2-8-8-2z')],
  block: [circle(12, 12, 10), p('M4.93 4.93l14.14 14.14')],
  more: [p('M5 12h.01M12 12h.01M19 12h.01')],
  play: [p('M5 3l14 9-14 9V3z')],
  pause: [p('M6 4h4v16H6zM14 4h4v16h-4z')],
  stop: [p('M6 6h12v12H6z')],
  reset: [p('M1 4v6h6'), p('M3.51 15a9 9 0 1 0 2.13-9.36L1 10')],
  flag: [p('M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z'), p('M4 22v-7')],
  timer: [circle(12, 13, 8), p('M12 9v4l2 2M9 2h6')],
  download: [p('M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4'), p('M7 10l5 5 5-5'), p('M12 15V3')],
  share: [p('M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8'), p('M16 6l-4-4-4 4'), p('M12 2v13')],
  lock: [p('M5 11h14a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2z'), p('M7 11V7a5 5 0 0 1 10 0v4')],
  fuel: [p('M3 22V4a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v18'), p('M3 22h12'), p('M15 8h2a2 2 0 0 1 2 2v6a1.5 1.5 0 0 0 3 0V9l-3-3'), p('M6 8h6')],
  engine: [p('M4 10h3l2-2h6l2 2h3v6h-3l-2 2H9l-2-2H4z'), p('M12 8V5M10 5h4')],
  money: [p('M2 6h20v12H2z'), circle(12, 12, 3), p('M6 12h.01M18 12h.01')],
  transfer: [p('M7 10h14l-4-4'), p('M17 14H3l4 4')],
  bird: [p('M22 4s-.7 2.1-2 3.4c1.6 10-9.4 17.3-18 11.6 2.2.1 4.4-.6 6-2C3 15.5.5 9.6 3 5c2.2 2.6 5.6 4.1 9 4-.9-4.2 4-6.6 7-3.8 1.1 0 3-1.2 3-1.2z')],
  alert: [circle(12, 12, 10), p('M12 8v4M12 16h.01')],
  minus: [p('M5 12h14')],
  cloud: [p('M18 10h-1.26A8 8 0 1 0 9 20h9a5 5 0 0 0 0-10z')],
  rain: [p('M16 13v8M8 13v8M12 15v8'), p('M20 16.58A5 5 0 0 0 18 7h-1.26A8 8 0 1 0 4 15.25')],
  // icon hints other resources pass to RegisterApp
  home: [p('M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z'), p('M9 22V12h6v10')],
  car: [p('M5 11l1.5-4.5A2 2 0 0 1 8.4 5h7.2a2 2 0 0 1 1.9 1.5L19 11'), p('M3 11h18v6a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-6z'), circle(7.5, 18, 1.5), circle(16.5, 18, 1.5)],
  receipt: [p('M5 2h14v20l-3-2-2 2-2-2-2 2-2-2-3 2z'), p('M9 7h6M9 11h6')],
  eye: [p('M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z'), circle(12, 12, 3)],
  box: [p('M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z'), p('M3.27 6.96L12 12.01l8.73-5.05M12 22.08V12')],
  key: [circle(7.5, 15.5, 5.5), p('M21 2l-9.6 9.6M15.5 7.5l3 3L22 7l-3-3')],
  shield: [p('M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z')],
  briefcase: [p('M4 7h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2z'), p('M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16')],
  map: [p('M1 6v16l7-4 8 4 7-4V2l-7 4-8-4-7 4z'), p('M8 2v16M16 6v16')],
  heart: [p('M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z')],
  wrench: [p('M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z')],
  bank: [p('M3 21h18M3 10h18M5 6l7-3 7 3M4 10v11M20 10v11M8 14v3M12 14v3M16 14v3')],
  camera: [p('M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z'), circle(12, 13, 4)],
  music: [p('M9 18V5l12-2v13'), circle(6, 18, 3), circle(18, 16, 3)],
  note: [p('M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z'), p('M14 2v6h6M16 13H8M16 17H8M10 9H8')],
};

export function Ico({ name, size = 20, stroke = 1.9, style, className }: { name: string; size?: number; stroke?: number; style?: CSSProperties; className?: string }) {
  const body = ICONS[name] ?? ICONS.box;
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round"
      style={style} className={className} aria-hidden="true">{body}</svg>
  );
}

export function SignalBars({ off }: { off?: boolean }) {
  return (
    <svg width="18" height="12" viewBox="0 0 18 12" aria-hidden="true">
      {[0, 1, 2, 3].map((i) => <rect key={i} x={i * 5} y={9 - i * 3} width="3" height={3 + i * 3} rx="1" fill="currentColor" opacity={off ? 0.25 : 1} />)}
    </svg>
  );
}

export function Battery() {
  return (
    <svg width="26" height="12" viewBox="0 0 26 12" aria-hidden="true">
      <rect x="0.5" y="0.5" width="21" height="11" rx="3.5" fill="none" stroke="currentColor" opacity="0.5" />
      <rect x="2" y="2" width="16" height="8" rx="2" fill="currentColor" />
      <path d="M23.5 4v4c.8-.3 1.5-1.1 1.5-2s-.7-1.7-1.5-2z" fill="currentColor" opacity="0.5" />
    </svg>
  );
}
