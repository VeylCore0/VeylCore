// PREVIEW-ONLY demo data matching the concept images. Never used by the FiveM resources.
import type { BankActivity, BankOverview, HudFrame, InventoryOpen, ItemDef, ShopOpen, TargetState } from '@veyl/ui';

const def = (name: string, label: string, weight: number, usable = false, description?: string): ItemDef =>
  ({ name, label, weight, usable, stack: true, maxStack: 10, image: name === 'jacket' ? `${name}.svg` : `${name}.png`, description });

export const itemDefs: Record<string, ItemDef> = Object.fromEntries([
  { ...def('phone', 'Phone', 200, false, 'Stay connected.'), actions: [{ id: 'sim', label: 'SIM card', icon: 'use', tray: true }] },
  def('sim_card', 'SIM Card', 5, false, 'Right-click your phone and open the SIM card tray to insert it.'),
  def('radio', 'Radio', 400, false, 'Short-range radio.'),
  def('water_bottle', 'Water Bottle', 500, true, 'Restores thirst'),
  def('sandwich', 'Sandwich', 300, true, 'Restores hunger'),
  def('bandage', 'Bandage', 100, true, 'Stops light bleeding'),
  def('identity_card', 'ID Card', 10, false, 'Government-issued ID.'),
  def('flashlight', 'Flashlight', 600),
  def('repair_kit', 'Repair Kit', 2500, true, 'Fixes minor vehicle damage'),
  def('keys', 'Keys', 50),
  def('lockpick', 'Lockpick', 50),
  def('first_aid_kit', 'First Aid Kit', 1200),
  def('duct_tape', 'Duct Tape', 300),
  def('wrench_kit', 'Wrench Kit', 3000),
  def('jacket', 'Jacket', 1000),
  def('missing_art', 'Unknown Item', 100, false, 'Demonstrates the missing-image fallback.'),
].map((d) => [d.name, d]));

