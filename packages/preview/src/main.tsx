// VeylCore UI preview — DEVELOPMENT ONLY. Mounts the real app components and drives them with the same
// message envelope Lua uses. The dev NUI handler is ignored inside FiveM (see setDevNuiHandler).
import { createRoot } from 'react-dom/client';
import { useEffect, useState, type ComponentType } from 'react';
import { devEmit, setDevNuiHandler, type InventoryOpen, type NuiResponse, type TargetState } from '@veyl/ui';
import { App as InventoryApp } from '../../inventory-ui/src/App';
import { App as ShopApp } from '../../shop-ui/src/App';
import { App as BankApp } from '../../bank-ui/src/App';
import { App as HudApp } from '../../hud-ui/src/App';
import { App as TargetApp } from '../../target-ui/src/App';
import { App as AppearanceApp } from '../../appearance-ui/src/App';
import { App as VehicleApp } from '../../vehicle-ui/src/App';
import { App as DrugsApp } from '../../drugs-ui/src/App';
import { App as ApartmentsApp } from '../../apartments-ui/src/App';
import { App as DoorsApp } from '../../doorlocks-ui/src/App';
import { App as PhoneApp } from '../../phone-ui/src/App';
import { App as CityhallApp } from '../../cityhall-ui/src/App';
import { App as ManagementApp } from '../../management-ui/src/App';
import { App as EmotesApp } from '../../emotes-ui/src/App';
import { App as MedicalApp } from '../../medical-ui/src/App';
import { App as DispatchApp } from '../../dispatch-ui/src/App';
import { App as MdtApp } from '../../mdt-ui/src/App';
import { isMisc, miscDemo, miscHandler, miscOpen, type MiscScreen } from './miscMock';
import { phoneApi, phoneClose, phoneDemo, phoneReset, phoneSession, phoneVoice } from './phoneMock';
import { doorEditor, doorHandler, doorManage } from './doorMock';
import { aptCatalog, aptDashboard, aptFurniture, aptHandler } from './aptMock';
import type { AppearanceOpen, Slot } from '../../appearance-ui/src/types';
import '../../inventory-ui/src/inventory.css';
import '../../shop-ui/src/shop.css';
import '../../bank-ui/src/bank.css';
import '../../hud-ui/src/hud.css';
import '../../target-ui/src/target.css';
import '../../appearance-ui/src/appearance.css';
import '../../vehicle-ui/src/vehicles.css';
import '../../drugs-ui/src/drugs.css';
import '../../apartments-ui/src/apartments.css';
import '../../doorlocks-ui/src/doorlocks.css';
import '../../phone-ui/src/phone.css';
import '../../cityhall-ui/src/cityhall.css';
import '../../management-ui/src/management.css';
import '../../emotes-ui/src/emotes.css';
import '../../medical-ui/src/medical.css';
import '../../dispatch-ui/src/dispatch.css';
import '../../mdt-ui/src/mdt.css';
import './preview.css';
import * as F from './fixtures';


