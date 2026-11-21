import { useEffect, useRef, useState } from 'react';
import { CloseHint, t } from '@veyl/ui';
import type { SlotAddress } from './App';

export interface QuantityDialogState { from: SlotAddress; to: SlotAddress; max: number; value: number }

/** Split quantity, bounded by the server-owned stack count shown when the dialog opened. */
export function QuantityDialog({ state, onCancel, onConfirm }: { state: QuantityDialogState; onCancel: () => void; onConfirm: (n: number) => void }) {
  const [value, setValue] = useState(Math.max(1, state.value));
  const ref = useRef<HTMLInputElement>(null);
  useEffect(() => { setTimeout(() => ref.current?.select(), 30); }, []);
  const valid = Number.isInteger(value) && value >= 1 && value <= state.max;
  return (
    <div className="v-dialog-backdrop" onMouseDown={onCancel}>
      <div className="v-panel dialog" onMouseDown={(e) => e.stopPropagation()} role="dialog" aria-label={t('inv.split')}>
        <div className="dialog-head"><span className="dialog-title">{t('inv.split')}</span><CloseHint onClose={onCancel} /></div>
        <input className="split-range" type="range" min={1} max={state.max} value={value} onChange={(e) => setValue(Number(e.target.value))} />
        <input ref={ref} className="v-input" type="number" min={1} max={state.max} value={value}
          onChange={(e) => setValue(Math.floor(Number(e.target.value)))} onKeyDown={(e) => { if (e.key === 'Enter' && valid) onConfirm(value); }} />
        <div className="dialog-actions">
          <button className="v-btn" onClick={onCancel}>{t('common.cancel')}</button>
          <button className="v-btn primary" disabled={!valid} onClick={() => valid && onConfirm(value)}>{t('common.confirm')}</button>
        </div>
      </div>
    </div>
  );
}
