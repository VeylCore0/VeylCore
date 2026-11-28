import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { announceReady, newOpId, nui, useNuiMessage, type NearbyPlayer, type SlotItem } from '@veyl/ui';
import { BodyPanel } from './BodyPanel';
import { Grid, type SlotHandlers } from './Grid';
import { ItemMenu, type ItemMenuState } from './ItemMenu';
import { QuantityDialog, type QuantityDialogState } from './QuantityDialog';
import { GiveDialog } from './GiveDialog';
import { TrayDialog, type TrayState } from './TrayDialog';
import { Tooltip, type TipState } from './Tooltip';
import { ShopPanel, type ShopInfo, type ShopProduct } from './ShopPanel';
import { key, kgText, type Category, type Def, type Delta, type EquipSlot, type OpenPayload, type Profile, type Ref, type SlotAddress, type View } from './types';

export type { Ref, SlotAddress } from './types';
type Views = Partial<Record<Ref, View>>;

const DEFAULT_CATEGORIES: Category[] = [{ id: 'all', label: 'All' }];

function applyDelta(view: View, d: Delta): View {
  const map = new Map(view.items.map((i) => [i.slot, i] as const));
  for (const c of d.slots) { if (c.item) map.set(c.slot, c.item); else map.delete(c.slot); }
  return { ...view, revision: d.revision, weight: d.weight, items: [...map.values()] };
}

/** A diamond badge like the panel headers in the design: a teal outline with a glyph inside. */
function Diamond({ d }: { d: string }) {
  return <span className="idiamond"><svg viewBox="0 0 24 24"><path d={d} /></svg></span>;
}
const G = {
  user: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM5 20c0-4 3-6 7-6s7 2 7 6',
  pack: 'M8 8V6a4 4 0 0 1 8 0v2M6 8h12l1 12H5zM9 14h6',
  locker: 'M12 4v10M8 10l4 4 4-4M5 18h14',
  ground: 'M12 3v10M8 9l4 4 4-4M4 19h16',
};

