import { useState, type ReactNode } from 'react';
import { Icon, VMark } from './icons';
import { t } from './i18n';

export function Panel({ title, subtitle, onClose, children, footer, width }: {
  title?: ReactNode; subtitle?: ReactNode; onClose?: () => void; children: ReactNode; footer?: ReactNode; width?: number;
}) {
  return (
    <div className="v-panel" style={{ width: width ? `min(${width}px, 94vw)` : undefined, display: 'flex', flexDirection: 'column', maxHeight: '86vh' }}>
      {(title || onClose) && (
        <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', padding: '16px 16px 8px', gap: 8 }}>
          <div>
            {title && <div style={{ fontSize: 17, fontWeight: 600 }}>{title}</div>}
            {subtitle && <div className="v-muted" style={{ fontSize: 13, marginTop: 2 }}>{subtitle}</div>}
          </div>
          {onClose && <CloseHint onClose={onClose} />}
        </div>
      )}
      <div style={{ padding: '8px 16px' }} className="v-scroll">{children}</div>
      {footer && <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, padding: '8px 16px 16px' }}>{footer}</div>}
    </div>
  );
}

export function KeyBadge({ children }: { children: ReactNode }) {
  return <span className="v-key">{children}</span>;
}

/** "V  VEYLCORE | SECTION" one-line brand used on shop/bank headers. */
export function BrandHeader({ section }: { section: string }) {
  return (
    <div className="v-brand">
      <VMark size="1.5rem" />
      <span>VEYLCORE</span>
      <span className="sep" />
      <span className="section">{section.toUpperCase()}</span>
    </div>
  );
}

/** Stacked brand used on the inventory: V mark, divider, VEYLCORE over a section name. */
export function BrandStack({ section }: { section: string }) {
  return (
    <div className="v-brand-stack">
      <VMark size="2.4rem" />
      <span className="divider" />
      <div>
        <div className="name">VEYLCORE</div>
        <div className="sub">{section.toUpperCase()}</div>
      </div>
    </div>
  );
}

export function CloseHint({ onClose }: { onClose: () => void }) {
  return (
    <button className="v-close" onClick={onClose} aria-label={t('common.close')}>
      <span className="v-key">ESC</span>
      <span>{t('common.close')}</span>
    </button>
  );
}

export function SearchBox({ value, onChange, placeholder }: { value: string; onChange: (v: string) => void; placeholder: string }) {
  return (
    <label className="v-search">
      <Icon name="search" size="1rem" />
      <input className="v-input" value={value} placeholder={placeholder} maxLength={40} onChange={(e) => onChange(e.target.value)} />
    </label>
  );
}

export function Stepper({ value, min = 0, max, onChange, disabled }: { value: number; min?: number; max: number; onChange: (v: number) => void; disabled?: boolean }) {
  return (
    <span className="v-stepper">
      <button aria-label={t('common.decrease')} disabled={disabled || value <= min} onClick={() => onChange(value - 1)}><Icon name="minus" size="0.9rem" /></button>
      <span>{value}</span>
      <button aria-label={t('common.increase')} disabled={disabled || value >= max} onClick={() => onChange(value + 1)}><Icon name="plus" size="0.9rem" /></button>
    </span>
  );
}

export function Tabs<T extends string>({ tabs, value, onChange }: { tabs: { id: T; label: string }[]; value: T; onChange: (v: T) => void }) {
  return (
    <div className="v-tabs" role="tablist">
      {tabs.map((tab) => (
        <button key={tab.id} role="tab" aria-selected={tab.id === value} className={`v-tab${tab.id === value ? ' active' : ''}`} onClick={() => onChange(tab.id)}>
          {tab.label}
        </button>
      ))}
    </div>
  );
}

export function RadioCard({ label, active, onSelect, disabled }: { label: string; active: boolean; onSelect: () => void; disabled?: boolean }) {
  return (
    <button role="radio" aria-checked={active} className={`v-radio${active ? ' active' : ''}`} onClick={onSelect} disabled={disabled}>
      <span className="dot" /><span>{label}</span>
    </button>
  );
}

export function StateView({ kind, message, onRetry }: { kind: 'loading' | 'empty' | 'error' | 'restricted'; message?: string; onRetry?: () => void }) {
  return (
    <div className={`v-state${kind === 'error' ? ' error' : ''}`} role={kind === 'error' ? 'alert' : 'status'}>
      {kind === 'loading' ? <span className="v-spinner" /> : <Icon name={kind === 'error' ? 'alert' : kind === 'restricted' ? 'lock' : 'box'} size="1.6rem" />}
      <span>{message ?? t(`state.${kind}`)}</span>
      {onRetry && <button className="v-btn" onClick={onRetry}>{t('common.retry')}</button>}
    </div>
  );
}

/** Item thumbnail with a deliberate fallback (icon tile) when the image is missing. */
export function ItemImage({ src, alt, size }: { src?: string; alt: string; size: string }) {
  const [failed, setFailed] = useState(false);
  if (!src || failed) {
    return (
      <span className="v-item-fallback" style={{ width: size, height: size }} title={alt}>
        <Icon name="box" size="55%" />
      </span>
    );
  }
  return <img src={src} alt={alt} draggable={false} style={{ width: size, height: size, objectFit: 'contain' }} onError={() => setFailed(true)} />;
}

export type Tone = 'info' | 'success' | 'warning' | 'error';
export const toneColor: Record<Tone, string> = { info: 'var(--accent)', success: 'var(--success)', warning: 'var(--warning)', error: 'var(--danger)' };
export const toneIcon: Record<Tone, string> = { info: 'ℹ', success: '✓', warning: '!', error: '✕' };

export const money = (n: number | undefined | null, cents = false) =>
  `${(n ?? 0) < 0 ? '-' : ''}$${Math.abs(n ?? 0).toLocaleString('en-US', { minimumFractionDigits: cents ? 2 : 0, maximumFractionDigits: cents ? 2 : 0 })}`;

export const kg = (g: number) => `${(g / 1000).toFixed(1)}`;
