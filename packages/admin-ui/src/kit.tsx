import { useState, type ReactNode } from 'react';
import { nui, type NuiResponse } from '@veyl/ui';

export interface Overview {
  players: number; inCity: number; max: number; uptime: number; resources: number; reports: number; bans: number;
  world: { hour?: number; minute?: number; weather?: string; frozen?: boolean }; me: { id: number; name: string };
  weather: string[]; jobs: { id: string; label: string }[]; gangs: { id: string; label: string }[];
}
export interface SelfState { noclip: boolean; god: boolean; invisible: boolean; names: boolean; spectating: boolean; speed: number }
export interface PlayerRow { id: number; name: string; character?: string; citizenid?: string; ping: number; job?: string; staff: boolean }
export interface PlayerInfo {
  id: number; name: string; character?: string; citizenid?: string; ping: number; staff: boolean;
  identifiers: Record<string, string | undefined>; money?: Record<string, number>; job?: { label?: string; name?: string; grade?: { name?: string; level?: number } | number };
  gang?: { label?: string; name?: string }; coords?: { x: number; y: number; z: number }; health?: number; armor?: number;
  items: { name: string; label?: string; count: number }[]; warnings: { id: number; reason: string; issued_by: string; at: string }[];
}

export const api = <T = unknown>(name: string, ...args: unknown[]) => nui<T>('api', { name, args }) as Promise<NuiResponse<T>>;
export const tool = (kind: string, value?: unknown, extra?: unknown) => nui<{ state: SelfState; copy?: string }>('tool', { kind, value, extra }) as Promise<NuiResponse<{ state: SelfState; copy?: string }>>;
export const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(' ');
export const usd = (n: number) => `$${Math.round(n).toLocaleString('en-US')}`;
export const uptime = (s: number) => { const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60); return h > 0 ? `${h}h ${m}m` : `${m}m`; };

const P: Record<string, string[]> = {
  home: ['M3 11l9-8 9 8', 'M5 10v10h5v-6h4v6h5V10'],
  users: ['M17 20v-1.5a3.5 3.5 0 0 0-3.5-3.5h-5A3.5 3.5 0 0 0 5 18.5V20', 'M11 12a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7z', 'M19 20v-1.5a3 3 0 0 0-2-2.8'],
  user: ['M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2', 'M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z'],
  car: ['M5 17h14M3 13l2-6h14l2 6v4H3z', 'M7 17v2M17 17v2'],
  globe: ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z', 'M3 12h18', 'M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18'],
  flag: ['M5 21V4', 'M5 4h12l-2 4 2 4H5'],
  ban: ['M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z', 'M5.6 5.6l12.8 12.8'],
  log: ['M6 3h12v18H6z', 'M9 8h6M9 12h6M9 16h4'],
  server: ['M4 4h16v6H4zM4 14h16v6H4z', 'M8 7h.01M8 17h.01'],
  x: ['M18 6L6 18M6 6l12 12'], search: ['M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16z', 'M21 21l-4.3-4.3'],
  bolt: ['M13 3L5 13h6l-1 8 8-10h-6z'], eye: ['M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z', 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z'],
  shield: ['M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z'], check: ['M20 6L9 17l-5-5'], alert: ['M12 3l10 18H2L12 3z', 'M12 10v5M12 18h.01'],
  pin: ['M21 10c0 7-9 13-9 13S3 17 3 10a9 9 0 0 1 18 0z', 'M12 13a3 3 0 1 0 0-6 3 3 0 0 0 0 6z'], megaphone: ['M3 11v2l13 5V6L3 11z', 'M16 8c3 0 5 1.8 5 4s-2 4-5 4'],
};
export function Ico({ name, size = 18 }: { name: string; size?: number }) {
  const d = P[name] ?? P.alert;
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{d.map((p) => <path key={p} d={p} />)}</svg>;
}

export function Card({ title, right, children }: { title?: string; right?: ReactNode; children: ReactNode }) {
  return <section className="ad-card">{(title || right) && <header><h3>{title}</h3>{right}</header>}{children}</section>;
}
export function Btn({ children, onClick, kind = 'plain', disabled, title }: { children: ReactNode; onClick?: () => void; kind?: 'plain' | 'primary' | 'danger' | 'ghost'; disabled?: boolean; title?: string }) {
  return <button className={cx('ad-btn', kind)} onClick={onClick} disabled={disabled} title={title}>{children}</button>;
}
export function Toggle({ on, label, hint, onClick }: { on: boolean; label: string; hint?: string; onClick: () => void }) {
  return (
    <button className={cx('ad-toggle', on && 'on')} onClick={onClick} role="switch" aria-checked={on}>
      <span><b>{label}</b>{hint && <small>{hint}</small>}</span><i><u /></i>
    </button>
  );
}
export function Empty({ text }: { text: string }) { return <div className="ad-empty">{text}</div>; }

/** A row of fields with one button: keeps the little action forms short. */
export function Form({ fields, action, kind = 'primary', onSubmit }: { fields: { key: string; label: string; type?: 'text' | 'number' | 'select'; options?: { value: string; label: string }[]; placeholder?: string; init?: string; wide?: boolean }[]; action: string; kind?: 'primary' | 'danger'; onSubmit: (v: Record<string, string>) => Promise<boolean | void> | void }) {
  const [v, setV] = useState<Record<string, string>>(() => Object.fromEntries(fields.map((f) => [f.key, f.init ?? (f.type === 'select' ? f.options?.[0]?.value ?? '' : '')])));
  const [busy, setBusy] = useState(false);
  const initial = () => Object.fromEntries(fields.map((f) => [f.key, f.init ?? (f.type === 'select' ? f.options?.[0]?.value ?? '' : '')]));
  const go = async () => { setBusy(true); const r = await onSubmit(v); setBusy(false); if (r === true) setV(initial()); };
  return (
    <form className="ad-form" onSubmit={(e) => { e.preventDefault(); void go(); }}>
      {fields.map((f) => (
        <label key={f.key} className={cx(f.wide && 'wide')}>
          <span>{f.label}</span>
          {f.type === 'select'
            ? <select value={v[f.key]} onChange={(e) => setV({ ...v, [f.key]: e.target.value })}>{f.options?.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}</select>
            : <input type={f.type ?? 'text'} value={v[f.key]} placeholder={f.placeholder} onChange={(e) => setV({ ...v, [f.key]: e.target.value })} />}
        </label>
      ))}
      <Btn kind={kind} disabled={busy}>{busy ? '…' : action}</Btn>
    </form>
  );
}
