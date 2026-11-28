import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  BrandStack, CloseHint, Icon, announceReady, newOpId, nui, t, useNuiMessage,
  type InventoryDelta, type InventoryOpen, type InventoryView, type ItemDef, type NearbyPlayer, type SlotItem,
} from '@veyl/ui';
import { InventoryPanel } from './InventoryPanel';
import { ItemMenu, type ItemMenuState } from './ItemMenu';
import { QuantityDialog, type QuantityDialogState } from './QuantityDialog';
import { GiveDialog } from './GiveDialog';
import { TrayDialog, type TrayState } from './TrayDialog';

export type Ref = 'primary' | 'secondary';
export interface SlotAddress { ref: Ref; slot: number }
type Views = { primary?: InventoryView; secondary?: InventoryView };

function applyDelta(view: InventoryView, d: InventoryDelta): InventoryView {
  const map = new Map(view.items.map((i) => [i.slot, i] as const));
  for (const c of d.slots) { if (c.item) map.set(c.slot, c.item); else map.delete(c.slot); }
  return { ...view, revision: d.revision, weight: d.weight, items: [...map.values()] };
}

export function App() {
  const [open, setOpen] = useState(false);
  const [views, setViews] = useState<Views>({});
  const [defs, setDefs] = useState<Record<string, ItemDef>>({});
  const [imagePath, setImagePath] = useState('');
  const [hotbar, setHotbar] = useState(5);
  const [selected, setSelected] = useState<SlotAddress | null>(null);
  const [quantity, setQuantity] = useState(0); // 0 = the whole stack
  const [tray, setTray] = useState<{ at: SlotAddress; action: string; state: TrayState | null; error?: string; busy: boolean } | null>(null);
  const [pending, setPending] = useState<Set<string>>(new Set());
  const [toast, setToast] = useState<{ kind: 'error' | 'success'; text: string } | null>(null);
  const [drag, setDrag] = useState<{ from: SlotAddress; x: number; y: number; moved: boolean } | null>(null);
  const [menu, setMenu] = useState<ItemMenuState | null>(null);
  const [qty, setQty] = useState<QuantityDialogState | null>(null);
  const [give, setGive] = useState<{ from: SlotAddress; players: NearbyPlayer[] | null; error?: string } | null>(null);
  const toastTimer = useRef<number>();

  useEffect(() => announceReady(), []);

  // You can walk with the inventory open; while a text field has focus, Lua pauses movement so typing doesn't walk.
  useEffect(() => {
    const isField = (el: EventTarget | null) => el instanceof HTMLInputElement && el.type !== 'range';
    const onIn = (e: FocusEvent) => { if (isField(e.target)) void nui('ui:typing', { typing: true }); };
    const onOut = (e: FocusEvent) => { if (isField(e.target)) void nui('ui:typing', { typing: false }); };
    document.addEventListener('focusin', onIn);
    document.addEventListener('focusout', onOut);
    return () => { document.removeEventListener('focusin', onIn); document.removeEventListener('focusout', onOut); };
  }, []);

  useNuiMessage<InventoryOpen>('inventory:open', (d) => {
    setViews({ primary: d.primary, secondary: d.secondary });
    setDefs(d.items);
    setImagePath(d.imagePath);
    setHotbar(d.hotbarSlots ?? 5);
    setSelected(null);
    setQuantity(0);
    setPending(new Set());
    setMenu(null); setQty(null); setGive(null);
    setOpen(true);
  });
  useNuiMessage('inventory:close', () => { setOpen(false); setDrag(null); setMenu(null); setQty(null); setGive(null); setTray(null); });
  useNuiMessage<InventoryDelta>('inventory:delta', (d) => setViews((v) => (v[d.ref] ? { ...v, [d.ref]: applyDelta(v[d.ref]!, d) } : v)));
  useNuiMessage<InventoryView>('inventory:snapshot', (view) => setViews((v) => ({ ...v, [view.ref]: view })));

  const say = useCallback((kind: 'error' | 'success', text: string) => {
    setToast({ kind, text });
    window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => setToast(null), 3200);
  }, []);

  const itemAt = useCallback((a: SlotAddress | null): SlotItem | undefined =>
    a ? views[a.ref]?.items.find((i) => i.slot === a.slot) : undefined, [views]);

  const key = (a: SlotAddress) => `${a.ref}:${a.slot}`;
  const selectedItem = itemAt(selected);
  const selectedDef = selectedItem ? defs[selectedItem.name] : undefined;
  /** Quantity 0 (the default) means the whole stack. */
  const amountFor = useCallback((item: SlotItem) => (quantity > 0 ? Math.min(item.count, Math.floor(quantity)) : item.count), [quantity]);

  /** Every mutation is a server request; the grid only changes when the server's delta arrives. */
  const move = useCallback(async (from: SlotAddress, to: SlotAddress, count?: number) => {
    if (from.ref === to.ref && from.slot === to.slot) return;
    const fv = views[from.ref]; const tv = views[to.ref];
    if (!fv || !tv) return;
    const keys = [key(from), key(to)];
    if (keys.some((k) => pending.has(k))) return;
    setPending((p) => new Set([...p, ...keys]));
    const res = await nui('move', { opId: newOpId(), from, to, count, revisions: { [from.ref]: fv.revision, [to.ref]: tv.revision } });
    setPending((p) => { const n = new Set(p); keys.forEach((k) => n.delete(k)); return n; });
    if (!res.ok) say('error', res.message ?? res.code ?? 'Move failed');
  }, [views, pending, say]);

  const quickTransfer = useCallback((from: SlotAddress, count?: number) => {
    const target: Ref = from.ref === 'primary' ? 'secondary' : 'primary';
    const dest = views[target]; const item = itemAt(from);
    if (!dest || !item) return;
    const def = defs[item.name];
    const same = def?.stack ? dest.items.find((i) => i.name === item.name && JSON.stringify(i.metadata ?? {}) === JSON.stringify(item.metadata ?? {})) : undefined;
    let slot = same?.slot;
    if (!slot) { const used = new Set(dest.items.map((i) => i.slot)); for (let s = 1; s <= dest.slots; s++) if (!used.has(s)) { slot = s; break; } }
    if (!slot) return say('error', 'No free slot');
    void move(from, { ref: target, slot }, count);
  }, [views, defs, itemAt, move, say]);

  const use = useCallback((a: SlotAddress | null) => {
    const item = itemAt(a);
    if (!a || !item) return say('error', t('inv.selectFirst'));
    if (a.ref !== 'primary') return say('error', t('inv.useFromPersonal'));
    if (!defs[item.name]?.usable) return say('error', t('inv.notUsable'));
    void nui('use', { slot: a.slot });
  }, [itemAt, defs, say]);

  /** Opens an item's tray (for example the phone's SIM card slot) and loads what is in it. */
  const openTray = useCallback(async (a: SlotAddress, action: string) => {
    setTray({ at: a, action, state: null, busy: false });
    const res = await nui<TrayState>('itemTray', { slot: a.slot, id: action });
    setTray((t) => (t ? (res.ok && res.data ? { ...t, state: res.data } : { ...t, error: res.message ?? 'Could not open it' }) : t));
  }, []);

  const trayAct = useCallback(async (op: 'insert' | 'remove', slot?: number) => {
    const cur = tray;
    if (!cur) return;
    setTray({ ...cur, busy: true, error: undefined });
    const res = await nui('itemAction', { slot: cur.at.slot, id: cur.action, arg: { op, slot } });
    if (res.ok) say('success', res.message ?? 'Done'); else say('error', res.message ?? 'That did not work');
    const next = await nui<TrayState>('itemTray', { slot: cur.at.slot, id: cur.action });
    setTray((t) => (t ? { ...t, busy: false, state: next.ok && next.data ? next.data : t.state, error: res.ok ? undefined : res.message } : t));
  }, [tray, say]);

  const startGive = useCallback(async (a: SlotAddress | null) => {
    const item = itemAt(a);
    if (!a || !item) return say('error', t('inv.selectFirst'));
    if (a.ref !== 'primary') return say('error', t('inv.useFromPersonal'));
    setGive({ from: a, players: null });
    const res = await nui<NearbyPlayer[]>('nearby');
    if (!res.ok) setGive({ from: a, players: [], error: res.message ?? res.code });
    else setGive({ from: a, players: res.data ?? [] });
  }, [itemAt, say]);

  const confirmGive = useCallback(async (target: number) => {
    if (!give) return;
    const item = itemAt(give.from);
    setGive(null);
    if (!item) return;
    const k = key(give.from);
    setPending((p) => new Set([...p, k]));
    const res = await nui('give', { opId: newOpId(), slot: give.from.slot, count: amountFor(item), target, revision: views.primary?.revision });
    setPending((p) => { const n = new Set(p); n.delete(k); return n; });
    if (res.ok) say('success', res.message ?? 'Given'); else say('error', res.message ?? res.code ?? 'Could not give');
  }, [give, itemAt, amountFor, views, say]);

  const drop = useCallback(async (a: SlotAddress | null) => {
    const item = itemAt(a);
    if (!a || !item) return say('error', t('inv.selectFirst'));
    if (a.ref !== 'primary') return say('error', t('inv.dropUnavailable'));
    const k = key(a);
    if (pending.has(k)) return;
    setPending((p) => new Set([...p, k]));
    const res = await nui('drop', { opId: newOpId(), slot: a.slot, count: amountFor(item), revision: views.primary?.revision });
    setPending((p) => { const n = new Set(p); n.delete(k); return n; });
    if (res.ok) { say('success', res.message ?? 'Dropped'); setQuantity(0); } else say('error', res.message ?? res.code ?? 'Could not drop that');
  }, [itemAt, pending, amountFor, views, say]);

  const close = useCallback(() => { void nui('close'); }, []);

  // Pointer drag (works in CEF without HTML5 drag events).
  useEffect(() => {
    if (!drag) return;
    const onMove = (e: MouseEvent) => setDrag((d) => (d ? { ...d, x: e.clientX, y: e.clientY, moved: true } : d));
    const onUp = (e: MouseEvent) => {
      const el = (e.target as HTMLElement).closest<HTMLElement>('[data-slot]');
      const d = drag; setDrag(null);
      if (!el || !d.moved) return;
      const it = itemAt(d.from);
      void move(d.from, { ref: el.dataset.ref as Ref, slot: Number(el.dataset.slot) }, it && quantity > 0 ? amountFor(it) : undefined);
    };
    window.addEventListener('mousemove', onMove); window.addEventListener('mouseup', onUp);
    return () => { window.removeEventListener('mousemove', onMove); window.removeEventListener('mouseup', onUp); };
  }, [drag, move, itemAt, quantity, amountFor]);

  // Keyboard alternatives.
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (qty || give || menu) { if (e.key === 'Escape') { setQty(null); setGive(null); setMenu(null); } return; }
      if ((e.target as HTMLElement).tagName === 'INPUT') { if (e.key === 'Escape') (e.target as HTMLElement).blur(); return; }
      if (e.key === 'Escape') { e.preventDefault(); close(); return; }
      const cur = selected ?? { ref: 'primary' as Ref, slot: 1 };
      const view = views[cur.ref]; if (!view) return;
      const nav: Record<string, number> = { ArrowRight: 1, ArrowLeft: -1, ArrowDown: 5, ArrowUp: -5 };
      if (e.key in nav) { e.preventDefault(); const n = cur.slot + nav[e.key]; if (n >= 1 && n <= view.slots) setSelected({ ...cur, slot: n }); }
      else if (e.key === 'Tab') { e.preventDefault(); const o: Ref = cur.ref === 'primary' ? 'secondary' : 'primary'; if (views[o]) setSelected({ ref: o, slot: 1 }); }
      else if (e.key === 'Enter') use(cur);
      else if (e.key === 'Delete') void drop(cur);
      else if (e.key.toLowerCase() === 'q') { const it = itemAt(cur); if (it) quickTransfer(cur, amountFor(it)); }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, selected, views, qty, give, menu, use, drop, quickTransfer, itemAt, amountFor, close]);

  const panelHandlers = useMemo(() => ({
    onSelect: (a: SlotAddress) => { setSelected(a); setQuantity(0); },
    onDragStart: (a: SlotAddress, x: number, y: number) => setDrag({ from: a, x, y, moved: false }),
    onShiftClick: (a: SlotAddress) => { const it = itemAt(a); if (it) quickTransfer(a, amountFor(it)); },
    onContext: (a: SlotAddress, x: number, y: number) => { if (itemAt(a)) { setSelected(a); setMenu({ at: a, x, y }); } },
    onUse: (a: SlotAddress) => use(a),
  }), [itemAt, quickTransfer, amountFor, use]);

  if (!open || !views.primary) return null;
  const dragItem = drag?.moved ? itemAt(drag.from) : undefined;
  const maxQty = selectedItem?.count ?? 1;
  const canUse = !!selectedItem && selected?.ref === 'primary' && !!selectedDef?.usable;
  const canGive = !!selectedItem && selected?.ref === 'primary';
  const canDrop = canGive;
  const useReason = !selectedItem ? t('inv.selectFirst') : selected?.ref !== 'primary' ? t('inv.useFromPersonal')
    : !selectedDef?.usable ? t('inv.cantUse', { item: selectedDef?.label ?? selectedItem.name }) : null;

  return (
    <div className="inv-root" onContextMenu={(e) => e.preventDefault()}>
      <div className="inv-frame">
      <header className="inv-header">
        <BrandStack section={t('inv.section')} />
        <CloseHint onClose={close} />
      </header>

      <main className="inv-main">
        <InventoryPanel
          view={views.primary} defs={defs} imagePath={imagePath} pending={pending} selected={selected}
          title={t('inv.personal')} subtitle={t('inv.personalSub')} searchPlaceholder={t('inv.searchPersonal')}
          hotbar={hotbar} footer={<SelectedStrip item={selectedItem} def={selectedDef} imagePath={imagePath} />}
          {...panelHandlers}
        />

        <div className="inv-center v-panel">
          <div className="v-label">{t('inv.quantity')}</div>
          <input
            className="v-input qty-input" type="number" min={0} max={maxQty} value={quantity}
            onChange={(e) => setQuantity(Math.max(0, Math.min(maxQty, Math.floor(Number(e.target.value) || 0))))}
            title="0 = the whole stack"
            aria-label={t('inv.quantity')}
          />
          <button className="v-btn primary block" disabled={!canUse} title={useReason ?? undefined} onClick={() => use(selected)}>{t('inv.use').toUpperCase()}</button>
          <button className="v-btn block" disabled={!canGive} title={!canGive ? t('inv.selectFirst') : undefined} onClick={() => void startGive(selected)}>{t('inv.give').toUpperCase()}</button>
          <button className="v-btn block" disabled={!canDrop} title={!canDrop ? t('inv.dropUnavailable') : undefined} onClick={() => void drop(selected)}>{t('inv.drop').toUpperCase()}</button>
          {selectedItem && useReason && selected?.ref === 'primary' && <div className="inv-reason v-muted">{useReason}</div>}
        </div>

        {views.secondary ? (
          <InventoryPanel
            view={views.secondary} defs={defs} imagePath={imagePath} pending={pending} selected={selected}
            title={views.secondary.label}
            subtitle={views.secondary.type === 'drop' ? t('inv.groundSub') : t('inv.storageSub')}
            searchPlaceholder={views.secondary.type === 'drop' ? t('inv.searchGround') : t('inv.searchStorage')}
            hotbar={0} {...panelHandlers}
          />
        ) : <div className="inv-panel-spacer" />}
      </main>

      </div>

      <footer className="inv-hints v-muted">
        <span><Icon name="mouse" size="1rem" /> {t('inv.hintDrag')}</span>
        <span className="divider" />
        <span><span className="v-key">SHIFT</span> {t('inv.hintShift')}</span>
        <span className="divider" />
        <span><Icon name="mouse" size="1rem" /> Right-click {t('inv.hintRight')}</span>
      </footer>

      {toast && <div className={`v-toast-inline ${toast.kind}`} role="alert"><Icon name={toast.kind === 'error' ? 'alert' : 'check'} size="1rem" />{toast.text}</div>}

      {dragItem && drag && (
        <img className="drag-ghost" style={{ left: drag.x, top: drag.y }} src={`${imagePath}/${defs[dragItem.name]?.image ?? dragItem.name + '.png'}`} alt="" />
      )}

      {menu && (
        <ItemMenu
          state={menu} item={itemAt(menu.at)} def={itemAt(menu.at) ? defs[itemAt(menu.at)!.name] : undefined} hasSecondary={!!views.secondary}
          onClose={() => setMenu(null)}
          onUse={() => { use(menu.at); setMenu(null); }}
          onAction={(id, isTray) => { const a = menu.at; setMenu(null); if (a.ref !== 'primary') return; if (isTray) void openTray(a, id); else void nui('itemAction', { slot: a.slot, id }); }}
          onGive={() => { const a = menu.at; setMenu(null); void startGive(a); }}
          onTransfer={() => { const a = menu.at; const it = itemAt(a); setMenu(null); if (it) quickTransfer(a, amountFor(it)); }}
          onSplit={() => {
            const a = menu.at; const it = itemAt(a); const view = views[a.ref]; setMenu(null);
            if (!it || !view || it.count < 2) return;
            const used = new Set(view.items.map((i) => i.slot));
            for (let s = 1; s <= view.slots; s++) if (!used.has(s)) { setQty({ from: a, to: { ref: a.ref, slot: s }, max: it.count - 1, value: Math.floor(it.count / 2) }); return; }
            say('error', 'No free slot to split into');
          }}
        />
      )}
      {qty && <QuantityDialog state={qty} onCancel={() => setQty(null)} onConfirm={(n) => { const s = qty; setQty(null); void move(s.from, s.to, n); }} />}
      {tray && (
        <TrayDialog state={tray.state} error={tray.error} busy={tray.busy} defs={defs} imagePath={imagePath}
          candidates={tray.state ? (views.primary?.items ?? []).filter((i) => i.name === tray.state!.accepts) : []}
          onClose={() => setTray(null)} onInsert={(slot) => void trayAct('insert', slot)} onRemove={() => void trayAct('remove')} />
      )}
      {give && <GiveDialog players={give.players} error={give.error} onCancel={() => setGive(null)} onPick={(id) => void confirmGive(id)} />}
    </div>
  );
}