export function inventoryOpen(empty: boolean): InventoryOpen {
  const D = (name: string, label: string, weight: number, extra: Record<string, unknown> = {}) => ({ name, label, weight, usable: false, stack: true, maxStack: 10, image: name + '.png', category: 'misc', ...extra });
  const items: Record<string, unknown> = Object.fromEntries([
    D('phone', 'Phone', 200, { stack: false, equip: 'phone', category: 'equipment', description: 'Stay connected.', actions: [{ id: 'sim', label: 'SIM card', icon: 'use', tray: true }] }),
    D('identity_card', 'ID Card', 10, { stack: false, equip: 'id', category: 'equipment', description: 'Government-issued ID.' }),
    D('tablet', 'Tablet', 600, { stack: false, equip: 'tablet', category: 'equipment' }),
    D('door_key', 'Key', 20, { stack: false, equip: 'key', category: 'equipment', description: 'Opens one door.' }),
    D('baseball_cap', 'Baseball Cap', 150, { stack: false, equip: 'hat', category: 'equipment', description: 'A plain cap.' }),
    D('sunglasses', 'Sunglasses', 80, { stack: false, equip: 'glasses', category: 'equipment' }),
    D('face_mask', 'Face Mask', 60, { stack: false, equip: 'mask', category: 'equipment' }),
    D('headset', 'Headset', 200, { stack: false, equip: 'ears', category: 'equipment' }),
    D('armor_vest', 'Body Armour', 3000, { equip: 'armor', category: 'equipment', maxStack: 3, description: 'Full body armour. Wear it in the armour slot.' }),
    D('money', 'Cash', 0, { maxStack: 100000000, description: 'Cold, hard cash.' }),
    D('water_bottle', 'Water Bottle', 500, { usable: true, category: 'consumables', description: 'Restores thirst' }),
    D('sandwich', 'Sandwich', 300, { usable: true, category: 'consumables', description: 'Restores hunger' }),
    D('bandage', 'Bandage', 100, { usable: true, category: 'consumables', description: 'Stops light bleeding' }),
    D('first_aid_kit', 'First Aid Kit', 1200, { category: 'consumables' }),
    D('lockpick', 'Lockpick', 50), D('flashlight', 'Flashlight', 600), D('repair_kit', 'Repair Kit', 2500, { usable: true }),
    D('prod_pack', 'Bagged Weed', 120, { category: 'goods', maxStack: 100 }),
    D('sim_card', 'SIM Card', 5, { description: 'Right-click your phone and open the SIM card tray to insert it.' }),
  ].map((d) => [d.name, d]));
  const at = (list: [string, number, Record<string, unknown>?][], from = 1) => list.map(([name, count, metadata], i) => ({ slot: i + from, name, count, ...(metadata ? { metadata } : {}) }));
  const personal = empty ? [] : [
    ...at([['phone', 1], ['money', 15845091], ['money', 65747], ['baseball_cap', 1], ['bandage', 5], ['water_bottle', 3]]),
    { slot: 8, name: 'money', count: 111 }, { slot: 10, name: 'money', count: 335672 },
    { slot: 11, name: 'bandage', count: 1 }, { slot: 13, name: 'identity_card', count: 1 }, { slot: 14, name: 'lockpick', count: 2 },
    { slot: 15, name: 'sandwich', count: 2 }, { slot: 7, name: 'prod_pack', count: 12, metadata: { quality: 78, grade: 'Premium', varietyLabel: 'Violet Haze', batch: 'B0003C' } },
    { slot: 9, name: 'sim_card', count: 1 },
  ];
  const pack = empty ? [] : [{ slot: 2, name: 'first_aid_kit', count: 1 }, { slot: 6, name: 'flashlight', count: 1 }];
  const equip = empty ? [] : [{ slot: 8, name: 'phone', count: 1 }, { slot: 9, name: 'door_key', count: 1, metadata: { label: 'Apartment 4B' } }, { slot: 3, name: 'sunglasses', count: 1 }];
  const locker = empty ? [] : [{ slot: 15, name: 'bandage', count: 3 }];
  const equipSlots = [
    { slot: 1, id: 'ears', label: 'Headset', icon: 'headset', side: 'left' }, { slot: 2, id: 'mask', label: 'Mask', icon: 'mask', side: 'left' },
    { slot: 3, id: 'glasses', label: 'Glasses', icon: 'glasses', side: 'left' }, { slot: 4, id: 'armor', label: 'Armour', icon: 'shield', side: 'left' },
    { slot: 5, id: 'hat', label: 'Hat', icon: 'hat', side: 'left' }, { slot: 6, id: 'id', label: 'ID card', icon: 'id', side: 'right' },
    { slot: 7, id: 'phone', label: 'Phone', icon: 'phone', side: 'right' }, { slot: 8, id: 'tablet', label: 'Tablet', icon: 'tablet', side: 'right' }, { slot: 9, id: 'key', label: 'Key', icon: 'key', side: 'right' },
  ];
  return {
    primary: { ref: 'primary', id: 'player:DEMO', label: 'Pockets', type: 'player', slots: 30, maxWeight: 55000, weight: empty ? 0 : 1200, revision: 1, items: personal },
    backpack: { ref: 'backpack', id: 'pack:DEMO', label: 'Backpack', type: 'stash', slots: 15, maxWeight: 15000, weight: empty ? 0 : 1800, revision: 1, items: pack },
    equip: { ref: 'equip', id: 'equip:DEMO', label: 'Equipment', type: 'stash', slots: 9, maxWeight: 100000000, weight: 0, revision: 1, items: equip },
    secondary: empty ? { ref: 'secondary', id: 'ground', label: 'Ground', type: 'drop', slots: 20, maxWeight: 200000, weight: 0, revision: 0, items: [] }
      : { ref: 'secondary', id: 'stash:DEMO', label: 'Personal Locker', type: 'stash', slots: 24, maxWeight: 70000, weight: 345, revision: 1, items: locker },
    equipSlots, categories: [{ id: 'all', label: 'All' }, { id: 'weapons', label: 'Weapons' }, { id: 'consumables', label: 'Consumables' }, { id: 'equipment', label: 'Equipment' }, { id: 'goods', label: 'Goods' }, { id: 'misc', label: 'Other' }],
    profile: { cid: 'AZZ21893', name: 'Lucas Enembe', phone: '8452336311', job: 'Paramedic' },
    items, imagePath: '/items', hotbarSlots: 5,
  } as unknown as InventoryOpen;
}

