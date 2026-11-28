import { useEffect, useState, type CSSProperties, type ReactNode } from 'react';
import { nui, type NuiResponse } from '@veyl/ui';

export const api = <T = unknown>(name: string, ...args: unknown[]) => nui<T>('api', { name, args }) as Promise<NuiResponse<T>>;
export const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(' ');
/** '#rrggbb' -> '12, 34, 56' for rgba(var(--x-rgb), a) (color-mix is not available in the game's browser). */
export const rgbOf = (hex: string) => { const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex); return m ? `${parseInt(m[1], 16)}, ${parseInt(m[2], 16)}, ${parseInt(m[3], 16)}` : '255, 255, 255'; };
export const heatVars = (hex: string) => ({ '--heat': hex, '--heat-rgb': rgbOf(hex) }) as React.CSSProperties;
export const usd = (n: number) => `$${Math.round(n).toLocaleString('en-US')}`;

// ---- icons (24x24 stroke) ----------------------------------------------------------------------------------
const PATHS: Record<string, string[]> = {
  dashboard: ['M3 11l9-8 9 8', 'M5 10v10h5v-6h4v6h5V10'],
  contracts: ['M8 3h8l3 3v15H5V3h3', 'M9 9h6M9 13h6M9 17h4'],
  play: ['M6 4l14 8-14 8V4z'],
  car: ['M5 16l1.6-5.2A2 2 0 0 1 8.5 9.4h7a2 2 0 0 1 1.9 1.4L19 16', 'M3 16h18v3H3z', 'M7 19v1.5M17 19v1.5'],
  star: ['M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9L12 3z'],
  crew: ['M17 20v-1.5a3.5 3.5 0 0 0-3.5-3.5h-5A3.5 3.5 0 0 0 5 18.5V20', 'M11 12a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7z', 'M19 20v-1.5a3 3 0 0 0-2-2.8', 'M16 5.3a3.5 3.5 0 0 1 0 6.4'],
  flame: ['M12 3c1 3.5 4.5 5 4.5 9.2A4.5 4.5 0 0 1 12 17a4.5 4.5 0 0 1-4.5-4.8c0-2 1-3 2-4 .2 1.2.9 2 1.7 2.3C11 8.5 11.5 5.5 12 3z', 'M9 21h6'],
  chart: ['M4 20V10M10 20V4M16 20v-8M22 20H2'],
  gear: ['M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z', 'M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z'],
  bell: ['M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9', 'M13.7 21a2 2 0 0 1-3.4 0'],
  x: ['M18 6L6 18M6 6l12 12'],
  pin: ['M21 10c0 7-9 13-9 13S3 17 3 10a9 9 0 0 1 18 0z', 'M12 13a3 3 0 1 0 0-6 3 3 0 0 0 0 6z'],
  clock: ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z', 'M12 7v5l3 2'],
  check: ['M20 6L9 17l-5-5'],
  lock: ['M6 11V8a6 6 0 0 1 12 0v3', 'M5 11h14v10H5z'],
  alert: ['M12 3l10 18H2L12 3z', 'M12 10v5M12 18h.01'],
  money: ['M3 7h18v10H3z', 'M12 14a2 2 0 1 0 0-4 2 2 0 0 0 0 4z', 'M6 10h.01M18 14h.01'],
  crown: ['M3 8l4 4 5-7 5 7 4-4-2 11H5L3 8z'],
  plus: ['M12 5v14M5 12h14'],
  refresh: ['M21 12a9 9 0 1 1-3-6.7L21 8', 'M21 3v5h-5'],
  user: ['M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2', 'M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z'],
  flag: ['M4 21V4', 'M4 4h13l-2 4 2 4H4'],
  route: ['M6 19a2 2 0 1 0 0-4 2 2 0 0 0 0 4z', 'M18 9a2 2 0 1 0 0-4 2 2 0 0 0 0 4z', 'M8 17h6a3 3 0 0 0 0-6h-4a3 3 0 0 1 0-6h6'],
  help: ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z', 'M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.4-1 .9-1 1.7', 'M12 17h.01'],
  shield: ['M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z'],
  signal: ['M2 12a15 15 0 0 1 20 0', 'M5.5 15.5a10 10 0 0 1 13 0', 'M9 19a5 5 0 0 1 6 0'],
};

export function Ico({ name, size = 18, className }: { name: string; size?: number; className?: string }) {
  const d = PATHS[name] ?? PATHS.help;
  return (
    <svg className={className} width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {d.map((p) => <path key={p} d={p} />)}
    </svg>
  );
}

// ---- vehicle picture -----------------------------------------------------------------------------------------
const imageBase = () => (window as unknown as { __veylVehicleImages?: string }).__veylVehicleImages ?? 'nui://veyl_vehicles/web/images';
export function CarImage({ model, className }: { model?: string; className?: string }) {
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [model]);
  if (!model || failed || !/^[a-z0-9_]+$/i.test(model)) return <span className={cx('bst-car-fallback', className)}><Ico name="car" size={34} /></span>;
  return <img className={cx('bst-car', className)} src={`${imageBase()}/${model.toLowerCase()}.webp`} alt="" draggable={false} onError={() => setFailed(true)} />;
}