export function App() {
  const [open, setOpen] = useState(false);
  const [views, setViews] = useState<Views>({});
  const [defs, setDefs] = useState<Record<string, Def>>({});
  const [imagePath, setImagePath] = useState('');
  const [hotbar, setHotbar] = useState(5);
  const [equipSlots, setEquipSlots] = useState<EquipSlot[]>([]);
  const [categories, setCategories] = useState<Category[]>(DEFAULT_CATEGORIES);
  const [profile, setProfile] = useState<Profile | undefined>();
  const [selected, setSelected] = useState<SlotAddress | null>(null);
  const [quantity, setQuantity] = useState(0); // 0 = the whole stack
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState('all');
  const [tray, setTray] = useState<{ at: SlotAddress; action: string; state: TrayState | null; error?: string; busy: boolean } | null>(null);
  const [pending, setPending] = useState<Set<string>>(new Set());
  const [toast, setToast] = useState<{ kind: 'error' | 'success'; text: string } | null>(null);
  const [drag, setDrag] = useState<{ from: SlotAddress; x: number; y: number; moved: boolean } | null>(null);
  const [menu, setMenu] = useState<ItemMenuState | null>(null);
  const [qty, setQty] = useState<QuantityDialogState | null>(null);
  const [give, setGive] = useState<{ from: SlotAddress; players: NearbyPlayer[] | null; error?: string } | null>(null);
  const [tip, setTip] = useState<TipState | null>(null);
  const [shop, setShop] = useState<ShopInfo | null>(null);
  const [buying, setBuying] = useState(false);
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

  useNuiMessage<OpenPayload>('inventory:open', (d) => {
    setViews({ primary: d.primary, secondary: d.secondary, equip: d.equip, backpack: d.backpack });
    setDefs(d.items);
    setImagePath(d.imagePath);
    setHotbar(d.hotbarSlots ?? 5);
    setEquipSlots(d.equipSlots ?? []);
    setCategories(d.categories && d.categories.length ? d.categories : DEFAULT_CATEGORIES);
    setShop(d.shop ?? null); setBuying(false);
    setProfile(d.profile);
    setSelected(null); setQuantity(0); setSearch(''); setCategory('all'); setPending(new Set());
    setMenu(null); setQty(null); setGive(null); setTip(null);
    setOpen(true);
  });
  useNuiMessage('inventory:close', () => { setOpen(false); setDrag(null); setMenu(null); setQty(null); setGive(null); setTray(null); setTip(null); });
  useNuiMessage<Delta>('inventory:delta', (d) => setViews((v) => (v[d.ref] ? { ...v, [d.ref]: applyDelta(v[d.ref]!, d) } : v)));
  useNuiMessage<ShopInfo>('inventory:shop', (s) => setShop(s));
  useNuiMessage<View>('inventory:snapshot', (view) => setViews((v) => ({ ...v, [view.ref]: view })));

  const say = useCallback((kind: 'error' | 'success', text: string) => {
    setToast({ kind, text });
    window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => setToast(null), 3200);
  }, []);

  const itemAt = useCallback((a: SlotAddress | null): SlotItem | undefined => (a ? views[a.ref]?.items.find((i) => i.slot === a.slot) : undefined), [views]);
  const selectedItem = itemAt(selected);
  const amountFor = useCallback((item: SlotItem) => (quantity > 0 ? Math.min(item.count, Math.floor(quantity)) : item.count), [quantity]);
  const mine = (r: Ref) => r === 'primary' || r === 'backpack';

  /** A free slot (or a stack the item can join) in a container. */
  const slotFor = useCallback((ref: Ref, item: SlotItem): number | undefined => {
    const view = views[ref];
    if (!view) return undefined;
    const def = defs[item.name];
    if (def?.stack) {
      const same = view.items.find((i) => i.name === item.name && JSON.stringify(i.metadata ?? {}) === JSON.stringify(item.metadata ?? {}) && i.count + item.count <= (def.maxStack || 1));
      if (same) return same.slot;
    }
    const used = new Set(view.items.map((i) => i.slot));
    for (let s = 1; s <= view.slots; s++) if (!used.has(s)) return s;
    return undefined;
  }, [views, defs]);

  /** Every mutation is a server request; the grids only change when the server's delta arrives. */
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
    const item = itemAt(from);
    if (!item) return;
    const target: Ref = from.ref === 'primary' ? (views.secondary ? 'secondary' : 'backpack')
      : from.ref === 'backpack' ? (views.secondary ? 'secondary' : 'primary') : 'primary';
    if (!views[target]) return say('error', 'Nowhere to put it');
    const slot = slotFor(target, item);
    if (!slot) return say('error', 'No free slot');
    void move(from, { ref: target, slot }, count);
  }, [views, itemAt, slotFor, move, say]);

  const equip = useCallback((a: SlotAddress) => {
    const item = itemAt(a); const def = item ? defs[item.name] : undefined;
    if (!item || !def?.equip) return say('error', 'That cannot be worn');
    const es = equipSlots.find((s) => s.id === def.equip);
    if (!es) return say('error', 'There is no slot for that');
    void move(a, { ref: 'equip', slot: es.slot }, 1);
  }, [itemAt, defs, equipSlots, move, say]);

  const unequip = useCallback((a: SlotAddress) => {
    const item = itemAt(a);
    if (!item) return;
    const ref: Ref = slotFor('primary', item) ? 'primary' : 'backpack';
    const slot = slotFor(ref, item);
    if (!slot) return say('error', 'No free slot');
    void move(a, { ref, slot }, 1);
  }, [itemAt, slotFor, move, say]);

  const use = useCallback((a: SlotAddress | null) => {
    const item = itemAt(a);
    if (!a || !item) return say('error', 'Select an item first');
    if (!mine(a.ref)) return say('error', 'Move it to your pockets or backpack to use it');
    if (!defs[item.name]?.usable) return say('error', `${defs[item.name]?.label ?? item.name} cannot be used`);
    void nui('use', { slot: a.slot, ref: a.ref });
  }, [itemAt, defs, say]);

  /** Double click: wear it if it can be worn, use it if it can be used, otherwise send it across. */
  const primaryAction = useCallback((a: SlotAddress) => {
    const item = itemAt(a); const def = item ? defs[item.name] : undefined;
    if (!item) return;
    if (a.ref === 'equip') return unequip(a);
    if (def?.equip && mine(a.ref)) return equip(a);
    if (def?.usable && mine(a.ref)) return use(a);
    quickTransfer(a, amountFor(item));
  }, [itemAt, defs, unequip, equip, use, quickTransfer, amountFor]);

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
    if (!a || !item) return say('error', 'Select an item first');
    if (!mine(a.ref)) return say('error', 'Move it to your pockets or backpack first');
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
    const res = await nui('give', { opId: newOpId(), slot: give.from.slot, ref: give.from.ref, count: amountFor(item), target, revision: views[give.from.ref]?.revision });
    setPending((p) => { const n = new Set(p); n.delete(k); return n; });
    if (res.ok) say('success', res.message ?? 'Given'); else say('error', res.message ?? res.code ?? 'Could not give');
  }, [give, itemAt, amountFor, views, say]);

  const drop = useCallback(async (a: SlotAddress | null) => {
    const item = itemAt(a);
    if (!a || !item) return say('error', 'Select an item first');
    if (!mine(a.ref)) return say('error', 'Only pockets and backpack items can be dropped');
    const k = key(a);
    if (pending.has(k)) return;
    setPending((p) => new Set([...p, k]));
    const res = await nui('drop', { opId: newOpId(), slot: a.slot, ref: a.ref, count: amountFor(item), revision: views[a.ref]?.revision });
    setPending((p) => { const n = new Set(p); n.delete(k); return n; });
    if (res.ok) { say('success', res.message ?? 'Dropped'); setQuantity(0); } else say('error', res.message ?? res.code ?? 'Could not drop that');
  }, [itemAt, pending, amountFor, views, say]);

  const buy = useCallback(async (p: ShopProduct, count: number, method: 'cash' | 'bank') => {
    if (buying) return;
    setBuying(true);
    const res = await nui('shopBuy', { opId: newOpId(), index: p.index, count, method, expectedTotal: p.price * count });
    setBuying(false);
    if (res.ok) say('success', res.message ?? 'Bought'); else say('error', res.message ?? res.code ?? 'Could not buy that');
  }, [buying, say]);

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
      const to: SlotAddress = { ref: el.dataset.ref as Ref, slot: Number(el.dataset.slot) };
      // Dropping a stack on a wear slot wears one of it.
      const count = to.ref === 'equip' ? 1 : it && quantity > 0 ? amountFor(it) : undefined;
      void move(d.from, to, count);
    };
    window.addEventListener('mousemove', onMove); window.addEventListener('mouseup', onUp);
    return () => { window.removeEventListener('mousemove', onMove); window.removeEventListener('mouseup', onUp); };
  }, [drag, move, itemAt, quantity, amountFor]);

  // Keyboard alternatives.
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (qty || give || menu || tray) { if (e.key === 'Escape') { setQty(null); setGive(null); setMenu(null); setTray(null); } return; }
      if ((e.target as HTMLElement).tagName === 'INPUT') { if (e.key === 'Escape') (e.target as HTMLElement).blur(); return; }
      if (e.key === 'Escape') { e.preventDefault(); close(); return; }
      if (!selected) return;
      if (e.key === 'Enter') primaryAction(selected);
      else if (e.key === 'Delete') void drop(selected);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, selected, qty, give, menu, tray, primaryAction, drop, close]);

  const q = search.trim().toLowerCase();
  const matches = useCallback((item: SlotItem | undefined) => {
    if (!item) return q === '' && category === 'all';
    const def = defs[item.name];
    if (category !== 'all' && (def?.category ?? 'misc') !== category) return false;
    return q === '' || (def?.label ?? item.name).toLowerCase().includes(q);
  }, [q, category, defs]);

  const handlers: SlotHandlers = useMemo(() => ({
    onSelect: (a) => { setSelected(a); setQuantity(0); },
    onDragStart: (a, x, y) => { setTip(null); setDrag({ from: a, x, y, moved: false }); },
    onShiftClick: (a) => { const it = itemAt(a); if (it) quickTransfer(a, amountFor(it)); },
    onContext: (a, x, y) => { if (itemAt(a)) { setSelected(a); setTip(null); setMenu({ at: a, x, y }); } },
    onDouble: (a) => primaryAction(a),
    onHover: (a, x, y) => {
      const it = a ? itemAt(a) : undefined;
      setTip(it ? { item: it, def: defs[it.name], x, y } : null);
    },
  }), [itemAt, quickTransfer, amountFor, primaryAction, defs]);

  if (!open || !views.primary) return null;
  const dragItem = drag?.moved ? itemAt(drag.from) : undefined;
  const maxQty = selectedItem?.count ?? 1;
  const total = (f: (v: View) => number) => (['primary', 'backpack', 'equip'] as Ref[]).reduce((n, r) => n + (views[r] ? f(views[r]!) : 0), 0);
  const cash = total((v) => v.items.filter((i) => i.name === 'money').reduce((n, i) => n + i.count, 0));
  const carried = total((v) => v.weight);
  const carryMax = (views.primary?.maxWeight ?? 0) + (views.backpack?.maxWeight ?? 0);
  const sec = views.secondary;
  const secIsGround = sec?.type === 'drop';
  const panelWeight = (v: View) => `${kgText(v.weight)}/${kgText(v.maxWeight)}kg`;

  return (
    <div className="inv-root" onContextMenu={(e) => e.preventDefault()}>
      <button className="close-hint" onClick={close}><kbd>ESC</kbd>Close</button>
      <div className="inv-stage">
        <BodyPanel equip={views.equip} slots={equipSlots} defs={defs} imagePath={imagePath} profile={profile} cash={cash} carried={carried} carryMax={carryMax}
          pending={pending} selected={selected} handlers={handlers} matches={matches} />

        <div className="col-mid">
          <section className="ipanel player-panel" aria-label="Pockets">
            <header className="ipanel-head">
              <Diamond d={G.user} />
              <div><h3>{profile?.name || views.primary.label}</h3><p>{panelWeight(views.primary)}</p></div>
              <div className="head-tools">
                <input className="ifield" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search..." aria-label="Search items" />
                <input className="ifield qty" type="number" min={0} max={maxQty} value={quantity} title="Amount to move: 0 means the whole stack" aria-label="Amount"
                  onChange={(e) => setQuantity(Math.max(0, Math.min(maxQty, Math.floor(Number(e.target.value) || 0))))} />
              </div>
            </header>
            <div className="ichips" role="tablist">
              {categories.map((c) => <button key={c.id} role="tab" aria-selected={category === c.id} className={`ichip${category === c.id ? ' on' : ''}`} onClick={() => setCategory(c.id)}>{c.label}</button>)}
            </div>
            <div className="grid-scroll">
              <Grid view={views.primary} defs={defs} imagePath={imagePath} pending={pending} selected={selected} hotbar={hotbar} cols={5} matches={matches} handlers={handlers} />
            </div>
          </section>

          {views.backpack && (
            <section className="ipanel pack-panel" aria-label="Backpack">
              <header className="ipanel-head">
                <Diamond d={G.pack} />
                <div><h3>{views.backpack.label}</h3><p>{panelWeight(views.backpack)}</p></div>
              </header>
              <div className="grid-scroll">
                <Grid view={views.backpack} defs={defs} imagePath={imagePath} pending={pending} selected={selected} cols={5} matches={matches} handlers={handlers} />
              </div>
            </section>
          )}
        </div>

        <div className="col-right">
          {shop ? (
            <ShopPanel shop={shop} defs={defs} imagePath={imagePath} busy={buying} onBuy={(p, n, m) => void buy(p, n, m)} matches={(label) => q === '' || label.toLowerCase().includes(q)} />
          ) : sec ? (
            <section className="ipanel side-panel" aria-label={sec.label}>
              <header className="ipanel-head">
                <Diamond d={secIsGround ? G.ground : G.locker} />
                <div><h3>{sec.label}</h3><p>{panelWeight(sec)}</p></div>
              </header>
              <div className="grid-scroll tall">
                <Grid view={sec} defs={defs} imagePath={imagePath} pending={pending} selected={selected} cols={4} matches={matches} handlers={handlers} />
              </div>
            </section>
          ) : null}
        </div>
      </div>

      <footer className="inv-hints">
        <span><kbd>Drag</kbd> move items</span>
        <span><kbd>Shift</kbd> + click send across</span>
        <span><kbd>Double click</kbd> use or wear</span>
        <span><kbd>Right click</kbd> more</span>
        <span><kbd>Del</kbd> drop</span>
      </footer>

      {toast && <div className={`itoast ${toast.kind}`} role="alert">{toast.text}</div>}
      {dragItem && drag && <img className="drag-ghost" style={{ left: drag.x, top: drag.y }} src={`${imagePath}/${defs[dragItem.name]?.image ?? dragItem.name + '.png'}`} alt="" />}
      {tip && !drag && !menu && <Tooltip tip={tip} />}

      {menu && (
        <ItemMenu
          state={menu} item={itemAt(menu.at)} def={itemAt(menu.at) ? defs[itemAt(menu.at)!.name] : undefined}
          secondaryOpen={!!sec && !secIsGround ? true : !!sec} secondaryLabel={secIsGround ? 'the ground' : sec?.label} hasBackpack={!!views.backpack}
          onClose={() => setMenu(null)}
          onUse={() => { use(menu.at); setMenu(null); }}
          onEquip={() => { equip(menu.at); setMenu(null); }}
          onUnequip={() => { unequip(menu.at); setMenu(null); }}
          onGive={() => { const a = menu.at; setMenu(null); void startGive(a); }}
          onDrop={() => { const a = menu.at; setMenu(null); void drop(a); }}
          onMove={(to) => {
            const a = menu.at; const it = itemAt(a); setMenu(null);
            if (!it) return;
            const slot = slotFor(to, it);
            if (!slot) return say('error', 'No free slot');
            void move(a, { ref: to, slot }, amountFor(it));
          }}
          onAction={(id, isTray) => { const a = menu.at; setMenu(null); if (!mine(a.ref)) return; if (isTray) void openTray(a, id); else void nui('itemAction', { slot: a.slot, id }); }}
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
        <TrayDialog state={tray.state} error={tray.error} busy={tray.busy} defs={defs as never} imagePath={imagePath}
          candidates={tray.state ? (views.primary?.items ?? []).filter((i) => i.name === tray.state!.accepts) : []}
          onClose={() => setTray(null)} onInsert={(slot) => void trayAct('insert', slot)} onRemove={() => void trayAct('remove')} />
      )}
      {give && <GiveDialog players={give.players} error={give.error} onCancel={() => setGive(null)} onPick={(id) => void confirmGive(id)} />}
    </div>
  );
}
