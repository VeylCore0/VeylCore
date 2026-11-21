import { useEffect, useState } from 'react';
import { Icon, VMark, announceReady, t, useNuiMessage, type TargetState } from '@veyl/ui';

/** Passive overlay: never takes focus. Selection is resolved by Lua from its own registry (index), never by NUI. */
export function App() {
  const [state, setState] = useState<TargetState>({ active: false, options: [], selected: 1 });
  useEffect(() => announceReady(), []);
  useNuiMessage<TargetState>('target:state', setState);

  if (!state.active) return null;
  const has = state.options.length > 0;
  const keys = state.keys ?? { hold: 'ALT', select: 'E' };
  return (
    <div className="tg-root">
      <div className={`tg-reticle${has ? ' on' : ''}`}><span /></div>
      {has && (
        <div className="tg-card" role="listbox" aria-label={state.title ?? 'Interactions'}>
          <div className="tg-brand"><VMark size="0.95rem" /><span>VEYLCORE</span></div>
          {(state.title || state.state) && (
            <div className="tg-context">
              <span className="tg-title">{state.title}</span>
              {state.state && <span className="tg-state"><Icon name={state.stateIcon ?? 'lock'} size="0.85rem" />{state.state}</span>}
            </div>
          )}
          <div className="tg-options">
            {state.options.map((o) => (
              <div key={o.index} role="option" aria-selected={o.index === state.selected} className={`tg-opt${o.index === state.selected ? ' sel' : ''}`}>
                <Icon name={o.icon ?? 'hand'} size="0.95rem" />
                <span>{o.label}</span>
              </div>
            ))}
          </div>
          <div className="tg-hints">
            <span>{t('target.hold')} <span className="v-key">{keys.hold}</span></span>
            <span><span className="v-key">{keys.select}</span> {t('target.select')}</span>
          </div>
        </div>
      )}
    </div>
  );
}
