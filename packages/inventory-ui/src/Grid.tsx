import type { InventoryView, ItemDef } from '@veyl/ui';
import type { SlotAddress } from './App';

const fmtKg = (g: number) => `${(g / 1000).toFixed(1)} kg`;

export function Grid(props: {
  view: InventoryView;
  defs: Record<string, ItemDef>;
  imagePath: string;
  pending: Set<string>;
  selected: SlotAddress | null;
  onDragStart: (a: SlotAddress, x: number, y: number) => void;
  onSelect: (a: SlotAddress) => void;
  onHover: (a: SlotAddress | null) => void;
  onQuick: (a: SlotAddress) => void;
  onContext: (a: SlotAddress, x: number, y: number) => void;
  onUse: (a: SlotAddress) => void;
}) {
  const { view, defs, imagePath, pending, selected } = props;
  const bySlot = new Map(view.items.map((i) => [i.slot, i] as const));
  const pct = Math.min(100, (view.weight / Math.max(1, view.maxWeight)) * 100);
  const slots = Array.from({ length: view.slots }, (_, i) => i + 1);

  return (
    <section className="inv-panel v-panel">
      <header className="inv-head">
        <div className="inv-title">{view.ref === 'primary' ? 'Pockets' : view.label}</div>
        <div className="inv-weight v-muted">{fmtKg(view.weight)} / {fmtKg(view.maxWeight)}</div>
      </header>
      <div className="weight-bar"><div className={`weight-fill${pct > 90 ? ' high' : ''}`} style={{ width: `${pct}%` }} /></div>
      <div className="grid">
        {slots.map((slot) => {
          const item = bySlot.get(slot);
          const def = item ? defs[item.name] : undefined;
          const addr: SlotAddress = { ref: view.ref, slot };
          const isSel = selected?.ref === view.ref && selected.slot === slot;
          const isPending = pending.has(`${view.ref}:${slot}`);
          return (
            <div
              key={slot}
              data-ref={view.ref}
              data-slot={slot}
              className={`slot${item ? ' filled' : ''}${isSel ? ' sel' : ''}${isPending ? ' pending' : ''}`}
              onMouseDown={(e) => {
                if (e.button !== 0) return;
                props.onSelect(addr);
                if (e.ctrlKey) { props.onQuick(addr); return; }
                if (item) props.onDragStart(addr, e.clientX, e.clientY);
              }}
              onDoubleClick={() => props.onUse(addr)}
              onContextMenu={(e) => { e.preventDefault(); props.onContext(addr, e.clientX, e.clientY); }}
              onMouseEnter={() => props.onHover(item ? addr : null)}
              onMouseLeave={() => props.onHover(null)}
            >
              {item && (
                <>
                  <img src={`${imagePath}/${def?.image ?? item.name + '.svg'}`} alt="" draggable={false} />
                  {item.count > 1 && <span className="count">{item.count}</span>}
                  <span className="label">{def?.label ?? item.name}</span>
                  {typeof item.durability === 'number' && <span className="durability" style={{ width: `${item.durability}%` }} />}
                </>
              )}
            </div>
          );
        })}
      </div>
    </section>
  );
}