type Screen = 'inventory' | 'shop' | 'bank' | 'hud' | 'target' | 'creator' | 'clothing' | 'barber' | 'garage' | 'impound' | 'dealer' | 'journal' | 'grow' | 'table' | 'phone' | MiscScreen | 'aptLease' | 'aptHome' | 'aptFurn' | 'aptDesk' | 'aptWardrobe' | 'aptBell' | 'doorEdit' | 'doorManage' | 'doorHint';
const AP_MODE = { creator: 'create', clothing: 'clothing', barber: 'barber' } as const;
const isAppearance = (s: Screen): s is keyof typeof AP_MODE => s in AP_MODE;
const isVehicle = (s: Screen) => s === 'garage' || s === 'impound' || s === 'dealer' || s === 'journal' || s === 'grow' || s === 'table';
const isApt = (s: Screen) => s.startsWith('apt');
const isDoor = (s: Screen) => s.startsWith('door');
const backdropOf = (s: Screen) => (isAppearance(s) || isVehicle(s) || s === 'phone' || isMisc(s) || isApt(s) || isDoor(s) ? 'hud' : s);
const clone = <T,>(v: T): T => JSON.parse(JSON.stringify(v));
let apState: AppearanceOpen | null = null;
type Mode = 'normal' | 'loading' | 'empty' | 'error' | 'restricted' | 'pending';
const SCREENS: { id: Screen; label: string; app: ComponentType }[] = [
  { id: 'inventory', label: 'Inventory', app: InventoryApp }, { id: 'shop', label: 'Shop', app: ShopApp },
  { id: 'bank', label: 'Bank', app: BankApp }, { id: 'hud', label: 'HUD', app: HudApp }, { id: 'target', label: 'Target', app: TargetApp },
  { id: 'creator', label: 'Creator', app: AppearanceApp }, { id: 'clothing', label: 'Clothing', app: AppearanceApp }, { id: 'barber', label: 'Barber', app: AppearanceApp },
  { id: 'garage', label: 'Garage', app: VehicleApp }, { id: 'impound', label: 'Impound', app: VehicleApp }, { id: 'dealer', label: 'Dealer', app: VehicleApp },
  { id: 'journal', label: 'Journal', app: DrugsApp }, { id: 'table', label: 'Table', app: DrugsApp }, { id: 'grow', label: 'Grow HUD', app: DrugsApp },
  { id: 'phone', label: 'Phone', app: PhoneApp },
  { id: 'cityhall', label: 'City Hall', app: CityhallApp }, { id: 'management', label: 'Management', app: ManagementApp }, { id: 'emotes', label: 'Emotes', app: EmotesApp },
  { id: 'medical', label: 'Death screen', app: MedicalApp }, { id: 'dispatch', label: 'Dispatch', app: DispatchApp }, { id: 'mdt', label: 'MDT', app: MdtApp },
  { id: 'aptLease', label: 'Leasing', app: ApartmentsApp }, { id: 'aptHome', label: 'Home', app: ApartmentsApp },
  { id: 'aptFurn', label: 'Furniture', app: ApartmentsApp }, { id: 'aptDesk', label: 'Desk', app: ApartmentsApp },
  { id: 'aptWardrobe', label: 'Wardrobe', app: ApartmentsApp }, { id: 'aptBell', label: 'Doorbell', app: ApartmentsApp },
  { id: 'doorEdit', label: 'Doors', app: DoorsApp }, { id: 'doorManage', label: 'Door mgr', app: DoorsApp }, { id: 'doorHint', label: 'Door hint', app: DoorsApp },
];
const MODES: Mode[] = ['normal', 'loading', 'empty', 'error', 'restricted', 'pending'];

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Mock backend: behaviour depends on the selected mode so every UI state can be reviewed. */
function installHandler(screen: Screen, mode: Mode, inv: { current: InventoryOpen }) {
  setDevNuiHandler(async (action, payload): Promise<NuiResponse> => {
    if (action === 'ui:ready') return { ok: true };
    if (isApt(screen)) return aptHandler(action, payload, mode);
    if (isMisc(screen)) return miscHandler(screen, action, payload);
    if (screen === 'phone') {
      if (action === 'close') { phoneClose(); return { ok: true }; }
      if (action === 'ui:typing' || action === 'waypoint' || action === 'openExternal') return { ok: true };
      if (action === 'location') return { ok: true, data: { label: 'Legion Square, Pillbox Hill' } };
      if (action === 'api') {
        if (mode === 'pending') await wait(2000);
        if (mode === 'error') return { ok: false, code: 'DATABASE_ERROR', message: 'Demo: the phone service is unavailable.' };
        const p = payload as { name: string; args: unknown[] };
        return phoneApi(p.name, p.args ?? []);
      }
    }
    if (isDoor(screen)) return doorHandler(action, payload);
    if (action === 'close') { devEmit(isAppearance(screen) ? 'appearance:close' : screen === 'impound' ? 'garage:close' : screen === 'journal' || screen === 'table' ? 'drugs:close' : `${screen}:close`); return { ok: true }; }
    if (isAppearance(screen) && (action === 'camera' || action === 'rotate')) return { ok: true };
    if (isAppearance(screen) && action === 'change') {
      const p = payload as { key: string; value: Slot };
      if (apState) apState.values[p.key] = p.value;
      return { ok: true, data: { value: p.value } };
    }
    if (mode === 'pending') await wait(2000);
    if (mode === 'error') return { ok: false, code: 'DATABASE_ERROR', message: 'Demo: the server rejected this request.' };
    if (mode === 'restricted') return { ok: false, code: 'NO_PERMISSION', message: 'Demo: you do not have access to this.' };
    switch (`${screen}:${action}`) {
      case 'inventory:move': {
        const { from, to, count } = payload as { from: { ref: 'primary' | 'secondary'; slot: number }; to: { ref: 'primary' | 'secondary'; slot: number }; count?: number };
        const o = inv.current;
        const src = o[from.ref]!.items.find((i) => i.slot === from.slot);
        if (!src) return { ok: false, code: 'NOT_FOUND', message: 'Nothing in that slot' };
        const n = Math.min(count ?? src.count, src.count);
        const dst = o[to.ref]!.items.find((i) => i.slot === to.slot);
        const fromItems = o[from.ref]!.items.filter((i) => i.slot !== from.slot);
        if (n < src.count) fromItems.push({ ...src, count: src.count - n });
        let toItems = (from.ref === to.ref ? fromItems : o[to.ref]!.items).filter((i) => i.slot !== to.slot);
        if (dst && dst.name === src.name) toItems.push({ ...dst, count: dst.count + n });
        else { toItems.push({ slot: to.slot, name: src.name, count: n }); if (dst && n === src.count) { if (from.ref === to.ref) toItems.push({ ...dst, slot: from.slot }); else fromItems.push({ ...dst, slot: from.slot }); } }
        if (from.ref === to.ref) toItems = toItems.filter((i, idx, arr) => arr.findIndex((j) => j.slot === i.slot) === idx);
        const next = { ...o, [from.ref]: { ...o[from.ref]!, items: from.ref === to.ref ? toItems : fromItems, revision: o[from.ref]!.revision + 1 } };
        if (from.ref !== to.ref) next[to.ref] = { ...o[to.ref]!, items: toItems, revision: o[to.ref]!.revision + 1 };
        inv.current = next as InventoryOpen;
        devEmit('inventory:snapshot', next[from.ref]);
        if (from.ref !== to.ref) devEmit('inventory:snapshot', next[to.ref]);
        return { ok: true };
      }
      case 'inventory:use': return { ok: true };
      case 'inventory:drop': {
        // Demo: the right-hand box becomes the ground and receives the item.
        const p = payload as { slot: number; count: number };
        const o = inv.current;
        const it = o.primary.items.find((i) => i.slot === p.slot);
        if (!it) return { ok: false, code: 'NOT_FOUND', message: 'Nothing in that slot' };
        const n = Math.min(p.count, it.count);
        const rest = o.primary.items.filter((i) => i.slot !== p.slot);
        if (n < it.count) rest.push({ ...it, count: it.count - n });
        const ground = o.secondary?.type === 'drop' ? o.secondary : { ref: 'secondary' as const, id: 'drop:demo', label: 'Ground', type: 'drop' as const, slots: 20, maxWeight: 200000, weight: 0, revision: 0, items: [] };
        const used = new Set(ground.items.map((i) => i.slot));
        let slot = 1; while (used.has(slot)) slot++;
        const next = { ...o, primary: { ...o.primary, items: rest, revision: o.primary.revision + 1 }, secondary: { ...ground, id: 'drop:demo', items: [...ground.items, { ...it, slot, count: n }], revision: ground.revision + 1 } };
        inv.current = next;
        devEmit('inventory:snapshot', next.primary);
        devEmit('inventory:snapshot', next.secondary);
        return { ok: true, message: `Dropped ${n}x (demo)` };
      }
      case 'inventory:nearby': return { ok: true, data: [{ id: 14, name: 'Jamie Cole', distance: 1.6 }, { id: 22, name: 'Riley Park', distance: 2.4 }] };
      case 'inventory:give': return { ok: true, message: 'Gave items (demo)' };
      case 'shop:checkout': {
        const p = payload as { expectedTotal: number; method: 'cash' | 'bank' };
        const balances = { cash: 420, bank: 12840 };
        balances[p.method] -= p.expectedTotal;
        return { ok: true, message: `Paid $${p.expectedTotal} (demo)`, data: { total: p.expectedTotal, delivered: [], refunded: 0, balances } };
      }
      case 'bank:overview': return { ok: true, data: F.bankOverview(mode === 'empty') };
      case 'bank:deposit': case 'bank:withdraw': return { ok: true, message: 'Done (demo)', data: F.bankOverview(false) };
      case 'bank:resolveRecipient': return { ok: true, data: { token: 'demo', name: 'Jamie Cole', accountMasked: 'VC •••• 7731' } };
      case 'bank:transfer': return { ok: true, message: 'Transfer sent (demo)' };
      case 'bank:history': return { ok: true, data: mode === 'empty' ? { rows: [], nextOffset: null } : F.bankHistory((payload as { offset: number }).offset) };
      case 'clothing:checkout': case 'barber:checkout': {
        if (!apState) return { ok: false };
        const p = payload as { expectedTotal: number; method: 'cash' | 'bank' };
        apState.store!.balances[p.method] -= p.expectedTotal;
        apState.original = clone(apState.values);
        return { ok: true, message: `Paid ${p.expectedTotal} (demo)`, data: clone(apState) };
      }
      case 'clothing:wearOutfit': {
        if (!apState) return { ok: false };
        const o = apState.store!.outfits!.find((x) => x.id === (payload as { id: number }).id)!;
        Object.assign(apState.values, clone(o.slots));
        return { ok: true, data: clone(apState) };
      }
      case 'clothing:saveOutfit': {
        const list = [{ id: Date.now(), name: String((payload as { name: string }).name), slots: clone(apState!.values) }, ...(apState!.store!.outfits ?? [])];
        apState!.store!.outfits = list;
        return { ok: true, message: 'Outfit saved (demo)', data: list };
      }
      case 'clothing:deleteOutfit': {
        const list = (apState!.store!.outfits ?? []).filter((o) => o.id !== (payload as { id: number }).id);
        apState!.store!.outfits = list;
        return { ok: true, message: 'Outfit deleted (demo)', data: list };
      }
      case 'table:craftStart': {
        const p = payload as { recipe: string; units: number };
        return { ok: true, data: { token: 'demo', durationMs: 2500 * p.units, challenge: p.recipe === 'roll_joints' ? 'timing' : 'calibration' } };
      }
      case 'table:craftComplete': return { ok: true, message: 'Made 4x Joint (Premium) (demo)', data: { state: 'delivered', view: F.weedTable(false) } };
      case 'table:craftCancel': return { ok: true, message: 'Cancelled. Supplies returned. (demo)', data: { view: F.weedTable(false) } };
      case 'table:collectTray': return { ok: true, message: 'Collected everything (demo)', data: { view: F.weedTable(false) } };
      case 'journal:refresh': return { ok: true, data: F.journal(false) };
      case 'journal:waypoint': return { ok: true, message: 'Waypoint set' };
      case 'garage:takeOut': devEmit('garage:close'); return { ok: true, message: 'Vehicle ready (demo)' };
      case 'impound:takeOut': devEmit('garage:close'); return { ok: true, message: 'Released (demo)' };
      case 'dealer:purchase': {
        const p = payload as { model: string; expectedPrice: number };
        if (p.model === 'banshee' && p.expectedPrice !== 99000) return { ok: false, code: 'PRICE_CHANGED', message: 'The price is now $99,000 (demo)', data: { price: 99000 } };
        devEmit('dealer:close'); return { ok: true, message: 'Bought (demo)' };
      }
      case 'creator:finish': devEmit('appearance:close'); return { ok: true };
      case 'creator:sex': { apState = F.appearanceOpen('create', false); apState.sex = (payload as { sex: 'm' | 'f' }).sex; return { ok: true, data: clone(apState) }; }
      default: return { ok: false, code: 'NOT_IMPLEMENTED', message: `No demo handler for ${action}` };
    }
  });
}

