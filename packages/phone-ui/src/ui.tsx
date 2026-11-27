// Shared phone primitives: avatars, app icons, sheets, toggles, sliders, headers, toasts.
import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { Ico } from './icons';
import { avatarBg, initials, shade } from './format';
import { useBack } from './nav';
import type { Res } from './api';

export const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(' ');

/** Built-in app look: glyph + colour. External apps bring their own colour and icon hint. */
export const APP_LOOK: Record<string, { icon: string; color: string }> = {
  phone: { icon: 'phone', color: '#2fc473' },
  messages: { icon: 'chat', color: '#6a6cf0' },
  contacts: { icon: 'users', color: '#d98a45' },
  settings: { icon: 'sliders', color: '#6f7585' },
  mail: { icon: 'mail', color: '#2b9ee8' },
  store: { icon: 'bag', color: '#3a7bf0' },
  calculator: { icon: 'calc', color: '#f08a2a' },
  clock: { icon: 'clock', color: '#2a2c36' },
};

export function AppIcon({ icon, color, size = 58, badge }: { icon: string; color: string; size?: number; badge?: number }) {
  const style: CSSProperties = {
    width: size, height: size, borderRadius: size * 0.27,
    background: `linear-gradient(155deg, ${shade(color, 0.28)} 0%, ${color} 55%, ${shade(color, -0.28)} 100%)`,
  };
  return (
    <span className="ph-appicon" style={style}>
      <Ico name={icon} size={size * 0.5} stroke={1.8} />
      {!!badge && badge > 0 && <span className="ph-badge">{badge > 99 ? '99+' : badge}</span>}
    </span>
  );
}

export function Avatar({ name, size = 44, group, id }: { name: string; size?: number; group?: boolean; id?: string }) {
  const ini = initials(name);
  return (
    <span className="ph-avatar" style={{ width: size, height: size, fontSize: size * 0.38, background: avatarBg(id ?? name) }}>
      {group ? <Ico name="users" size={size * 0.5} /> : ini || <Ico name="user" size={size * 0.52} />}
    </span>
  );
}

/** App header: large title with an optional back action and trailing actions. */
export function Header({ title, onBack, backLabel, right, large = true }: { title?: string; onBack?: () => void; backLabel?: string; right?: ReactNode; large?: boolean }) {
  return (
    <header className={cx('ph-header', large && 'large')}>
      <div className="ph-header-row">
        {onBack ? <button className="ph-back" onClick={onBack}><Ico name="back" size={22} stroke={2.2} /><span>{backLabel ?? 'Back'}</span></button> : <span />}
        <div className="ph-header-right">{right}</div>
      </div>
      {title && <h1>{title}</h1>}
    </header>
  );
}

export function IconButton({ icon, onClick, label, tone, size = 20, disabled }: { icon: string; onClick?: () => void; label: string; tone?: 'accent' | 'danger'; size?: number; disabled?: boolean }) {
  return <button className={cx('ph-iconbtn', tone)} onClick={onClick} aria-label={label} title={label} disabled={disabled}><Ico name={icon} size={size} /></button>;
}

export function Button({ children, onClick, kind = 'plain', disabled, block, type }: { children: ReactNode; onClick?: () => void; kind?: 'primary' | 'plain' | 'danger' | 'ghost'; disabled?: boolean; block?: boolean; type?: 'button' | 'submit' }) {
  return <button type={type ?? 'button'} className={cx('ph-btn', `k-${kind}`, block && 'block')} onClick={onClick} disabled={disabled}>{children}</button>;
}

export function Toggle({ on, onChange, disabled, label }: { on: boolean; onChange: (v: boolean) => void; disabled?: boolean; label: string }) {
  return (
    <button role="switch" aria-checked={on} aria-label={label} className={cx('ph-toggle', on && 'on')} onClick={() => onChange(!on)} disabled={disabled}>
      <span />
    </button>
  );
}

export function Segmented<T extends string>({ options, value, onChange }: { options: { id: T; label: string; icon?: string }[]; value: T; onChange: (v: T) => void }) {
  return (
    <div className="ph-seg" role="tablist">
      {options.map((o) => (
        <button key={o.id} role="tab" aria-selected={o.id === value} className={cx(o.id === value && 'on')} onClick={() => onChange(o.id)}>
          {o.icon && <Ico name={o.icon} size={15} />}{o.label}
        </button>
      ))}
    </div>
  );
}

export function Slider({ value, min = 0, max = 100, onChange, onCommit, label }: { value: number; min?: number; max?: number; onChange: (v: number) => void; onCommit?: (v: number) => void; label: string }) {
  const pct = ((value - min) / (max - min)) * 100;
  return (
    <input className="ph-slider" type="range" min={min} max={max} value={value} aria-label={label} style={{ '--p': `${pct}%` } as CSSProperties}
      onChange={(e) => onChange(Number(e.target.value))}
      onPointerUp={(e) => onCommit?.(Number((e.target as HTMLInputElement).value))}
      onKeyUp={(e) => onCommit?.(Number((e.target as HTMLInputElement).value))} />
  );
}

