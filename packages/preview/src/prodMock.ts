// Preview-only backend for the production tablet, shop and bench pages. Same callback names and shapes as veyl_production's server
// (server/callbacks.lua); never shipped to FiveM.
import { devEmit, type NuiResponse } from '@veyl/ui';

const now = () => Math.floor(Date.now() / 1000);
const ok = <T,>(data?: T, message?: string): NuiResponse<T> => ({ ok: true, data, message });
const err = (code: string, message: string): NuiResponse<never> => ({ ok: false, code, message });
const L: Record<string, string> = { prod_seed_ember: 'Violet Haze Seeds', prod_seed_violet: 'Silverleaf Seeds', prod_seed_azure: 'Nightbloom Seeds', prod_planter: 'Planter', prod_water: 'Clean Water', prod_nutrient: 'Growth Tonic', prod_leaf: 'Weed Bud', prod_blend: 'Trimmed Bud', prod_pack: 'Bagged Weed', prod_wild_herb: 'Wild Herbs', prod_workstation: 'Weed Table', prod_fseed_dawn: 'Red Ridge Seeds', prod_fseed_dusk: 'Andes Mist Seeds', prod_supply_kit: 'Chemical Supplies' };

let xp = 410, cash = 24000;
let plants = [
  { id: 1, variety: 'ember', label: 'Violet Haze', state: 'growing', x: 2024, y: 4880, property: null, growth: 0.62, water: 58, nutrient: 44, health: 100, stage: 3, minutesLeft: 17, careRatio: 0.9 },
  { id: 2, variety: 'violet', label: 'Silverleaf', state: 'ready', x: 2030, y: 4882, property: null, growth: 1, water: 31, nutrient: 22, health: 92, stage: 4, minutesLeft: 0, careRatio: 0.8 },
  { id: 3, variety: 'ember', label: 'Violet Haze', state: 'growing', x: 1, y: 1, property: 'puerta_lab', growth: 0.2, water: 80, nutrient: 76, health: 100, stage: 1, minutesLeft: 36, careRatio: 1 },
];
const base = now();
let batches = [
  { id: 1, recipe: 'blend', label: 'Trim Bud', state: 'running', startsAt: base - 20, endsAt: base + 30, quality: 71, tier: 'Good', output: { item: 'prod_blend', count: 2 }, stage: 'Blending', progress: 0.4 },
  { id: 2, recipe: 'blend', label: 'Trim Bud', state: 'queued', startsAt: base + 30, endsAt: base + 80, quality: 64, tier: 'Good', output: { item: 'prod_blend', count: 2 }, stage: null, progress: 0 },
];
const recipes = [
  { id: 'blend', label: 'Trim Bud', level: 1, locked: false, inputs: [{ item: 'prod_leaf', count: 4 }], output: { item: 'prod_blend', count: 2 }, seconds: 50, stages: [{ label: 'Sorting', seconds: 20 }, { label: 'Blending', seconds: 30 }] },
  { id: 'pack', label: 'Bag Weed', level: 4, locked: true, inputs: [{ item: 'prod_blend', count: 2 }], output: { item: 'prod_pack', count: 3 }, seconds: 35, stages: [{ label: 'Weighing', seconds: 15 }, { label: 'Sealing', seconds: 20 }] },
  { id: 'synthesize', label: 'Cook Crystal', level: 2, branch: 'supplier', skill: 3, hazard: true, locked: false, inputs: [{ item: 'prod_supply_kit', count: 2 }], output: { item: 'prod_blend', count: 2 }, seconds: 90, stages: [{ label: 'Mixing', seconds: 90 }] },
  { id: 'tonic', label: 'Mix Growth Tonic', level: 1, locked: false, inputs: [{ item: 'prod_wild_herb', count: 3 }], output: { item: 'prod_nutrient', count: 2 }, seconds: 25, stages: [{ label: 'Steeping', seconds: 25 }] },
];
const bench = () => ({ id: 1, type: 'prep_table', label: 'Portable Weed Table', property: null, mine: true, x: 2030, y: 4890, slots: 3, batches, recipes, serverTime: now() });
let owned = true;
let locked = true;
const upgrades = {
  storage: { label: 'Storage capacity', icon: 'box', levels: [{ price: 15000, slots: 15, maxWeight: 60000 }, { price: 30000, slots: 30, maxWeight: 150000 }, { price: 55000, slots: 50, maxWeight: 300000 }] },
  benches: { label: 'Workstation slots', icon: 'bench', levels: [{ price: 20000, slots: 1 }, { price: 40000, slots: 2 }, { price: 70000, slots: 3 }] },
  equipment: { label: 'Equipment', icon: 'gear', levels: [{ price: 25000, quality: 3, speed: 0.95 }, { price: 50000, quality: 6, speed: 0.9 }, { price: 90000, quality: 10, speed: 0.8 }] },
  security: { label: 'Security', icon: 'shield', levels: [{ price: 12000, breachSeconds: 20 }, { price: 28000, breachSeconds: 45 }, { price: 60000, breachSeconds: 90 }] },
};
let ups: Record<string, number> = { storage: 1 };
let members = [{ id: 'PB', role: 'employee', name: 'Jamie Cole' }];

