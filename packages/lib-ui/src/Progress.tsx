import { useEffect, useRef, useState } from 'react';
import { Glyph, type UIConfig } from './glyphs';

export interface ActionStart {
  id: string; label: string; icon?: string; duration: number; color?: string; canCancel: boolean; cancelLabel: string;
  keyLabel?: string; subLabel?: string; completeLabel?: string; showComplete: boolean;
}
export interface ActionState extends ActionStart { kind: 'timed' | 'hold'; startedAt: number; progress?: number; result?: 'completed' | 'cancelled' }

/** Timed progress card: the bar and numbers are drawn from elapsed time (requestAnimationFrame), never from frame counts. */
export function ProgressCard({ a, cfg }: { a: ActionState; cfg?: UIConfig['Progress'] }) {
  const [now, setNow] = useState(performance.now());
  const raf = useRef(0);
  useEffect(() => {
    if (a.result) return;
    const tick = () => { setNow(performance.now()); raf.current = requestAnimationFrame(tick); };
    raf.current = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf.current);
  }, [a.id, a.result]);
  const done = a.result === 'completed';
  const frac = done ? 1 : Math.max(0, Math.min(1, (now - a.startedAt) / a.duration));
  const left = Math.max(0, (a.duration - (now - a.startedAt)) / 1000);
  const style = { bottom: `${cfg?.offsetY ?? 11}vh`, width: `${cfg?.width ?? 26}rem`, ...(a.color ? { '--vn-accent': a.color } : {}) } as React.CSSProperties;
  if (done && a.showComplete) {
    return (
      <div className={`vn-progress done${a.result ? ' ending' : ''}`} style={style} role="status">
        <span className="vn-tile ok"><Glyph name="check" /></span>
        <div className="vn-p-main"><div className="vn-p-label big">{a.completeLabel ?? `${a.label.replace(/…$|\.\.\.$/, '')} complete`}</div></div>
      </div>
    );
  }
  return (
    <div className={`vn-progress${a.result === 'cancelled' ? ' cancelled' : ''}`} style={style} role="progressbar" aria-valuenow={Math.round(frac * 100)} aria-valuemin={0} aria-valuemax={100} aria-label={a.label}>
      <span className="vn-tile"><Glyph name={a.icon ?? 'wrench'} /></span>
      <div className="vn-p-main">
        <div className="vn-p-top"><span className="vn-p-label">{a.label}</span><span className="vn-p-pct">{Math.round(frac * 100)}%</span></div>
        <div className="vn-p-track"><i style={{ width: `${frac * 100}%` }} /></div>
        <div className="vn-p-bottom">
          <span>{a.result === 'cancelled' ? 'Cancelled' : `${left.toFixed(1)}s remaining`}</span>
          {a.canCancel && !a.result && <span className="vn-cancel"><kbd>{a.cancelLabel}</kbd> Cancel</span>}
        </div>
      </div>
    </div>
  );
}

/** Hold-to-interact: keycap inside a ring that fills while the key is held (Lua sends ~10 updates a second; CSS smooths them). */
export function HoldCard({ a, cfg }: { a: ActionState; cfg?: UIConfig['Progress'] }) {
  const done = a.result === 'completed';
  const p = done ? 1 : a.progress ?? 0;
  const C = 2 * Math.PI * 22;
  return (
    <div className={`vn-progress hold${a.result ? ' ending' : ''}`} style={{ bottom: `${cfg?.offsetY ?? 11}vh`, ...(a.color ? { '--vn-accent': a.color } : {}) } as React.CSSProperties} role="progressbar" aria-valuenow={Math.round(p * 100)} aria-label={a.label}>
      <span className="vn-ring">
        <svg viewBox="0 0 52 52" aria-hidden>
          <circle cx="26" cy="26" r="22" className="bg" />
          <circle cx="26" cy="26" r="22" className="fg" style={{ strokeDasharray: C, strokeDashoffset: C * (1 - p) }} />
        </svg>
        {done ? <span className="vn-ring-ok"><Glyph name="check" /></span> : <kbd>{a.keyLabel ?? 'E'}</kbd>}
      </span>
      <div className="vn-p-main">
        <div className="vn-p-label big">{done ? (a.completeLabel ?? 'Done') : a.result === 'cancelled' ? 'Released' : a.label}</div>
        {!done && a.subLabel && <div className="vn-p-sub">{a.subLabel}</div>}
      </div>
    </div>
  );
}
