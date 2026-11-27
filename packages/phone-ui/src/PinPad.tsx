// A 4-digit PIN entry: dots, keypad, keyboard digits, shake on a wrong PIN. Used by the lock screen, setup and Settings.
import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import { Ico } from './icons';
import { cx } from './ui';

const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9'];

export function PinPad({ title, subtitle, error, disabled, onComplete, footer }: {
  title: string; subtitle?: string; error?: string; disabled?: boolean;
  /** Return false for a wrong / rejected PIN: the dots shake and clear. Anything else just clears for the next step. */
  onComplete: (pin: string) => Promise<boolean | void> | boolean | void;
  footer?: ReactNode;
}) {
  const [pin, setPin] = useState('');
  const [shake, setShake] = useState(false);
  const cur = useRef('');     // the digits typed so far (state setters must stay free of side effects)
  const busy = useRef(false);
  const done = useRef(onComplete);
  done.current = onComplete;
  const set = (v: string) => { cur.current = v; setPin(v); };

  const press = useCallback((d: string) => {
    if (busy.current || disabled || cur.current.length >= 4) return;
    const next = cur.current + d;
    set(next);
    if (next.length < 4) return;
    busy.current = true;
    void (async () => {
      let ok: boolean | void = true;
      try { ok = await done.current(next); } finally { busy.current = false; }
      if (ok === false) { setShake(true); window.setTimeout(() => setShake(false), 480); }
      set('');
    })();
  }, [disabled]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (document.activeElement && document.activeElement !== document.body) return;
      if (/^[0-9]$/.test(e.key)) press(e.key);
      else if (e.key === 'Backspace' && !busy.current) set(cur.current.slice(0, -1));
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [press]);

  return (
    <div className="ph-pin">
      <h2>{title}</h2>
      <p className={cx('ph-pin-sub', !!error && 'err')} role="status">{error || subtitle || ' '}</p>
      <div className={cx('ph-pin-dots', shake && 'shake')} aria-label={`${pin.length} of 4 digits`}>
        {[0, 1, 2, 3].map((i) => <i key={i} className={cx(i < pin.length && 'on')} />)}
      </div>
      <div className="ph-pin-keys">
        {KEYS.map((k) => <button key={k} className="ph-pk" onClick={() => press(k)} disabled={disabled}>{k}</button>)}
        <span />
        <button className="ph-pk" onClick={() => press('0')} disabled={disabled}>0</button>
        <button className="ph-pk plain" onClick={() => !busy.current && set(cur.current.slice(0, -1))} aria-label="Delete" style={{ visibility: pin ? 'visible' : 'hidden' }}><Ico name="backspace" size={22} /></button>
      </div>
      {footer && <div className="ph-pin-foot">{footer}</div>}
    </div>
  );
}

/** Choose a new PIN: enter it, then enter it again. `onSubmit` returns an error message, or nothing when it worked. */
export function NewPin({ title = 'Create a PIN', subtitle = 'Choose 4 digits', onSubmit, footer }: {
  title?: string; subtitle?: string; onSubmit: (pin: string) => Promise<string | void>; footer?: ReactNode;
}) {
  const [first, setFirst] = useState<string | null>(null);
  const [error, setError] = useState('');
  return (
    <PinPad
      title={first ? 'Confirm your PIN' : title}
      subtitle={first ? 'Enter it once more' : subtitle}
      error={error}
      footer={footer}
      onComplete={async (pin) => {
        if (!first) { setFirst(pin); setError(''); return; }
        if (pin !== first) { setFirst(null); setError('The PINs did not match. Try again.'); return false; }
        const problem = await onSubmit(pin);
        if (problem) { setFirst(null); setError(problem); return false; }
      }}
    />
  );
}