function open(screen: Screen, mode: Mode, inv: { current: InventoryOpen }) {
  const empty = mode === 'empty';
  switch (screen) {
    case 'inventory': inv.current = F.inventoryOpen(empty); devEmit('inventory:open', inv.current); break;
    case 'shop':
      if (mode === 'loading') devEmit('shop:open', null);
      else if (mode === 'restricted') { devEmit('shop:open', null); devEmit('shop:error', { message: 'This store is staff-only (demo).', restricted: true }); }
      else { devEmit('shop:open', F.shopOpen(empty)); if (!empty) setTimeout(() => devEmit('shop:demoBasket', F.shopDemoBasket), 30); }
      break;
    case 'bank':
      devEmit('bank:open', mode === 'loading' ? null : F.bankOverview(empty));
      if (mode === 'error') devEmit('bank:error', { message: 'Banking is unavailable right now (demo).' });
      break;
    case 'hud': devEmit('hud:frame', F.hudFrame); break;
    case 'doorEdit': devEmit('door:open', { view: 'editor', data: doorEditor() }); break;
    case 'doorManage': devEmit('door:open', { view: 'manage', data: doorManage() }); break;
    case 'doorHint': devEmit('door:status', { visible: true, name: 'MRPD Front Desk', locked: true }); break;
    case 'aptLease': devEmit('apt:open', { view: 'leasing', data: aptCatalog(empty) }); break;
    case 'aptHome': devEmit('apt:open', { view: 'dashboard', data: aptDashboard(empty) }); break;
    case 'aptFurn': devEmit('apt:open', { view: 'furniture', data: aptFurniture() }); break;
    case 'aptDesk': devEmit('apt:open', { view: 'desk', data: { building: 'starlite', label: 'Starlite Motel front desk', tab: 'directory', directory: true } }); break;
    case 'aptWardrobe': devEmit('apt:open', { view: 'wardrobe', data: { outfits: [{ id: 1, name: 'Work clothes' }, { id: 2, name: 'Night out' }], max: 10 } }); break;
    case 'aptBell': devEmit('apt:open', { view: 'doorbell', data: { id: 7, name: 'Alex Carter', expires: 60 } }); break;
    case 'cityhall': case 'management': case 'emotes': case 'medical': case 'dispatch': case 'mdt': miscOpen(screen, empty); break;
    case 'phone':
      phoneReset(empty);
      phoneVoice(mode !== 'restricted');
      devEmit('phone:open', phoneSession(empty));
      break;
    case 'garage': case 'impound': devEmit('garage:open', F.garageOpen(screen, empty)); break;
    case 'dealer': devEmit('dealer:open', F.dealerOpen(empty)); break;
    case 'journal': devEmit('drugs:journal', F.journal(empty)); break;
    case 'table': devEmit('drugs:equipment', F.weedTable(empty, mode === 'pending')); break;
    case 'grow':
      devEmit('drugs:card', F.plantCard);
      devEmit('drugs:placement', mode === 'error' ? { visible: true, valid: false, reason: 'Too close to another plant', label: 'Violet Haze', container: 'ground', canToggle: true }
        : { visible: true, valid: true, label: 'Violet Haze', container: 'ground', canToggle: true });
      break;
    case 'creator': case 'clothing': case 'barber':
      apState = F.appearanceOpen(AP_MODE[screen], empty);
      devEmit('appearance:open', clone(apState));
      break;
    case 'target': {
      const s: TargetState = empty ? { ...F.targetState, options: [] } : F.targetState;
      devEmit('target:state', s);
      break;
    }
  }
}

