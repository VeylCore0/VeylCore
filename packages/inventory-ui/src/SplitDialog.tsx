import { useEffect, useRef, useState } from 'react';
import { Panel } from '@veyl/ui';
import type { SlotAddress } from './App';

export interface SplitState { from: SlotAddress; to: SlotAddress; max: number; value: number }

export function SplitDialog({ state, onCancel, onConfirm }: { state: SplitState; onCancel: () => void; onConfirm: (n: number) => void }) {
  const [value, setValue] = useState(Math.max(1, state.value));
  const inputRef = useRef<HTMLInputElement>(null);
  useEffect(() => { setTimeout(() => inputRef.current?.select(), 30); }, []);
  const valid = Number.isInteger(value) && value >= 1 && value < state.max + 1;
  return (
    <div className="split-backdrop">
      <Panel
        title="Split stack"
        width={320}
        onClose={onCancel}
        footer={
          <>
            <button className="v-btn" onClick={onCancel}>Cancel</button>
            <button className="v-btn primary" disabled={!valid} onClick={() => valid && onConfirm(value)}>Move {valid ? value : ''}</button>
          </>
        }
      >
        <input
          ref={inputRef}
          className="split-range"
          type="range"
          min={1}
          max={state.max}
          value={value}
          onChange={(e) => setValue(Number(e.target.value))}
        />
        <input
          className="split-number"
          type="number"
          min={1}
          max={state.max}
          value={value}
          onChange={(e) => setValue(Math.floor(Number(e.target.value)))}
          onKeyDown={(e) => { if (e.key === 'Enter' && valid) onConfirm(value); }}
        />
        <span className="v-muted"> of {state.max}</span>
      </Panel>
    </div>
  );
}
