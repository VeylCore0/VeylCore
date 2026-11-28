import { useEffect, useState, type CSSProperties, type ReactNode } from 'react';
import { nui, type NuiResponse } from '@veyl/ui';

export const api = <T = unknown>(name: string, ...args: unknown[]) => nui<T>('api', { name, args }) as Promise<NuiResponse<T>>;
export const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(' ');
export const usd = (n: number) => `$${Math.round(n).toLocaleString('en-US')}`;

const PATHS: Record<string, string[]> = {
  dashboard: ['M3 11l9-8 9 8', 'M5 10v10h5v-6h4v6h5V10'],
  leaf: ['M5 19c0-9 6-14 15-14 0 9-5 15-14 15', 'M5 19c3-5 6-8 10-10'],
  gear: ['M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z', 'M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z'],
  home: ['M3 10l9-7 9 7v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V10z', 'M9 21v-7h6v7'],
  star: ['M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9L12 3z'],
  chart: ['M4 20V10M10 20V4M16 20v-8M22 20H2'],
  x: ['M18 6L6 18M6 6l12 12'],
  check: ['M20 6L9 17l-5-5'],
  plus: ['M12 5v14M5 12h14'],
  lock: ['M6 11V8a6 6 0 0 1 12 0v3', 'M5 11h14v10H5z'],
  unlock: ['M6 11V8a6 6 0 0 1 11-3.2', 'M5 11h14v10H5z'],
  alert: ['M12 3l10 18H2L12 3z', 'M12 10v5M12 18h.01'],
  clock: ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z', 'M12 7v5l3 2'],
  box: ['M21 8l-9-5-9 5 9 5 9-5z', 'M3 8v8l9 5 9-5V8', 'M12 13v8'],
  bag: ['M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z', 'M3 6h18', 'M16 10a4 4 0 0 1-8 0'],
  money: ['M3 7h18v10H3z', 'M12 14a2 2 0 1 0 0-4 2 2 0 0 0 0 4z'],
  users: ['M17 20v-1.5a3.5 3.5 0 0 0-3.5-3.5h-5A3.5 3.5 0 0 0 5 18.5V20', 'M11 12a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7z', 'M19 20v-1.5a3 3 0 0 0-2-2.8'],
  pin: ['M21 10c0 7-9 13-9 13S3 17 3 10a9 9 0 0 1 18 0z', 'M12 13a3 3 0 1 0 0-6 3 3 0 0 0 0 6z'],
  shield: ['M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z'],
  drop: ['M12 3s6 6.5 6 11a6 6 0 0 1-12 0c0-4.5 6-11 6-11z'],
  bolt: ['M13 3L5 13h6l-1 8 8-10h-6z'],
  trash: ['M3 6h18', 'M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6', 'M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2'],
  key: ['M21 2l-2 2m-7.6 7.6a5.5 5.5 0 1 1-7.8 7.8 5.5 5.5 0 0 1 7.8-7.8z', 'M15.5 7.5l3 3L22 7l-3-3'],
  arrow: ['M5 12h14M13 6l6 6-6 6'],
  info: ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z', 'M12 16v-5M12 8h.01'],
};

export function Ico({ name, size = 18 }: { name: string; size?: number }) {
  const d = PATHS[name] ?? PATHS.info;
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{d.map((p) => <path key={p} d={p} />)}</svg>;
}

const imageBase = () => (window as unknown as { __veylItemImages?: string }).__veylItemImages ?? 'nui://veyl_inventory/web/images';
export function ItemImg({ item, size = 40 }: { item: string; size?: number }) {
  const [bad, setBad] = useState(false);
  if (bad) return <span className="pr-itemfb" style={{ width: size, height: size }}><Ico name="box" size={size * 0.5} /></span>;
  return <img className="pr-item" width={size} height={size} src={`${imageBase()}/${item}.png`} alt="" draggable={false} onError={() => setBad(true)} />;
}

export function Bar({ value, color, label }: { value: number; color?: string; label?: string }) {
  const pct = Math.max(0, Math.min(1, value)) * 100;
  return <div className="pr-bar" role="progressbar" aria-valuenow={Math.round(pct)} aria-valuemin={0} aria-valuemax={100} aria-label={label}><i style={{ width: `${pct}%`, ...(color ? { background: color } : {}) } as CSSProperties} /></div>;
}