function Preview() {
  const [screen, setScreen] = useState<Screen>('inventory');
  const [mode, setMode] = useState<Mode>('normal');
  const [backdrop, setBackdrop] = useState(true);
  const [overlay, setOverlay] = useState(0);
  const [inv] = useState<{ current: InventoryOpen }>({ current: F.inventoryOpen(false) });
  const [nonce, setNonce] = useState(0);
  const Active = SCREENS.find((s) => s.id === screen)!.app;

  useEffect(() => {
    installHandler(screen, mode, inv);
    const timer = setTimeout(() => open(screen, mode, inv), 60);
    return () => clearTimeout(timer);
  }, [screen, mode, inv, nonce]);

  return (
    <>
      {backdrop && <div className="pv-backdrop" style={{ backgroundImage: `url(/concepts/${backdropOf(screen)}.webp)` }} />}
      <div key={`${screen}-${nonce}`} className="pv-stage"><Active /></div>
      {overlay > 0 && <div className="pv-overlay" style={{ backgroundImage: `url(/concepts/${backdropOf(screen)}.webp)`, opacity: overlay / 100 }} />}
      <div className="pv-bar" style={screen === 'phone' ? { top: 8, bottom: 'auto' } : undefined}>
        <strong>PREVIEW ONLY</strong>
        {SCREENS.map((s) => <button key={s.id} className={s.id === screen ? 'on' : ''} onClick={() => setScreen(s.id)}>{s.label}</button>)}
        <select value={mode} onChange={(e) => setMode(e.target.value as Mode)}>{MODES.map((m) => <option key={m}>{m}</option>)}</select>
        <label><input type="checkbox" checked={backdrop} onChange={(e) => setBackdrop(e.target.checked)} /> concept backdrop</label>
        <label>compare <input type="range" min={0} max={80} value={overlay} onChange={(e) => setOverlay(Number(e.target.value))} /></label>
        <button onClick={() => setNonce((n) => n + 1)}>reopen</button>
        {isMisc(screen) && screen === 'dispatch' && <button onClick={() => { devEmit('dispatch:close'); miscDemo('dispatch', 'alert'); }}>+ alert (closed)</button>}
        {isMisc(screen) && screen === 'medical' && <><button onClick={() => miscDemo('medical', 'down')}>down</button><button onClick={() => miscDemo('medical', 'dead')}>dead</button></>}
        {screen === 'phone' && <>
          <button onClick={() => phoneDemo('message')}>+ message</button>
          <button onClick={() => phoneDemo('group')}>+ group msg</button>
          <button onClick={() => phoneDemo('call')}>+ incoming call</button>
          <button onClick={() => phoneDemo('notification')}>+ notification</button>
          <button onClick={() => phoneDemo('share')}>+ number share</button>
          <button onClick={() => phoneDemo('mail')}>+ mail</button>
          <button onClick={() => phoneDemo('lock')}>lock phone (PIN 1234)</button>
          <button onClick={() => phoneDemo('setup')}>first-run setup</button>
          <button onClick={() => phoneClose()}>close phone</button>
          <button onClick={() => devEmit('phone:open', phoneSession(false))}>open phone</button>
        </>}
      </div>
    </>
  );
}

createRoot(document.getElementById('root')!).render(<Preview />);
export { F };
