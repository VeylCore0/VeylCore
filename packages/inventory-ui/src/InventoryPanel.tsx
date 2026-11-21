import { useState, type ReactNode } from 'react';
import { ItemImage, SearchBox, kg, type InventoryView, type ItemDef } from '@veyl/ui';
import type { SlotAddress } from './App';

export function InventoryPanel(props: {
  view: InventoryView; defs: Record<string, ItemDef>; imagePath: string; pending: Set<string>; selected: SlotAddress | null;
  title: string; subtitle: string; searchPlaceholder: string; hotbar: number; footer?: ReactNode;
  onSelect: (a: SlotAddress) => void; onDragStart: (a: SlotAddress, x: number, y: number) => void;
  onShiftClick: (a: SlotAddress) => void; onContext: (a: SlotAddress, x: number, y: number) => void; onUse: (a: SlotAddress) => void;
}) {
  const { view, defs, imagePath, pending, selected } = props;
  const [search, setSearch] = useState('');
  const bySlot = new Map(view.items.map((i) => [i.slot, i] as const));
  const pct = Math.min(100, (view.weight / Math.max(1, view.maxWeight)) * 100);
  const q = search.trim().toLowerCase();

  return (
    <section className="inv-panel v-panel" aria-label={props.title}>
      <div className="panel-head">
        <div className="panel-title">{props.title.toUpperCase()}</div>
        <div className="panel-weight">{kg(view.weight)} / {Math.round(view.maxWeight / 1000)} kg</div>
      </div>
      <div className="panel-sub">
        <span className="v-muted">{props.subtitle}</span>
        <div className="weight-bar" role="progressbar" aria-valuenow={Math.round(pct)} aria-valuemin={0} aria-valuemax={100}>
          <div className={`weight-fill${pct > 90 ? ' high' : ''}`} style={{ width: `${pct}%` }} />
        </div>
      </div>
      <SearchBox value={search} onChange={setSearch} placeholder={props.searchPlaceholder} />
      <div className="grid v-scroll">
        {Array.from({ length: view.slots }, (_, i) => i + 1).map((slot) => {
          const item = bySlot.get(slot);
          const def = item ? defs[item.name] : undefined;
          const addr: SlotAddress = { ref: view.ref, slot };
          const isSel = selected?.ref === view.ref && selected.slot === slot;
          const isPending = pending.has(`${view.ref}:${slot}`);
          // Search only dims non-matching slots: slot identity and server state are unchanged.
          const dim = q !== '' && !(item && (def?.label ?? item.name).toLowerCase().includes(q));
          return (
            <div
              key={slot} data-ref={view.ref} data-slot={slot}
              className={`slot${item ? ' filled' : ''}${isSel ? ' sel' : ''}${isPending ? ' pending' : ''}${dim ? ' dim' : ''}`}
              onMouseDown={(e) => {
                if (e.button !== 0) return;
                props.onSelect(addr);
                if (e.shiftKey && item) { props.onShiftClick(addr); return; }
                if (item) props.onDragStart(addr, e.clientX, e.clientY);
              }}
              onDoubleClick={() => item && props.onUse(addr)}
              onContextMenu={(e) => { e.preventDefault(); props.onContext(addr, e.clientX, e.clientY); }}
            >
              {slot <= props.hotbar && <span className="slot-num">{slot}</span>}
              {item && (
                <>
                  <span className="slot-count">x{item.count}</span>
                  <ItemImage src={`${imagePath}/${def?.image ?? item.name + '.png'}`} alt={def?.label ?? item.name} size="58%" />
                  <span className="slot-label">{def?.label ?? item.name}</span>
                  {typeof item.durability === 'number' && <span className="slot-dur" style={{ width: `${Math.max(0, Math.min(100, item.durability))}%` }} />}
                </>
              )}
            </div>
          );
        })}
      </div>
      {props.footer}
    </section>
  );
}