export const shopOpen = (empty: boolean): ShopOpen => ({
  shopId: '247_innocence', title: 'General Store', subtitle: 'Daily essentials.', imagePath: '/items', maxPerLine: 20,
  categories: [{ id: 'food', label: 'Food' }, { id: 'drinks', label: 'Drinks' }, { id: 'tools', label: 'Tools' }],
  methods: ['cash', 'bank'], balances: { cash: 420, bank: 12840 },
  products: empty ? [] : [
    { index: 1, item: 'water_bottle', label: 'Water Bottle', price: 5, category: 'drinks', image: 'water_bottle.png', stock: null },
    { index: 2, item: 'sandwich', label: 'Sandwich', price: 12, category: 'food', image: 'sandwich.png', stock: null },
    { index: 3, item: 'sprunk', label: 'Soda', price: 6, category: 'drinks', image: 'sprunk.png', stock: null },
    { index: 4, item: 'snack_bar', label: 'Snack Bar', price: 4, category: 'food', image: 'snack_bar.png', stock: 12 },
    { index: 5, item: 'bandage', label: 'Bandage', price: 15, category: 'tools', image: 'bandage.png', stock: null },
    { index: 6, item: 'flashlight', label: 'Flashlight', price: 80, category: 'tools', image: 'flashlight.png', stock: null },
    { index: 7, item: 'radio', label: 'Radio', price: 250, category: 'tools', image: 'radio.png', stock: 0 },
    { index: 8, item: 'repair_kit', label: 'Repair Kit', price: 450, category: 'tools', image: 'repair_kit.png', stock: null },
  ],
});
/** Concept basket: 2 water ($10) + 1 sandwich ($12) + 1 bandage ($15) = $37. */
export const shopDemoBasket: Record<number, number> = { 1: 2, 2: 1, 5: 1 };

const activity: BankActivity[] = [
  { id: 'a1', type: 'bank', delta: 1500, balance: 12840, reason: 'Paycheck', at: 'Today, 12:45', icon: 'briefcase' },
  { id: 'a2', type: 'bank', delta: -37, balance: 11340, reason: 'Store purchase', at: 'Today, 11:12', icon: 'cart' },
  { id: 'a3', type: 'bank', delta: -2500, balance: 11377, reason: 'Vehicle payment', at: 'Yesterday, 19:32', icon: 'car' },
];
export const bankOverview = (empty: boolean): BankOverview => ({
  name: 'Alex Veyl', hour: 19, bank: 12840, cash: 420, account: 'VC48210482', accountMasked: 'VC •••• 0482', recent: empty ? [] : activity,
});
export const bankHistory = (offset: number): { rows: BankActivity[]; nextOffset: number | null } => {
  const rows = Array.from({ length: 8 }, (_, i) => {
    const a = activity[(offset + i) % activity.length];
    return { ...a, id: `h${offset + i}`, at: `Nov ${20 - Math.floor((offset + i) / 3)}, 1${(offset + i) % 10}:0${i % 6}` };
  });
  return { rows, nextOffset: offset + 8 >= 24 ? null : offset + 8 };
};

export const hudFrame: HudFrame = {
  visible: true,
  status: { health: 82, armor: 45, hunger: 64, thirst: 58, stress: 12, stamina: 100 },
  vehicle: { speed: 64, unit: 'MPH', gear: '3', rpm: 0.62, fuel: 72, seatbelt: 'on' },
  voice: { talking: false, range: 3, available: true },
  info: { serverId: 27, cash: 420, bank: 12840 },
  compass: { heading: 20, street: 'Alta St' },
  minimap: { left: 0.016, bottom: 0.085, width: 0.168, height: 0.17 },
  settings: { scale: 1, showMoney: true, showCompass: true, showStatus: true, showVehicle: true, showBrand: true, unit: 'MPH' },
};

export const targetState: TargetState = {
  active: true, selected: 1, title: 'Vehicle', state: 'Locked', stateIcon: 'car', keys: { hold: 'ALT', select: 'E' },
  options: [{ index: 1, label: 'Unlock vehicle', icon: 'unlock' }, { index: 2, label: 'Open trunk', icon: 'trunk' }, { index: 3, label: 'Inspect vehicle', icon: 'inspect' }],
};

// ---------------------------------------------------------------------------
// Appearance (mirrors veyl_appearance/config.lua categories; counts are typical freemode values)
// ---------------------------------------------------------------------------
import type { AppearanceOpen, Category, Mode as AppearanceMode, Slot } from '../../appearance-ui/src/types';