const LEVELS = [0, 120, 360, 800, 1600, 3200];
const NAMES = ['Newcomer', 'Hand', 'Practitioner', 'Specialist', 'Expert', 'Master'];
const lvOf = () => { let l = 1; LEVELS.forEach((n, i) => { if (xp >= n) l = i + 1; }); return l; };

function props() {
  const lv = lvOf();
  return {
    properties: [
      owned ? { id: 'puerta_lab', label: 'La Puerta Lab', description: 'A quiet unit near the old docks. The cheapest way in.', price: 60000, level: 1, branch: 'botanical', role: 'owner', owned: true, locked,
        upgrades: ups, storage: { slots: 55, weight: 180000 }, benches: { used: 1, max: 2 }, hasCode: true, inside: false, pricePaid: 60000, members, sellFor: 36000 }
        : { id: 'puerta_lab', label: 'La Puerta Lab', description: 'A quiet unit near the old docks. The cheapest way in.', price: 60000, level: 1, branch: 'botanical', role: null, owned: false, locked: true, forSale: true, levelOk: true },
      { id: 'elysian_lab', label: 'Elysian Lab', description: 'Warehouse space by the container yards.', price: 85000, level: 2, branch: 'botanical', role: null, owned: false, locked: true, forSale: true, levelOk: lv >= 2 },
      { id: 'harmony_lab', label: 'Harmony Lab', description: 'A big shed in the desert. Far from prying eyes.', price: 110000, level: 3, branch: 'botanical', role: null, owned: false, locked: true, forSale: true, levelOk: lv >= 3 },
    ],
    owned: owned ? 1 : 0, maxOwned: 2, upgrades,
  };
}

let supRun: any = null;
function supplierState() {
  return {
    suppliers: [
      { id: 'harbour_contact', label: 'Harbour contact', level: 1, locked: false, fee: 250, open: true, hours: [0, 24], runsLeft: 3, minutes: 20, kits: [2, 4], x: 1210, y: -3110 },
      { id: 'night_contact', label: 'Night contact', level: 4, locked: lvOf() < 4, fee: 600, open: false, hours: [20, 28], runsLeft: 2, minutes: 25, kits: [4, 7], x: -430, y: -2170 },
    ],
    run: supRun, cancelWait: 0,
  };
}

