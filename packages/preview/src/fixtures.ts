// PREVIEW-ONLY demo data matching the concept images. Never used by the FiveM resources.
import type { BankActivity, BankOverview, HudFrame, InventoryOpen, ItemDef, ShopOpen, TargetState } from '@veyl/ui';

const def = (name: string, label: string, weight: number, usable = false, description?: string): ItemDef =>
  ({ name, label, weight, usable, stack: true, maxStack: 10, image: name === 'jacket' ? `${name}.svg` : `${name}.png`, description });

export const itemDefs: Record<string, ItemDef> = Object.fromEntries([
  def('phone', 'Phone', 200, false, 'Stay connected.'),
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
  const personal = empty ? [] : [
    ['phone', 1], ['radio', 1], ['water_bottle', 3], ['sandwich', 2], ['bandage', 5],
    ['identity_card', 1], ['flashlight', 1], ['repair_kit', 1], ['keys', 1], ['lockpick', 2],
  ].map(([name, count], i) => ({ slot: i + 1, name: name as string, count: count as number }));
  const trunk = empty ? [] : [['first_aid_kit', 1], ['duct_tape', 2], ['wrench_kit', 1], ['jacket', 1], ['missing_art', 1]]
    .map(([name, count], i) => ({ slot: i + 1, name: name as string, count: count as number }));
  return {
    primary: { ref: 'primary', id: 'player:DEMO', label: 'Pockets', type: 'player', slots: 25, maxWeight: 30000, weight: empty ? 0 : 12400, revision: 1, items: personal },
    secondary: { ref: 'secondary', id: 'trunk:DEMO', label: 'Vehicle Trunk', type: 'trunk', slots: 25, maxWeight: 60000, weight: empty ? 0 : 7800, revision: 1, items: trunk },
    items: itemDefs, imagePath: '/items', hotbarSlots: 5,
  };
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
