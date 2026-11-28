import type { SlotItem } from '@veyl/ui';
import type { Def, SlotAddress } from './types';

export interface ItemMenuState { at: SlotAddress; x: number; y: number }

interface Row { label: string; onClick: () => void; disabled?: string; danger?: boolean }

/** Right-click menu inside the inventory page. Rows that cannot apply to the item are left out; the rest say why when disabled. */
export function ItemMenu(props: {
  state: ItemMenuState; item?: SlotItem; def?: Def; secondaryOpen: boolean; secondaryLabel?: string; hasBackpack: boolean;
  onClose: () => void; onUse: () => void; onEquip: () => void; onUnequip: () => void; onGive: () => void; onDrop: () => void; onSplit: () => void;
  onMove: (to: 'secondary' | 'backpack' | 'primary') => void; onAction: (id: string, tray: boolean) => void;
}) {
  const { state, item, def } = props;
  if (!item || !def) return null;
  const ref = state.at.ref;
  const mine = ref === 'primary' || ref === 'backpack';
  const rows: Row[] = [];
  if (ref === 'equip') {
    rows.push({ label: 'Unequip', onClick: props.onUnequip });
  } else {
    if (def.usable && mine) rows.push({ label: 'Use', onClick: props.onUse });
    if (def.equip && mine) rows.push({ label: 'Equip', onClick: props.onEquip });
    for (const a of def.actions ?? []) if (mine) rows.push({ label: a.label, onClick: () => props.onAction(a.id, a.tray === true) });
    if (item.count > 1) rows.push({ label: 'Split stack', onClick: props.onSplit });
    if (mine) rows.push({ label: 'Give to someone nearby', onClick: props.onGive });
    if (ref === 'primary' && props.hasBackpack) rows.push({ label: 'Move to backpack', onClick: () => props.onMove('backpack') });
    if (ref === 'backpack') rows.push({ label: 'Move to pockets', onClick: () => props.onMove('primary') });
    if (ref !== 'secondary' && props.secondaryOpen) rows.push({ label: `Move to ${props.secondaryLabel ?? 'storage'}`, onClick: () => props.onMove('secondary') });
    if (ref === 'secondary') rows.push({ label: 'Take', onClick: () => props.onMove('primary') });
    if (mine) rows.push({ label: 'Drop', onClick: props.onDrop, danger: true });
  }
  const left = Math.min(state.x, window.innerWidth - 232);
  const top = Math.min(state.y, window.innerHeight - 40 - rows.length * 38);
  return (
    <div className="ctx-backdrop" onMouseDown={props.onClose}>
      <div className="ctx" style={{ left, top }} onMouseDown={(e) => e.stopPropagation()} role="menu">
        <div className="ctx-title">{def.label}</div>
        {rows.map((r) => (
          <button key={r.label} role="menuitem" className={`ctx-row${r.danger ? ' danger' : ''}`} disabled={!!r.disabled} title={r.disabled} onClick={r.onClick}>{r.label}</button>
        ))}
      </div>
    </div>
  );
}
