import { useEffect, useRef, useState } from 'react';
import { CloseHint, money, newOpId, t } from '@veyl/ui';
import { parseAmount } from './App';

/** Deposit/withdraw amount entry. The operation id is created once per dialog so a timed-out submit can be retried safely. */
export function AmountDialog({ title, max, onCancel, onSubmit }: {
  title: string; max: number; onCancel: () => void; onSubmit: (amount: number, opId: string) => Promise<boolean | 'retry'>;
}) {
  const [raw, setRaw] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const opId = useRef(newOpId());
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => { setTimeout(() => input.current?.focus(), 30); }, []);

  const submit = async () => {
    if (busy) return;
    const a = parseAmount(raw);
    if (!a.ok) return setError(a.error);
    if (a.value > max) return setError(`Maximum ${money(max)}`);
    setError(null);
    setBusy(true);
    const r = await onSubmit(a.value, opId.current);
    setBusy(false);
    if (r === false) opId.current = newOpId(); // a definite failure: a new attempt is a new operation
  };

  return (
    <div className="v-dialog-backdrop" onMouseDown={() => !busy && onCancel()}>
      <div className="v-panel bank-dialog" role="dialog" aria-label={title} onMouseDown={(e) => e.stopPropagation()}
        onKeyDown={(e) => { if (e.key === 'Escape' && !busy) onCancel(); if (e.key === 'Enter') void submit(); }}>
        <div className="bank-dialog-head"><span className="bank-h2">{title}</span><CloseHint onClose={() => !busy && onCancel()} /></div>
        <label className="bank-field"><span>{t('bank.amount')} <span className="v-muted">(max {money(max)})</span></span>
          <input ref={input} className="v-input" value={raw} inputMode="numeric" placeholder="$0" onChange={(e) => setRaw(e.target.value)} />
          {error && <em className="bank-err">{error}</em>}
        </label>
        <div className="bank-dialog-actions">
          <button className="v-btn" disabled={busy} onClick={onCancel}>{t('common.cancel')}</button>
          <button className="v-btn primary" disabled={busy} onClick={() => void submit()}>{busy ? '…' : title}</button>
        </div>
      </div>
    </div>
  );
}

export function ConfirmDialog({ title, message, detail, busy, onCancel, onConfirm }: {
  title: string; message: string; detail?: string; busy: boolean; onCancel: () => void; onConfirm: () => void;
}) {
  return (
    <div className="v-dialog-backdrop" onMouseDown={() => !busy && onCancel()}>
      <div className="v-panel bank-dialog" role="alertdialog" aria-label={title} onMouseDown={(e) => e.stopPropagation()}>
        <div className="bank-dialog-head"><span className="bank-h2">{title}</span></div>
        <p className="bank-confirm-msg">{message}</p>
        {detail && <p className="v-muted">{detail}</p>}
        <div className="bank-dialog-actions">
          <button className="v-btn" disabled={busy} onClick={onCancel}>{t('common.cancel')}</button>
          <button className="v-btn primary" disabled={busy} onClick={onConfirm} autoFocus>{busy ? '…' : t('common.confirm')}</button>
        </div>
      </div>
    </div>
  );
}