const AP_CATS: Category[] = [
  { key: 'heritage', group: 'character', label: 'Heritage', icon: 'dna', camera: 'head', kind: 'heritage' },
  { key: 'features', group: 'face', label: 'Face shape', icon: 'face', camera: 'head', kind: 'features' },
  { key: 'eyes', group: 'face', label: 'Eye colour', icon: 'eye', camera: 'head', kind: 'eyes' },
  { key: 'blemishes', group: 'skin', label: 'Blemishes', icon: 'face', camera: 'head', kind: 'overlay', max: 23 },
  { key: 'ageing', group: 'skin', label: 'Ageing', icon: 'face', camera: 'head', kind: 'overlay', max: 14 },
  { key: 'hair', group: 'hair', label: 'Hairstyle', icon: 'scissors', camera: 'head', kind: 'component', color: 'hair', color2: true, max: 78, textures: 1 },
  { key: 'beard', group: 'hair', label: 'Beard', icon: 'beard', camera: 'head', kind: 'overlay', color: 'hair', max: 28 },
  { key: 'eyebrows', group: 'hair', label: 'Eyebrows', icon: 'eye', camera: 'head', kind: 'overlay', color: 'hair', max: 33 },
  { key: 'makeup', group: 'hair', label: 'Eye makeup', icon: 'sparkle', camera: 'head', kind: 'overlay', max: 74 },
  { key: 'lipstick', group: 'hair', label: 'Lipstick', icon: 'sparkle', camera: 'head', kind: 'overlay', color: 'makeup', max: 9 },
  { key: 'tops', group: 'clothing', label: 'Jackets & tops', icon: 'shirt', camera: 'body', kind: 'component', max: 391, textures: 4 },
  { key: 'undershirt', group: 'clothing', label: 'Undershirts', icon: 'shirt', camera: 'body', kind: 'component', max: 187, textures: 2 },
  { key: 'arms', group: 'clothing', label: 'Arms & gloves', icon: 'hand', camera: 'body', kind: 'component', max: 196, textures: 1 },
  { key: 'legs', group: 'clothing', label: 'Pants', icon: 'pants', camera: 'legs', kind: 'component', max: 143, textures: 3 },
  { key: 'shoes', group: 'clothing', label: 'Shoes', icon: 'shoe', camera: 'feet', kind: 'component', max: 101, textures: 2 },
  { key: 'bag', group: 'clothing', label: 'Bags', icon: 'bag', camera: 'body', kind: 'component', max: 99, textures: 1 },
  { key: 'mask', group: 'clothing', label: 'Masks', icon: 'mask', camera: 'head', kind: 'component', max: 196, textures: 1 },
  { key: 'hat', group: 'accessories', label: 'Hats', icon: 'hat', camera: 'head', kind: 'prop', max: 159, textures: 1 },
  { key: 'glasses', group: 'accessories', label: 'Glasses', icon: 'glasses', camera: 'head', kind: 'prop', max: 45, textures: 1 },
  { key: 'watch', group: 'accessories', label: 'Watches', icon: 'watch', camera: 'body', kind: 'prop', max: 40, textures: 1 },
];
const AP_GROUPS: Record<AppearanceMode, string[]> = {
  create: ['character', 'face', 'skin', 'hair', 'clothing', 'accessories'], admin: ['character', 'face', 'skin', 'hair', 'clothing', 'accessories'],
  clothing: ['clothing', 'accessories'], barber: ['hair'],
};
const AP_PRICES: Record<string, number> = { tops: 60, undershirt: 30, arms: 20, legs: 45, shoes: 40, bag: 35, mask: 30, hat: 25, glasses: 30, watch: 80, hair: 30, beard: 20, eyebrows: 10, makeup: 15, lipstick: 10 };

function apValue(c: Category): Slot {
  switch (c.kind) {
    case 'heritage': return { mother: 21, father: 4, shapeMix: 70, skinMix: 50 };
    case 'features': return { values: new Array(20).fill(0) };
    case 'eyes': return { d: 3 };
    case 'component': return c.key === 'hair' ? { d: 12, t: 0, color: 3, color2: 3 } : { d: c.key === 'tops' ? 15 : 4, t: 0 };
    case 'prop': return { d: -1, t: 0 };
    default: return { d: -1, opacity: 100, color: 0 };
  }
}

const shade = (i: number, hue: number) => `hsl(${(hue + i * 9) % 360} ${30 + (i % 5) * 10}% ${18 + (i % 8) * 8}%)`;

