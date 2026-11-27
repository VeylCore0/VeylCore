import { useEffect, useState } from 'react';
import { Icon, VMark, announceReady, t, useNuiMessage, type TargetState } from '@veyl/ui';

/**
 * Interaction menu. Passive overlay: never takes focus. Selection is resolved by Lua from its own registry (index),
 * never by NUI. Scroll / arrow keys move the selection, the key (E) or a click confirms: that is all Lua; this only draws.
 *
 * The keycap on the left slides to the selected row (it is positioned from the selected index with a CSS variable).
 */
export function App() {
  const [state, setState] = useState<TargetState>({ active: false, options: [], selected: 1 });
  useEffect(() => announceReady(), []);
  useNuiMessage<TargetState>('target:state', setState);

  if (!state.active) return null;
  const has = state.options.length > 0;
  const keys = state.keys ?? { hold: 'ALT', select: 'E' };
  const sel = Math.max(0, state.options.findIndex((o) => o.index === state.selected));
  const many = state.options.length > 1;

  return (
    <div className="tg-root">
      <div className={`tg-reticle${has ? ' on' : ''}`}><i /><i /><i /><i /><span /></div>
      {has && (
        <div className="tg-menu" role="listbox" aria-label={state.title ?? 'Interactions'}>
          <span className="tg-link" aria-hidden="true" />
          {(state.title || state.state) && (
            <div className="tg-head">
              <VMark size="0.8rem" />
              {state.title && <span className="tg-title">{state.title}</span>}
              {state.state && <span className="tg-state"><Icon name={state.stateIcon ?? 'lock'} size="0.8rem" />{state.state}</span>}
            </div>
          )}
          <div className="tg-body" style={{ ['--sel' as string]: sel }}>
            <div className="tg-key" aria-hidden="true"><span>{keys.select}</span></div>
            <div className="tg-list">
              {state.options.map((o, i) => (
                <div
                  key={o.index}
                  role="option"
                  aria-selected={i === sel}
                  className={`tg-row${i === sel ? ' sel' : ''}`}
                  style={{ ['--n' as string]: i, ['--d' as string]: Math.min(Math.abs(i - sel), 4) }}
                >
                  <span className="tg-dot" />
                  <span className="tg-opt">
                    <Icon name={o.icon ?? 'hand'} size="1rem" />
                    <span className="tg-label">{o.label}</span>
                  </span>
                </div>
              ))}
            </div>
          </div>
          <div className="tg-hints">
            {many && <span><Icon name="mouse" size="0.85rem" /> scroll</span>}
            <span>{t('target.hold')} <span className="tg-cap">{keys.hold}</span></span>
          </div>
        </div>
      )}
    </div>
  );
}