function SelectedStrip({ item, def, imagePath }: { item?: SlotItem; def?: ItemDef; imagePath: string }) {
  if (!item || !def) return <div className="inv-strip v-muted">{t('inv.noSelection')}</div>;
  return (
    <div className="inv-strip">
      <img src={`${imagePath}/${def.image ?? item.name + '.png'}`} alt="" onError={(e) => { (e.target as HTMLImageElement).style.visibility = 'hidden'; }} />
      <div className="strip-text">
        <div className="strip-name">{def.label}{typeof item.metadata?.grade === 'string' && <span className={`strip-grade ${String(item.metadata.grade).toLowerCase()}`}>{String(item.metadata.grade)}</span>}</div>
        {def.description && <div className="v-muted strip-desc">{def.description}</div>}
        {item.metadata && (item.metadata.varietyLabel || item.metadata.batch) ? (
          <div className="v-muted strip-desc">
            {[item.metadata.varietyLabel && `Variety: ${String(item.metadata.varietyLabel)}`, typeof item.metadata.quality === 'number' && `Quality ${item.metadata.quality}`,
              item.metadata.batch && `Batch ${String(item.metadata.batch)}`].filter(Boolean).join(' · ')}
          </div>
        ) : null}
      </div>
      <div className="v-muted strip-weight">{t('inv.each', { w: (def.weight / 1000).toFixed(1) })}</div>
    </div>
  );
}
