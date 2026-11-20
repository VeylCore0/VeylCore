import type { ReactNode } from 'react';

export function Panel({ title, subtitle, onClose, children, footer, width }: {
  title?: ReactNode;
  subtitle?: ReactNode;
  onClose?: () => void;
  children: ReactNode;
  footer?: ReactNode;
  width?: number;
}) {
  return (
    <div className="v-panel" style={{ width: width ? `min(${width}px, 94vw)` : undefined, display: 'flex', flexDirection: 'column', maxHeight: '86vh' }}>
      {(title || onClose) && (
        <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', padding: '16px 16px 8px', gap: 8 }}>
          <div>
            {title && <div style={{ fontSize: 17, fontWeight: 600 }}>{title}</div>}
            {subtitle && <div className="v-muted" style={{ fontSize: 13, marginTop: 2 }}>{subtitle}</div>}
          </div>
          {onClose && (
            <button className="v-btn" aria-label="Close" style={{ padding: '2px 10px' }} onClick={onClose}>
              Esc
            </button>
          )}
        </div>
      )}
      <div style={{ padding: '8px 16px', overflowY: 'auto' }}>{children}</div>
      {footer && <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, padding: '8px 16px 16px' }}>{footer}</div>}
    </div>
  );
}

export function KeyBadge({ children }: { children: ReactNode }) {
  return <span className="v-key">{children}</span>;
}

export type Tone = 'info' | 'success' | 'warning' | 'error';

export const toneColor: Record<Tone, string> = {
  info: 'var(--v-accent)',
  success: 'var(--v-success)',
  warning: 'var(--v-warning)',
  error: 'var(--v-error)',
};

/** Status colours are always paired with an icon/text (never colour alone). */
export const toneIcon: Record<Tone, string> = { info: 'ℹ', success: '✓', warning: '!', error: '✕' };
