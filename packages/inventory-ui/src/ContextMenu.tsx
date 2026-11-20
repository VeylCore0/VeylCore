import type { ItemDef, SlotItem } from '@veyl/ui';
import type { SlotAddress } from './App';

export interface ContextState { at: SlotAddress; x: number; y: number }

export function ContextMenu(props: {
  state: ContextState;
  item?: SlotItem;
  def?: ItemDef;
  canTransfer: boolean;
  onClose: () => void;
  onUse: () => void;
  onQuick: () => void;
  onSplit: () => void;
}) {
  const { state, item, def } = props;
  if (!item || !def) return null;
  return (
    <div className="ctx-backdrop" onMouseDown={props.onClose}>
      <div className="ctx v-panel" style={{ left: state.x, top: state.y }} onMouseDown={(e) => e.stopPropagation()} role="menu">
        <div className="ctx-title">{def.label}</div>
        {def.usable && state.at.ref === 'primary' && <button className="ctx-row" onClick={props.onUse}>Use</button>}
        {item.count > 1 && <button className="ctx-row" onClick={props.onSplit}>Split stack…</button>}
        {props.canTransfer && (
          <button className="ctx-row" onClick={props.onQuick}>{state.at.ref === 'primary' ? 'Move to storage' : 'Take'}</button>
        )}
        <button className="ctx-row muted" onClick={props.onClose}>Cancel</button>
      </div>
    </div>
  );
}