export function Button({ children, onClick, kind = 'plain', disabled, block, title }: { children: ReactNode; onClick?: () => void; kind?: 'primary' | 'plain' | 'danger' | 'ghost'; disabled?: boolean; block?: boolean; title?: string }) {
  return <button className={cx('pr-btn', kind, block && 'block')} onClick={onClick} disabled={disabled} title={title}>{children}</button>;
}

export function Empty({ icon, title, text }: { icon: string; title: string; text?: string }) {
  return <div className="pr-empty"><Ico name={icon} size={28} /><strong>{title}</strong>{text && <span>{text}</span>}</div>;
}
export function Loading({ text = 'Loading' }: { text?: string }) { return <div className="pr-loading" role="status"><span className="pr-spinner" />{text}</div>; }
export function ErrorBox({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return <div className="pr-error" role="alert"><Ico name="alert" size={22} /><strong>Something went wrong</strong><span>{message}</span>{onRetry && <Button onClick={onRetry}>Try again</Button>}</div>;
}
export function Chip({ children, tone }: { children: ReactNode; tone?: 'ok' | 'warn' | 'bad' | 'accent' | 'mute' }) { return <span className={cx('pr-chip', tone)}>{children}</span>; }

function useEscape(onEscape: () => void) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.stopPropagation(); e.preventDefault(); onEscape(); } };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, [onEscape]);
}

export function Modal({ title, onClose, children, wide }: { title: string; onClose: () => void; children: ReactNode; wide?: boolean }) {
  useEscape(onClose);
  return (
    <div className="pr-modal-bg" onMouseDown={onClose}>
      <div className={cx('pr-modal', wide && 'wide')} role="dialog" aria-label={title} onMouseDown={(e) => e.stopPropagation()}>
        <div className="pr-modal-head"><h3>{title}</h3><button className="pr-icon" onClick={onClose} aria-label="Close"><Ico name="x" size={16} /></button></div>
        {children}
      </div>
    </div>
  );
}

export function Confirm({ title, text, confirm, danger, onConfirm, onCancel }: { title: string; text: string; confirm: string; danger?: boolean; onConfirm: () => void; onCancel: () => void }) {
  useEscape(onCancel);
  return (
    <div className="pr-modal-bg" onMouseDown={onCancel}>
      <div className="pr-modal small" role="alertdialog" aria-label={title} onMouseDown={(e) => e.stopPropagation()}>
        <h3>{title}</h3><p>{text}</p>
        <div className="pr-modal-actions"><Button kind="ghost" onClick={onCancel}>Cancel</Button><Button kind={danger ? 'danger' : 'primary'} onClick={onConfirm}>{confirm}</Button></div>
      </div>
    </div>
  );
}

export function Toast({ toast }: { toast: { kind: 'ok' | 'error'; text: string } | null }) {
  if (!toast) return null;
  return <div className={cx('pr-toast', toast.kind)} role="status"><Ico name={toast.kind === 'ok' ? 'check' : 'alert'} size={16} />{toast.text}</div>;
}

/** Seconds until a server timestamp, corrected for the difference between the server clock and this one. */
export function useClock(serverNow: number) {
  const [offset] = useState(() => serverNow - Math.floor(Date.now() / 1000));
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000) + offset);
  useEffect(() => { const t = window.setInterval(() => setNow(Math.floor(Date.now() / 1000) + offset), 1000); return () => window.clearInterval(t); }, [offset]);
  return now;
}
export const mmss = (s: number) => `${Math.floor(Math.max(0, s) / 60).toString().padStart(2, '0')}:${Math.floor(Math.max(0, s) % 60).toString().padStart(2, '0')}`;
export function ago(at: number, now = Math.floor(Date.now() / 1000)) {
  const s = Math.max(0, now - at);
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86400)}d ago`;
}

/** Item names for places that have no server state to read them from (the bench page). The tablet gets the same list from the server. */
export const ITEM_LABELS: Record<string, string> = {
  prod_seed_ember: 'Emberleaf Seeds', prod_seed_violet: 'Violetbloom Seeds', prod_seed_azure: 'Azurefern Seeds', prod_planter: 'Planter', prod_water: 'Clean Water',
  prod_nutrient: 'Growth Tonic', prod_leaf: 'Fresh Leaves', prod_blend: 'Leaf Blend', prod_pack: 'Packed Product', prod_wild_herb: 'Wild Herbs', prod_workstation: 'Prep Table', prod_access_card: 'Lab Access Card',
};
