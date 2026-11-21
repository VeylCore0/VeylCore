import { Icon, t, type ItemDef, type SlotItem } from '@veyl/ui';
import type { SlotAddress } from './App';

export interface ItemMenuState { at: SlotAddress; x: number; y: number }

/** Compact right-click menu rendered inside the inventory NUI (never a second resource's modal). */
export function ItemMenu(props: {
  state: ItemMenuState; item?: SlotItem; def?: ItemDef; hasSecondary: boolean;
  onClose: () => void; onUse: () => void; onGive: () => void; onTransfer: () => void; onSplit: () => void;
}) {
  const { state, item, def } = props;
  if (!item || !def) return null;
  const personal = state.at.ref === 'primary';
  const rows: { label: string; icon: string; onClick: () => void; disabled?: string }[] = [
    { label: t('inv.use'), icon: 'use', onClick: props.onUse, disabled: !personal ? t('inv.useFromPersonal') : !def.usable ? t('inv.notUsable') : undefined },
    { label: t('inv.give'), icon: 'give', onClick: props.onGive, disabled: !personal ? t('inv.useFromPersonal') : undefined },
    { label: t('inv.split'), icon: 'hotbar', onClick: props.onSplit, disabled: item.count < 2 ? 'Only one item in this stack' : undefined },
    { label: personal ? t('inv.moveToStorage') : t('inv.take'), icon: 'transfer', onClick: props.onTransfer, disabled: !props.hasSecondary ? 'No storage open' : undefined },
    { label: t('inv.drop'), icon: 'drop_item', onClick: props.onClose, disabled: t('inv.dropUnavailable') },
  ];
  const left = Math.min(state.x, window.innerWidth - 220);
  const top = Math.min(state.y, window.innerHeight - 240);
  return (
    <div className="ctx-backdrop" onMouseDown={props.onClose}>
      <div className="ctx v-panel" style={{ left, top }} onMouseDown={(e) => e.stopPropagation()} role="menu">
        <div className="ctx-title">{def.label}</div>
        {rows.map((r) => (
          <button key={r.label} role="menuitem" className="ctx-row" disabled={!!r.disabled} title={r.disabled} onClick={r.onClick}>
            <Icon name={r.icon} size="1rem" />
            <span>{r.label}</span>
            {r.disabled && <span className="ctx-reason">{r.disabled}</span>}
          </button>
        ))}
      </div>
    </div>
  );
}
