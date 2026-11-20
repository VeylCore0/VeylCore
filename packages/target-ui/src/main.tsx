import { createRoot } from 'react-dom/client';
import { useEffect, useState } from 'react';
import { announceReady, useNuiMessage, type TargetState } from '@veyl/ui';
import './target.css';

function Overlay() {
  const [state, setState] = useState<TargetState>({ active: false, options: [], selected: 1 });
  useEffect(() => announceReady(), []);
  useNuiMessage<TargetState>('target:state', setState);

  if (!state.active) return null;
  const hasOptions = state.options.length > 0;
  return (
    <div className="target">
      <div className={`reticle${hasOptions ? ' on' : ''}`} />
      {hasOptions && (
        <div className="options v-panel" role="listbox">
          {state.options.map((o) => (
            <div key={o.index} role="option" aria-selected={o.index === state.selected} className={`opt${o.index === state.selected ? ' sel' : ''}`}>
              <span className="opt-label">{o.label}</span>
            </div>
          ))}
          <div className="hint v-muted">
            <span className="v-key">E</span> select{state.options.length > 1 && <> · <span className="v-key">Scroll</span> change</>}
          </div>
        </div>
      )}
    </div>
  );
}

createRoot(document.getElementById('root')!).render(<Overlay />);