export function appearanceOpen(mode: AppearanceMode, empty: boolean): AppearanceOpen {
  const cats = AP_CATS.filter((c) => AP_GROUPS[mode].includes(c.group));
  const values = Object.fromEntries(cats.map((c) => [c.key, apValue(c)]));
  const store = mode === 'clothing' || mode === 'barber';
  return {
    mode, allowCancel: mode !== 'create', sex: 'm',
    title: mode === 'create' ? 'Create your character' : mode === 'clothing' ? 'Clothing Store' : mode === 'barber' ? 'Barber Shop' : 'Appearance',
    subtitle: mode === 'create' ? 'Pick a starting look. You can change clothes and hair later in stores.' : mode === 'clothing' ? 'Clothes and accessories' : 'Hair, beards and makeup',
    categories: cats, values, original: JSON.parse(JSON.stringify(values)),
    palettes: { hair: Array.from({ length: 64 }, (_, i) => shade(i, 20)), makeup: Array.from({ length: 64 }, (_, i) => shade(i, 330)) },
    store: store ? {
      prices: Object.fromEntries(cats.map((c) => [c.key, AP_PRICES[c.key] ?? 0])), balances: { cash: 420, bank: 12840 }, methods: ['cash', 'bank'],
      outfits: mode === 'clothing' ? (empty ? [] : [
        { id: 2, name: 'Work clothes', slots: { tops: { d: 22, t: 1 }, legs: { d: 10, t: 0 }, shoes: { d: 12, t: 0 } } },
        { id: 1, name: 'Night out', slots: { tops: { d: 31, t: 0 }, legs: { d: 24, t: 0 } } },
      ]) : null,
    } : null,
  };
}

// ---------------------------------------------------------------------------
// Vehicles: garage, impound, dealership
// ---------------------------------------------------------------------------
import type { DealerOpen, GarageOpen, GarageVehicle } from '../../vehicle-ui/src/types';

const OWNED: GarageVehicle[] = [
  { id: 1, model: 'sultan', plate: 'VKX 4821', name: 'Sultan', brand: 'Karin', state: 'garaged', garage: 'legion', garageLabel: 'Legion Square Parking', fuel: 76, engine: 98, body: 91, impoundFee: 0, here: true, out: false },
  { id: 2, model: 'faggio', plate: 'MTP 0193', name: 'Faggio', brand: 'Pegassi', state: 'garaged', garage: 'legion', garageLabel: 'Legion Square Parking', fuel: 18, engine: 64, body: 40, impoundFee: 0, here: true, out: false },
  { id: 3, model: 'granger', plate: 'RDN 7710', name: 'Granger', brand: 'Declasse', state: 'garaged', garage: 'sandy', garageLabel: 'Sandy Shores Parking', fuel: 52, engine: 100, body: 100, impoundFee: 0, here: false, out: false },
  { id: 4, model: 'blista', plate: 'CWE 3355', name: 'Blista', brand: 'Dinka', state: 'impound', fuel: 34, engine: 12, body: 8, impoundFee: 500, impoundReason: 'destroyed', here: false, out: false },
  { id: 5, model: 'asea', plate: 'HPL 2047', name: 'Asea', brand: 'Declasse', state: 'out', garage: 'legion', fuel: 61, engine: 88, body: 77, impoundFee: 0, here: false, out: true },
];

export function garageOpen(kind: 'garage' | 'impound', empty: boolean): GarageOpen {
  const vehicles = empty ? [] : OWNED.map((v) => ({ ...v, here: kind === 'impound' ? v.state === 'impound' : v.here }));
  return { kind, placeId: kind === 'impound' ? 'impound' : 'legion', title: kind === 'impound' ? 'Impound Lot' : 'Legion Square Parking',
    vehicles, balances: { cash: 420, bank: 12840 }, methods: ['cash', 'bank'], imagePath: '/vehicles' };
}

export function dealerOpen(empty: boolean): DealerOpen {
  const v = (model: string, name: string, brand: string, price: number, category: string) => ({ model, name, brand, price, category });
  return {
    title: 'Premium Deluxe Motorsport', subtitle: 'New vehicles, registered to you on purchase.',
    categories: [{ id: 'compacts', label: 'Compacts' }, { id: 'sedans', label: 'Sedans' }, { id: 'suvs', label: 'SUVs' }, { id: 'sports', label: 'Sports' }, { id: 'motorcycles', label: 'Motorcycles' }],
    vehicles: empty ? [] : [
      v('panto', 'Panto', 'Benefactor', 7500, 'compacts'), v('blista', 'Blista', 'Dinka', 13000, 'compacts'), v('asea', 'Asea', 'Declasse', 9000, 'sedans'),
      v('tailgater', 'Tailgater', 'Obey', 26000, 'sedans'), v('granger', 'Granger', 'Declasse', 32000, 'suvs'), v('baller', 'Baller', 'Gallivanter', 42000, 'suvs'),
      v('sultan', 'Sultan', 'Karin', 45000, 'sports'), v('banshee', 'Banshee', 'Bravado', 105000, 'sports'), v('faggio', 'Faggio', 'Pegassi', 2500, 'motorcycles'),
      v('bati', 'Bati 801', 'Pegassi', 24000, 'motorcycles'),
    ],
    balances: { cash: 420, bank: 152840 }, methods: ['cash', 'bank'], imagePath: '/vehicles',
  };
}