export function prodState() {
  const lv = lvOf();
  const floor = LEVELS[lv - 1], next = LEVELS[lv];
  return {
    player: { name: 'Alex Morgan' },
    progress: { branches: { botanical: { label: 'Botanical', icon: 'leaf', color: '#7bd88f', xp, level: lv, levelName: NAMES[lv - 1], nextXp: next, floor, progress: next ? (xp - floor) / (next - floor) : 1 },
      field: { label: 'Field Operations', icon: 'compass', color: '#5ab0ff', xp: 220, level: 2, levelName: NAMES[1], nextXp: 360, floor: 120, progress: 0.42 },
      supplier: { label: 'Supplier Operations', icon: 'truck', color: '#f2b443', xp: 90, level: 1, levelName: NAMES[0], nextXp: 120, floor: 0, progress: 0.75 } },
      stats: { plants_planted: 14, plants_harvested: 9, leaves_harvested: 38, gathered: 21, batches_completed: 7, purchases: 12, sales: 5, money_spent: 3180, money_earned: 4260 },
      reputation: { level: lv, name: NAMES[lv - 1], xp, next, floor } },
    plants,
    varieties: [
      { key: 'ember', label: 'Violet Haze', branch: 'botanical', rarity: 'Common', level: 1, locked: false, growMinutes: 45, yield: [3, 5], seed: 'prod_seed_ember' },
      { key: 'violet', label: 'Silverleaf', branch: 'botanical', rarity: 'Uncommon', level: 2, locked: lv < 2, growMinutes: 70, yield: [3, 6], seed: 'prod_seed_violet' },
      { key: 'dawn', label: 'Red Ridge', branch: 'field', rarity: 'Common', level: 1, locked: false, growMinutes: 40, yield: [2, 4], seed: 'prod_fseed_dawn' },
      { key: 'dusk', label: 'Andes Mist', branch: 'field', rarity: 'Uncommon', level: 3, locked: lv < 3, growMinutes: 80, yield: [3, 6], seed: 'prod_fseed_dusk' },
      { key: 'azure', label: 'Nightbloom', branch: 'botanical', rarity: 'Rare', level: 4, locked: lv < 4, growMinutes: 100, yield: [4, 7], seed: 'prod_seed_azure' },
    ],
    workstations: [bench()], properties: props(),
    gathering: [
      { id: 'grapeseed_a', label: 'Wild patch', branch: 'botanical', points: 1, ready: 1, level: 1, locked: false, cooldown: 0, x: 2024, y: 4880 }, { id: 'grapeseed_b', label: 'Wild patch', branch: 'botanical', points: 1, ready: 0, level: 1, locked: false, cooldown: 180, x: 1959, y: 4640 },
      { id: 'alamo_shore', label: 'Alamo shore', branch: 'field', points: 6, ready: 4, level: 1, locked: false, cooldown: 0, x: 1380, y: 3600 },
      { id: 'canyon_floor', label: 'Canyon floor', branch: 'field', points: 5, ready: 5, level: 3, locked: lv < 3, cooldown: 0, x: -1200, y: 4300 },
      { id: 'paleto_a', label: 'Overgrown ditch', branch: 'botanical', points: 1, ready: 1, level: 2, locked: lv < 2, cooldown: 0, x: -216, y: 6330 },
    ],
    supplier: supplierState(), exposure: 0,
    shops: [{ id: 'garden_supplier', label: 'Garden Supplier', branch: 'botanical', x: 0, y: 0 }, { id: 'field_outfitter', label: 'Field Outfitter', branch: 'field', x: 0, y: 0 }, { id: 'supply_dealer', label: 'Supply Dealer', branch: 'supplier', x: 0, y: 0 }],
    recent: [
      { kind: 'harvest', text: 'harvested ember x4 (quality 72)', at: now() - 300 }, { kind: 'craft', text: 'started blend on bench #1', at: now() - 900 }, { kind: 'purchase', text: 'bought 3x prod_seed_ember for $120', at: now() - 3600 },
    ],
    police: { enabled: false, dispatch: false, isPolice: false },
    branches: { botanical: { label: 'Botanical', icon: 'leaf', color: '#7bd88f', enabled: true }, field: { label: 'Field Operations', icon: 'compass', color: '#5ab0ff', enabled: true }, supplier: { label: 'Supplier Operations', icon: 'truck', color: '#f2b443', enabled: true } },
    ui: { Brand: 'VEYL PRODUCTION', Accent: '#8b5fd6', Accent2: '#3f8bff', Currency: '$' },
    tiers: [{ max: 24, label: 'Poor', mult: 0.6 }, { max: 49, label: 'Standard', mult: 1 }, { max: 74, label: 'Good', mult: 1.3 }, { max: 89, label: 'Excellent', mult: 1.6 }, { max: 100, label: 'Flawless', mult: 2 }],
    levelNames: NAMES, itemLabels: L, serverTime: now(),
  };
}

export function prodShop() {
  return {
    id: 'garden_supplier', label: 'Garden Supplier',
    items: [
      { item: 'prod_planter', label: 'Planter', price: 60, stock: 26, max: 30, level: 1, locked: false }, { item: 'prod_water', label: 'Clean Water', price: 12, stock: 54, max: 60, level: 1, locked: false },
      { item: 'prod_nutrient', label: 'Growth Tonic', price: 25, stock: 6, max: 40, level: 1, locked: false }, { item: 'prod_seed_ember', label: 'Violet Haze Seeds', price: 40, stock: 33, max: 40, level: 1, locked: false },
      { item: 'prod_seed_violet', label: 'Silverleaf Seeds', price: 110, stock: 20, max: 20, level: 2, locked: lvOf() < 2 }, { item: 'prod_seed_azure', label: 'Nightbloom Seeds', price: 260, stock: 0, max: 10, level: 4, locked: lvOf() < 4 },
      { item: 'prod_workstation', label: 'Weed Table', price: 2500, stock: 4, max: 5, level: 2, locked: lvOf() < 2 },
    ],
    sell: [{ item: 'prod_pack', label: 'Bagged Weed', base: 180 }, { item: 'prod_blend', label: 'Trimmed Bud', base: 70 }, { item: 'prod_leaf', label: 'Weed Bud', base: 28 }, { item: 'prod_wild_herb', label: 'Wild Herbs', base: 12 }],
    quality: [{ max: 24, label: 'Poor', mult: 0.6 }, { max: 49, label: 'Standard', mult: 1 }, { max: 74, label: 'Good', mult: 1.3 }, { max: 89, label: 'Excellent', mult: 1.6 }, { max: 100, label: 'Flawless', mult: 2 }],
    restockMinutes: 30,
  };
}