/** Text input that tells the game when it has focus (so W/A/S/D don't move the player while typing). */
export function TextInput(props: { value: string; onChange: (v: string) => void; placeholder?: string; maxLength?: number; inputMode?: 'numeric' | 'text' | 'tel'; autoFocus?: boolean; onEnter?: () => void; className?: string; label?: string; multiline?: boolean; type?: 'text' | 'password' }) {
  const { value, onChange, placeholder, maxLength, inputMode, autoFocus, onEnter, className, label, multiline, type } = props;
  const ref = useRef<HTMLInputElement & HTMLTextAreaElement>(null);
  useEffect(() => { if (autoFocus) ref.current?.focus({ preventScroll: true }); }, [autoFocus]);
  // If this field unmounts while focused, release the typing lock.
  useEffect(() => () => { if (document.activeElement === ref.current) void typing(false); }, []);
  const common = {
    ref, value, placeholder, maxLength, inputMode, type, 'aria-label': label ?? placeholder, className: cx('ph-input', className), spellCheck: false, autoComplete: 'off',
    onChange: (e: { target: { value: string } }) => onChange(e.target.value),
    onFocus: () => void typing(true), onBlur: () => void typing(false),
  };
  return multiline
    ? <textarea {...common} rows={3} />
    : <input {...common} onKeyDown={(e) => { if (e.key === 'Enter') onEnter?.(); }} />;
}
import { post } from './api';
const typing = (t: boolean) => post('ui:typing', { typing: t });

export function SearchField({ value, onChange, placeholder = 'Search' }: { value: string; onChange: (v: string) => void; placeholder?: string }) {
  return (
    <label className="ph-search">
      <Ico name="search" size={16} />
      <TextInput value={value} onChange={onChange} placeholder={placeholder} />
      {value && <button className="ph-search-x" onClick={() => onChange('')} aria-label="Clear"><Ico name="x" size={14} /></button>}
    </label>
  );
}

/** A bottom sheet that sits inside the phone screen. Escape / back closes it first. */
export function Sheet({ title, onClose, children, actions }: { title?: string; onClose: () => void; children: ReactNode; actions?: ReactNode }) {
  useBack(true, () => { onClose(); return true; });
  return (
    <div className="ph-sheet-wrap">
      <div className="ph-sheet-dim" onClick={onClose} />
      <div className="ph-sheet" role="dialog" aria-label={title}>
        <div className="ph-sheet-grab" />
        {(title || actions) && <div className="ph-sheet-head"><h3>{title}</h3><div>{actions}</div></div>}
        <div className="ph-sheet-body">{children}</div>
      </div>
    </div>
  );
}

export function Group({ title, children, footer }: { title?: string; children: ReactNode; footer?: string }) {
  return (
    <section className="ph-group">
      {title && <h4>{title}</h4>}
      <div className="ph-group-card">{children}</div>
      {footer && <p className="ph-group-foot">{footer}</p>}
    </section>
  );
}

export function Row({ icon, iconColor, title, sub, right, onClick, danger, chevron }: { icon?: string; iconColor?: string; title: ReactNode; sub?: ReactNode; right?: ReactNode; onClick?: () => void; danger?: boolean; chevron?: boolean }) {
  const inner = (
    <>
      {icon && <span className="ph-row-icon" style={{ background: iconColor ?? 'var(--ph-fill-2)' }}><Ico name={icon} size={16} /></span>}
      <span className="ph-row-main"><span className={cx('ph-row-title', danger && 'danger')}>{title}</span>{sub && <span className="ph-row-sub">{sub}</span>}</span>
      {right && <span className="ph-row-right">{right}</span>}
      {chevron && <Ico name="forward" size={16} style={{ opacity: 0.4 }} />}
    </>
  );
  return onClick ? <button className="ph-row" onClick={onClick}>{inner}</button> : <div className="ph-row">{inner}</div>;
}

export function Empty({ icon, title, text, action }: { icon: string; title: string; text?: string; action?: ReactNode }) {
  return (
    <div className="ph-empty">
      <span><Ico name={icon} size={30} stroke={1.5} /></span>
      <strong>{title}</strong>
      {text && <p>{text}</p>}
      {action}
    </div>
  );
}

export function Spinner() { return <div className="ph-spinner" role="status" aria-label="Loading" />; }

export function Failure({ res, onRetry }: { res?: Res<unknown> | null; onRetry?: () => void }) {
  return (
    <div className="ph-empty">
      <span className="warn"><Ico name="x" size={26} /></span>
      <strong>Something went wrong</strong>
      <p>{res?.message ?? 'Could not load this right now.'}</p>
      {onRetry && <Button onClick={onRetry}>Try again</Button>}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Toasts (one small line at the bottom of the screen)
// ---------------------------------------------------------------------------
type Toast = { id: number; text: string; kind: 'ok' | 'error' };
let toasts: Toast[] = [];
let toastSeq = 0;
const toastListeners = new Set<() => void>();
export function toast(text: string, kind: 'ok' | 'error' = 'ok') {
  const t = { id: ++toastSeq, text, kind };
  toasts = [...toasts.slice(-1), t];
  toastListeners.forEach((l) => l());
  window.setTimeout(() => { toasts = toasts.filter((x) => x.id !== t.id); toastListeners.forEach((l) => l()); }, 2800);
}
/** Shows a server answer: errors always, successes only when the server sent a message. */
export function say(res: Res<unknown>) {
  if (!res.ok) toast(res.message ?? 'That did not work', 'error');
  else if (res.message) toast(res.message, 'ok');
  return res.ok;
}
export function ToastHost() {
  const [, force] = useState(0);
  useEffect(() => { const l = () => force((n) => n + 1); toastListeners.add(l); return () => { toastListeners.delete(l); }; }, []);
  return <div className="ph-toasts" aria-live="polite">{toasts.map((t) => <div key={t.id} className={cx('ph-toast', t.kind)}>{t.text}</div>)}</div>;
}
