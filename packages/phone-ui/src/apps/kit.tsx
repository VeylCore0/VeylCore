// Small pieces the apps share: a loader hook, money formatting, chips, meters, a floating action button.
import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import type { Res } from '../api';
import { Ico } from '../icons';
import { Failure, Spinner, cx } from '../ui';

export const usd = (n: number | undefined | null) => `${(n ?? 0) < 0 ? '-' : ''}$${Math.abs(Math.round(n ?? 0)).toLocaleString('en-US')}`;

/** Loads data from the server once, with loading / error state and a reload. */
export function useLoad<T>(fn: () => Promise<Res<T>>) {
  const [data, setData] = useState<T | null>(null);
  const [err, setErr] = useState<Res<T> | null>(null);
  const [loading, setLoading] = useState(true);
  const ref = useRef(fn);
  ref.current = fn;
  const reload = useCallback(async () => {
    setLoading(true);
    const r = await ref.current();
    if (r.ok && r.data !== undefined) { setData(r.data); setErr(null); } else setErr(r);
    setLoading(false);
  }, []);
  useEffect(() => { void reload(); }, [reload]);
  return { data, err, loading, reload, setData };
}

/** Spinner on first load, an error with Try again, otherwise the content. */
export function Loaded<T>({ data, err, loading, reload, children }: { data: T | null; err: Res<T> | null; loading: boolean; reload: () => void; children: (d: T) => ReactNode }) {
  if (data) return <>{children(data)}</>;
  if (loading) return <Spinner />;
  return <Failure res={err} onRetry={reload} />;
}

export function Chip({ children, tone, icon, active, onClick }: { children: ReactNode; tone?: 'ok' | 'warn' | 'bad' | 'accent'; icon?: string; active?: boolean; onClick?: () => void }) {
  const inner = <>{icon && <Ico name={icon} size={12} />}{children}</>;
  return onClick
    ? <button className={cx('ph-chip2', tone, active && 'on')} onClick={onClick}>{inner}</button>
    : <span className={cx('ph-chip2', tone, active && 'on')}>{inner}</span>;
}

export function Meter({ value, icon, label }: { value: number; icon?: string; label?: string }) {
  const v = Math.max(0, Math.min(100, Math.round(value)));
  return (
    <span className={cx('ph-meter2', v < 25 ? 'bad' : v < 50 ? 'warn' : 'ok')} title={label ? `${label} ${v}%` : `${v}%`}>
      {icon && <Ico name={icon} size={12} />}<i><b style={{ width: `${v}%` }} /></i>
    </span>
  );
}

export function Fab({ icon = 'plus', label, onClick }: { icon?: string; label: string; onClick: () => void }) {
  return <button className="ph-fab" onClick={onClick} aria-label={label} title={label}><Ico name={icon} size={24} stroke={2.4} /></button>;
}

/** Relative time: "now", "5 min", "3 h", "2 d". */
export function ago(ts: number) {
  const s = Math.max(0, Math.floor(Date.now() / 1000) - ts);
  if (s < 60) return 'now';
  if (s < 3600) return `${Math.floor(s / 60)} min`;
  if (s < 86400) return `${Math.floor(s / 3600)} h`;
  return `${Math.floor(s / 86400)} d`;
}

export const clientOp = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`;