export function prodApi(name: string, a: unknown[]): NuiResponse | undefined {
  switch (name) {
    case 'state': return ok(prodState());
    case 'shopView': case 'buyerView': return ok(prodShop());
    case 'shopBuy': { const item = prodShop().items.find((i) => i.item === a[1]); if (!item) return err('INVALID_INPUT', 'Bad request'); const cost = item.price * Number(a[2]); if (cost > cash) return err('INSUFFICIENT_FUNDS', 'You cannot afford that'); cash -= cost; return ok(undefined, `Bought ${a[2]}x ${item.label} for $${cost}`); }
    case 'runStart': supRun = { id: 1, supplier: String(a[0]), state: 'active', kits: 4, expiresAt: now() + 1200, serverTime: now(), pickup: { label: 'Container yard', x: 1205, y: -3118, z: 5 } }; return ok({ run: supRun }, 'Run started: head to the Container yard');
    case 'runCancel': supRun = null; return ok(undefined, 'Run dropped');
    case 'shopSell': return ok({ total: 360, sold: Number(a[1]) }, `Sold ${a[1]} for $360`);
    case 'wsOpen': return ok(bench());
    case 'wsStart': { if (batches.length >= 3) return err('LIMIT', 'The queue is full'); const r = recipes.find((x) => x.id === a[1]); if (!r || r.locked) return err('LEVEL_REQUIRED', 'Needs a higher level'); const last = batches[batches.length - 1]?.endsAt ?? now(); batches = [...batches, { id: Date.now() % 100000, recipe: r.id, label: r.label, state: 'queued', startsAt: last, endsAt: last + r.seconds, quality: 66, tier: 'Good', output: r.output, stage: null, progress: 0 }]; return ok(bench(), `${r.label} queued`); }
    case 'wsClaim': { const ready = batches.filter((b) => b.endsAt <= now()); if (!ready.length) return err('NOTHING_READY', 'Nothing is ready yet'); batches = batches.filter((b) => b.endsAt > now()); return ok(bench(), 'Collected'); }
    case 'wsCancel': batches = batches.filter((b) => b.id !== a[1]); return ok(bench(), 'Cancelled: everything returned');
    case 'wsPack': return batches.length ? err('INVALID_STATE', 'Finish or cancel its batches first') : ok(undefined, 'Packed up');
    case 'propBuy': owned = a[0] === 'puerta_lab' ? true : owned; cash -= 60000; return ok({ id: a[0] }, 'You bought La Puerta Lab');
    case 'propSell': owned = false; return ok(undefined, 'Sold for $36000. You can buy it back for 24 hours.');
    case 'propLock': locked = a[1] === true; return ok({ locked }, locked ? 'Locked' : 'Unlocked: anyone can walk in');
    case 'propCode': return ok(undefined, a[1] ? 'Access code set' : 'Access code removed');
    case 'propUpgrade': { const k = String(a[1]); const lv = (ups[k] ?? 0) + 1; if (!(upgrades as Record<string, { levels: unknown[] }>)[k]?.levels[lv - 1]) return err('INVALID_STATE', 'Already at the top level'); ups = { ...ups, [k]: lv }; return ok({ level: lv }, `Upgraded to level ${lv}`); }
    case 'propMemberAdd': members = [...members, { id: `P${a[1]}`, role: String(a[2]), name: 'Riley Park' }]; return ok(undefined, `Added as ${a[2]}`);
    case 'propMemberRemove': members = members.filter((m) => m.id !== a[1]); return ok(undefined, 'Access removed');
    case 'propStorage': return ok({ stash: 'prod_lab_puerta_lab_2' });
    case 'propTransfer': return ok(undefined, 'Offer sent');
    case 'nearbyPlayers': return ok([{ id: 14, name: 'Riley Park' }, { id: 22, name: 'Casey Nguyen' }]);
  }
  return undefined;
}

export const prodDemo = {
  reset() { supRun = null; xp = 410; cash = 24000; owned = true; locked = true; ups = { storage: 1 }; members = [{ id: 'PB', role: 'employee', name: 'Jamie Cole' }]; },
  tablet(page?: string) { devEmit('production:open', { view: 'tablet', data: { state: prodState(), page } }); },
  shop() { devEmit('production:open', { view: 'shop', data: prodShop() }); },
  buyer() { devEmit('production:open', { view: 'buyer', data: prodShop() }); },
  bench() { devEmit('production:open', { view: 'bench', data: bench() }); },
  placement(valid: boolean) { devEmit('production:placement', { visible: true, valid, reason: valid ? undefined : 'Too close to something else', label: 'Violet Haze' }); },
  run() { supRun = { id: 1, supplier: 'harbour_contact', state: 'picked', kits: 4, expiresAt: now() + 900, serverTime: now(), pickup: { label: 'Container yard', x: 1205, y: -3118, z: 5 }, drop: { label: 'Auto yard', x: 1017, y: -2528, z: 28 } }; },
  hazard(level: number) { devEmit('production:hazard', { level, warn: 40 }); },
  empty() { xp = 0; plants = []; batches = []; owned = false; },
};