// ---- small pieces ----------------------------------------------------------------------------------------------
export function Badge({ children, tone }: { children: ReactNode; tone?: 'standard' | 'premium' | 'high' | 'timed' | 'crew' | 'event' | 'ok' | 'warn' | 'bad' | 'mute' }) {
  return <span className={cx('bst-badge', tone)}>{children}</span>;
}

export const badgeTone = (badge: string) =>
  badge === 'HIGH RISK' ? 'high' : badge === 'PREMIUM' ? 'premium' : badge === 'TIMED' ? 'timed' : badge === 'CREW' ? 'crew' : badge === 'EVENT' ? 'event' : 'standard';

export function Bar({ value, color, className, label }: { value: number; color?: string; className?: string; label?: string }) {
  const pct = Math.max(0, Math.min(1, value)) * 100;
  return <div className={cx('bst-bar', className)} role="progressbar" aria-valuenow={Math.round(pct)} aria-valuemin={0} aria-valuemax={100} aria-label={label}><i style={{ width: `${pct}%`, ...(color ? { background: color } : {}) } as CSSProperties} /></div>;
}

export function Button({ children, onClick, kind = 'plain', disabled, block, title }: { children: ReactNode; onClick?: () => void; kind?: 'primary' | 'plain' | 'danger' | 'ghost'; disabled?: boolean; block?: boolean; title?: string }) {
  return <button className={cx('bst-btn', kind, block && 'block')} onClick={onClick} disabled={disabled} title={title}>{children}</button>;
}

export function Empty({ icon, title, text }: { icon: string; title: string; text?: string }) {
  return <div className="bst-empty"><Ico name={icon} size={30} /><strong>{title}</strong>{text && <span>{text}</span>}</div>;
}

export function Loading({ text = 'Loading' }: { text?: string }) {
  return <div className="bst-loading" role="status"><span className="bst-spinner" />{text}</div>;
}

export function ErrorBox({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return <div className="bst-error" role="alert"><Ico name="alert" size={22} /><strong>Something went wrong</strong><span>{message}</span>{onRetry && <Button onClick={onRetry}>Try again</Button>}</div>;
}

/** A modal that asks first. Escape or a click outside cancels it (and does not close the tablet). */
export function Confirm({ title, text, confirm, danger, onConfirm, onCancel }: { title: string; text: string; confirm: string; danger?: boolean; onConfirm: () => void; onCancel: () => void }) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.stopPropagation(); e.preventDefault(); onCancel(); } };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, [onCancel]);
  return (
    <div className="bst-modal-bg" onMouseDown={onCancel}>
      <div className="bst-modal small" role="alertdialog" aria-label={title} onMouseDown={(e) => e.stopPropagation()}>
        <h3>{title}</h3>
        <p>{text}</p>
        <div className="bst-modal-actions"><Button kind="ghost" onClick={onCancel}>Keep it</Button><Button kind={danger ? 'danger' : 'primary'} onClick={onConfirm}>{confirm}</Button></div>
      </div>
    </div>
  );
}

export function Modal({ title, onClose, children, wide }: { title: string; onClose: () => void; children: ReactNode; wide?: boolean }) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.stopPropagation(); e.preventDefault(); onClose(); } };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, [onClose]);
  return (
    <div className="bst-modal-bg" onMouseDown={onClose}>
      <div className={cx('bst-modal', wide && 'wide')} role="dialog" aria-label={title} onMouseDown={(e) => e.stopPropagation()}>
        <div className="bst-modal-head"><h3>{title}</h3><button className="bst-icon" onClick={onClose} aria-label="Close"><Ico name="x" size={16} /></button></div>
        {children}
      </div>
    </div>
  );
}

// ---- time -------------------------------------------------------------------------------------------------------
/** Seconds remaining until `until` (a server timestamp), corrected by the offset between the server clock and this one. */
export function useCountdown(until: number | undefined, serverNow: number) {
  const [offset] = useState(() => serverNow - Math.floor(Date.now() / 1000));
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000) + offset);
  useEffect(() => {
    const t = window.setInterval(() => setNow(Math.floor(Date.now() / 1000) + offset), 1000);
    return () => window.clearInterval(t);
  }, [offset]);
  return until ? Math.max(0, until - now) : 0;
}

export const mmss = (s: number) => `${Math.floor(s / 60).toString().padStart(2, '0')}:${(s % 60).toString().padStart(2, '0')}`;

export function ago(at: number, now = Math.floor(Date.now() / 1000)) {
  const s = Math.max(0, now - at);
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86400)}d ago`;
}

export function Toast({ toast }: { toast: { kind: 'ok' | 'error'; text: string } | null }) {
  if (!toast) return null;
  return <div className={cx('bst-toast', toast.kind)} role="status"><Ico name={toast.kind === 'ok' ? 'check' : 'alert'} size={16} />{toast.text}</div>;
}
