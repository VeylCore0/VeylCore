import type { ReactNode } from 'react';
import type { SlotItem } from '@veyl/ui';
import { key, type Def, type Ref, type SlotAddress, type View } from './types';

export interface SlotHandlers {
  onSelect: (a: SlotAddress) => void;
  onDragStart: (a: SlotAddress, x: number, y: number) => void;
  onShiftClick: (a: SlotAddress) => void;
  onContext: (a: SlotAddress, x: number, y: number) => void;
  onDouble: (a: SlotAddress) => void;
  onHover: (a: SlotAddress | null, x: number, y: number) => void;
}

export const countText = (n: number) => n.toLocaleString('en-US');

/** One item tile: icon and a count in the corner. Shared by the grids and the equipment slots. */
export function SlotTile(props: {
  addr: SlotAddress; item?: SlotItem; def?: Def; imagePath: string; selected: boolean; pending: boolean; dim: boolean; hotkey?: number;
  placeholder?: ReactNode; className?: string; handlers: SlotHandlers;
}) {
  const { addr, item, def, imagePath, handlers } = props;
  return (
    <div
      data-ref={addr.ref} data-slot={addr.slot}
      className={`slot${item ? ' filled' : ''}${props.selected ? ' sel' : ''}${props.pending ? ' pending' : ''}${props.dim ? ' dim' : ''}${props.className ? ' ' + props.className : ''}`}
      onMouseDown={(e) => {
        if (e.button !== 0) return;
        handlers.onSelect(addr);
        if (e.shiftKey && item) { handlers.onShiftClick(addr); return; }
        if (item) handlers.onDragStart(addr, e.clientX, e.clientY);
      }}
      onDoubleClick={() => item && handlers.onDouble(addr)}
      onContextMenu={(e) => { e.preventDefault(); handlers.onContext(addr, e.clientX, e.clientY); }}
      onMouseEnter={(e) => handlers.onHover(addr, e.clientX, e.clientY)}
      onMouseMove={(e) => item && handlers.onHover(addr, e.clientX, e.clientY)}
      onMouseLeave={() => handlers.onHover(null, 0, 0)}
    >
      {props.hotkey !== undefined && <span className="slot-num">{props.hotkey}</span>}
      {item ? (
        <>
          {(item.count > 1 || !def || def.stack) && <span className="slot-count" data-long={String(item.count).length > 7}>{countText(item.count)}</span>}
          <img className="slot-img" draggable={false} src={`${imagePath}/${def?.image ?? item.name + '.png'}`} alt={def?.label ?? item.name}
            onError={(e) => { (e.target as HTMLImageElement).style.visibility = 'hidden'; }} />
          {typeof item.durability === 'number' && <span className="slot-dur" style={{ width: `${Math.max(0, Math.min(100, item.durability))}%` }} />}
        </>
      ) : props.placeholder}
    </div>
  );
}

/** A grid of slots for one container. Search and category only dim: slot identity and server state never change. */
export function Grid(props: {
  view: View; defs: Record<string, Def>; imagePath: string; pending: Set<string>; selected: SlotAddress | null; hotbar?: number; cols: number;
  matches: (item: SlotItem | undefined) => boolean; handlers: SlotHandlers;
}) {
  const { view, defs } = props;
  const bySlot = new Map(view.items.map((i) => [i.slot, i] as const));
  return (
    <div className="grid" style={{ ['--cols' as string]: props.cols }}>
      {Array.from({ length: view.slots }, (_, i) => i + 1).map((slot) => {
        const item = bySlot.get(slot);
        const addr: SlotAddress = { ref: view.ref as Ref, slot };
        return (
          <SlotTile key={slot} addr={addr} item={item} def={item ? defs[item.name] : undefined} imagePath={props.imagePath}
            selected={props.selected?.ref === view.ref && props.selected.slot === slot} pending={props.pending.has(key(addr))}
            dim={!props.matches(item)} hotkey={props.hotbar && slot <= props.hotbar ? slot : undefined} handlers={props.handlers} />
        );
      })}
    </div>
  );
}
