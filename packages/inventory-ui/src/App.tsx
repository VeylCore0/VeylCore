import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  announceReady, nui, useNuiMessage,
  type InventoryDelta, type InventoryOpen, type InventoryView, type ItemDef, type SlotItem,
} from '@veyl/ui';
import { Grid } from './Grid';
import { Details } from './Details';
import { ContextMenu, type ContextState } from './ContextMenu';
import { SplitDialog, type SplitState } from './SplitDialog';

type Ref = 'primary' | 'secondary';
export interface SlotAddress { ref: Ref; slot: number }
interface Views { primary?: InventoryView; secondary?: InventoryView }

const newOpId = () =>
  (typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`)
    .replace(/[^\w-]/g, '').slice(0, 64);

function applyDelta(view: InventoryView, d: InventoryDelta): InventoryView {
  const map = new Map(view.items.map((i) => [i.slot, i] as const));
  for (const change of d.slots) {
    if (change.item) map.set(change.slot, change.item); else map.delete(change.slot);
  }
  return { ...view, revision: d.revision, weight: d.weight, items: [...map.values()] };
}

export function App() {
  const [open, setOpen] = useState(false);
  const [views, setViews] = useState<Views>({});
  const [defs, setDefs] = useState<Record<string, ItemDef>>({});
  const [imagePath, setImagePath] = useState('');
  const [pending, setPending] = useState<Set<string>>(new Set());
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<SlotAddress | null>(null);
  const [hovered, setHovered] = useState<SlotAddress | null>(null);
  const [drag, setDrag] = useState<{ from: SlotAddress; x: number; y: number } | null>(null);
  const [context, setContext] = useState<ContextState | null>(null);
  const [split, setSplit] = useState<SplitState | null>(null);
  const errorTimer = useRef<number>();

  useEffect(() => announceReady(), []);

  useNuiMessage<InventoryOpen>('inventory:open', (d) => {
    setViews({ primary: d.primary, secondary: d.secondary });
    setDefs(d.items);
    setImagePath(d.imagePath);
    setPending(new Set());
    setSelected({ ref: 'primary', slot: 1 });
    setContext(null);
    setSplit(null);
    setOpen(true);
  });
  useNuiMessage('inventory:close', () => { setOpen(false); setDrag(null); setContext(null); setSplit(null); });
  useNuiMessage<InventoryDelta>('inventory:delta', (d) => {
    setViews((v) => {
      const view = v[d.ref];
      if (!view) return v;
      return { ...v, [d.ref]: applyDelta(view, d) };
    });
  });
  useNuiMessage<InventoryView>('inventory:snapshot', (view) => setViews((v) => ({ ...v, [view.ref]: view })));

  const showError = useCallback((msg: string) => {
    setError(msg);
    window.clearTimeout(errorTimer.current);
    errorTimer.current = window.setTimeout(() => setError(null), 3500);
  }, []);

  const itemAt = useCallback((a: SlotAddress | null): SlotItem | undefined => {
    if (!a) return undefined;
    return views[a.ref]?.items.find((i) => i.slot === a.slot);
  }, [views]);

  const key = (a: SlotAddress) => `${a.ref}:${a.slot}`;

  /** Every move is a server request; the grid changes only when the server's delta arrives. */
  const move = useCallback(async (from: SlotAddress, to: SlotAddress, count?: number) => {
    if (from.ref === to.ref && from.slot === to.slot) return;
    const fromView = views[from.ref];
    const toView = views[to.ref];
    if (!fromView || !toView) return;
    const keys = [key(from), key(to)];
    if (keys.some((k) => pending.has(k))) return;
    setPending((p) => new Set([...p, ...keys]));
    const revisions: Record<string, number> = { [from.ref]: fromView.revision };
    revisions[to.ref] = toView.revision;
    const res = await nui('move', { opId: newOpId(), from, to, count, revisions });
    setPending((p) => { const n = new Set(p); keys.forEach((k) => n.delete(k)); return n; });
    if (!res.ok) showError(res.message ?? res.code ?? 'Move failed');
  }, [views, pending, showError]);

  /** Quick transfer: first matching stack or empty slot in the other panel. */
  const quickTransfer = useCallback((from: SlotAddress) => {
    const target: Ref = from.ref === 'primary' ? 'secondary' : 'primary';
    const dest = views[target];
    const item = itemAt(from);
    if (!dest || !item) return;
    const def = defs[item.name];
    const stack = def?.stack ? dest.items.find((i) => i.name === item.name && JSON.stringify(i.metadata ?? {}) === JSON.stringify(item.metadata ?? {})) : undefined;
    let slot = stack?.slot;
    if (!slot) {
      const used = new Set(dest.items.map((i) => i.slot));
      for (let s = 1; s <= dest.slots; s++) if (!used.has(s)) { slot = s; break; }
    }
    if (!slot) return showError('No free slot');
    void move(from, { ref: target, slot });
  }, [views, defs, itemAt, move, showError]);

  const use = useCallback((a: SlotAddress) => {
    const item = itemAt(a);
    if (!item || a.ref !== 'primary' || !defs[item.name]?.usable) return;
    void nui('use', { slot: a.slot });
  }, [itemAt, defs]);

  const close = useCallback(() => { void nui('close'); }, []);

  // Drag handling (pointer based so it works with keyboard-less mice and in CEF).
  useEffect(() => {
    if (!drag) return;
    const onMove = (e: MouseEvent) => setDrag((d) => (d ? { ...d, x: e.clientX, y: e.clientY } : d));
    const onUp = (e: MouseEvent) => {
      const el = (e.target as HTMLElement).closest<HTMLElement>('[data-slot]');
      const from = drag.from;
      setDrag(null);
      if (!el) return;
      const to: SlotAddress = { ref: el.dataset.ref as Ref, slot: Number(el.dataset.slot) };
      const item = itemAt(from);
      if (!item) return;
      if (e.shiftKey && item.count > 1) {
        setSplit({ from, to, max: item.count, value: Math.floor(item.count / 2) });
      } else {
        void move(from, to);
      }
    };
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
    return () => { window.removeEventListener('mousemove', onMove); window.removeEventListener('mouseup', onUp); };
  }, [drag, itemAt, move]);

  // Keyboard alternatives.
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (split || context) { if (e.key === 'Escape') { setSplit(null); setContext(null); } return; }
      if (e.key === 'Escape' || e.key === 'F2') { e.preventDefault(); close(); return; }
      if (!selected) return;
      const view = views[selected.ref];
      if (!view) return;
      const cols = 5;
      const nav: Record<string, number> = { ArrowRight: 1, ArrowLeft: -1, ArrowDown: cols, ArrowUp: -cols };
      if (e.key in nav) {
        e.preventDefault();
        const next = selected.slot + nav[e.key];
        if (next >= 1 && next <= view.slots) setSelected({ ...selected, slot: next });
      } else if (e.key === 'Tab') {
        e.preventDefault();
        const other: Ref = selected.ref === 'primary' ? 'secondary' : 'primary';
        if (views[other]) setSelected({ ref: other, slot: 1 });
      } else if (e.key === 'Enter') {
        use(selected);
      } else if (e.key.toLowerCase() === 'q') {
        quickTransfer(selected);
      } else if (e.key.toLowerCase() === 's') {
        const item = itemAt(selected);
        if (item && item.count > 1) {
          const used = new Set(view.items.map((i) => i.slot));
          let empty: number | undefined;
          for (let s = 1; s <= view.slots; s++) if (!used.has(s)) { empty = s; break; }
          if (empty) setSplit({ from: selected, to: { ref: selected.ref, slot: empty }, max: item.count, value: Math.floor(item.count / 2) });
        }
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, selected, views, split, context, use, quickTransfer, itemAt, close]);

  const detailsTarget = hovered ?? selected;
  const detailsItem = itemAt(detailsTarget);
  const dragItem = drag ? itemAt(drag.from) : undefined;

  const handlers = useMemo(() => ({
    onDragStart: (from: SlotAddress, x: number, y: number) => { if (itemAt(from)) setDrag({ from, x, y }); },
    onSelect: (a: SlotAddress) => setSelected(a),
    onHover: (a: SlotAddress | null) => setHovered(a),
    onQuick: (a: SlotAddress) => quickTransfer(a),
    onContext: (a: SlotAddress, x: number, y: number) => { if (itemAt(a)) setContext({ at: a, x, y }); },
    onUse: (a: SlotAddress) => use(a),
  }), [itemAt, quickTransfer, use]);

  if (!open || !views.primary) return null;

  return (
    <div className="inv-root" onContextMenu={(e) => e.preventDefault()}>
      <div className="inv-layout">
        <Grid view={views.primary} defs={defs} imagePath={imagePath} pending={pending} selected={selected} {...handlers} />
        {views.secondary && (
          <Grid view={views.secondary} defs={defs} imagePath={imagePath} pending={pending} selected={selected} {...handlers} />
        )}
        <Details item={detailsItem} def={detailsItem ? defs[detailsItem.name] : undefined} imagePath={imagePath} />
      </div>
      <div className="inv-help v-muted">
        <span><span className="v-key">Drag</span> move</span>
        <span><span className="v-key">Shift</span>+drop split</span>
        <span><span className="v-key">Ctrl</span>+click / <span className="v-key">Q</span> quick transfer</span>
        <span><span className="v-key">Enter</span> use</span>
        <span><span className="v-key">Esc</span> close</span>
      </div>
      {error && <div className="inv-error" role="alert">✕ {error}</div>}
      {drag && dragItem && (
        <div className="drag-ghost" style={{ left: drag.x, top: drag.y }}>
          <img src={`${imagePath}/${defs[dragItem.name]?.image ?? dragItem.name + '.svg'}`} alt="" />
        </div>
      )}
      {context && (
        <ContextMenu
          state={context}
          item={itemAt(context.at)}
          def={itemAt(context.at) ? defs[itemAt(context.at)!.name] : undefined}
          canTransfer={Boolean(views.secondary)}
          onClose={() => setContext(null)}
          onUse={() => { use(context.at); setContext(null); }}
          onQuick={() => { quickTransfer(context.at); setContext(null); }}
          onSplit={() => {
            const item = itemAt(context.at);
            const view = views[context.at.ref];
            setContext(null);
            if (!item || !view || item.count < 2) return;
            const used = new Set(view.items.map((i) => i.slot));
            for (let s = 1; s <= view.slots; s++) {
              if (!used.has(s)) { setSplit({ from: context.at, to: { ref: context.at.ref, slot: s }, max: item.count, value: Math.floor(item.count / 2) }); return; }
            }
            showError('No free slot to split into');
          }}
        />
      )}
      {split && (
        <SplitDialog
          state={split}
          onCancel={() => setSplit(null)}
          onConfirm={(n) => { const s = split; setSplit(null); void move(s.from, s.to, n); }}
        />
      )}
    </div>
  );
}
