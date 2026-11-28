// Preview-only backend for the black market menu. Same callback names and shapes as veyl_blackmarket's server.lua; never shipped to FiveM.
import { devEmit, type NuiResponse } from '@veyl/ui';

const ok = <T,>(data?: T, message?: string): NuiResponse<T> => ({ ok: true, data, message });
const err = (code: string, message: string): NuiResponse<never> => ({ ok: false, code, message });

type E = { item: string; label: string; description?: string; price: number; category: string; stock: number; max: number; level: number };
const CATS = [
  { id: 'pistols', label: 'Pistols', icon: 'gun' }, { id: 'smgs', label: 'SMGs', icon: 'gun' }, { id: 'long', label: 'Shotguns & Rifles', icon: 'gun' },
  { id: 'melee', label: 'Melee', icon: 'blade' }, { id: 'ammo', label: 'Ammo & Mods', icon: 'box' }, { id: 'drugs', label: 'Drugs', icon: 'pill' },
  { id: 'lab', label: 'Lab Supplies', icon: 'flask' }, { id: 'tools', label: 'Break-in Tools', icon: 'key' }, { id: 'hacking', label: 'Hacking & Fraud', icon: 'chip' },
];
const BASE: E[] = [
  { item: 'weapon_appistol', label: 'AP Pistol', price: 9500, category: 'pistols', stock: 6, max: 6, level: 0 },
  { item: 'weapon_heavypistol', label: 'Heavy Pistol', price: 7200, category: 'pistols', stock: 8, max: 8, level: 0 },
  { item: 'weapon_machinepistol', label: 'Machine Pistol', price: 12500, category: 'pistols', stock: 4, max: 4, level: 2 },
  { item: 'weapon_microsmg', label: 'Micro SMG', price: 14500, category: 'smgs', stock: 4, max: 4, level: 1 },
  { item: 'weapon_smg', label: 'SMG', price: 19500, category: 'smgs', stock: 3, max: 3, level: 2 },
  { item: 'weapon_carbinerifle', label: 'Carbine Rifle', price: 41000, category: 'long', stock: 2, max: 2, level: 4 },
  { item: 'weapon_heavysniper', label: 'Heavy Sniper', price: 95000, category: 'long', stock: 0, max: 1, level: 7 },
  { item: 'weapon_knuckle', label: 'Brass Knuckles', price: 600, category: 'melee', stock: 10, max: 10, level: 0 },
  { item: 'ammo_pistol', label: 'Pistol Ammo', description: 'For pistols and SMGs that take pistol rounds.', price: 9, category: 'ammo', stock: 400, max: 400, level: 0 },
  { item: 'att_suppressor', label: 'Suppressor', price: 4500, category: 'ammo', stock: 5, max: 5, level: 2 },
  { item: 'weed_baggie', label: 'Weed Baggie', price: 140, category: 'drugs', stock: 40, max: 40, level: 0 },
  { item: 'coke_baggie', label: 'Coke Baggie', price: 420, category: 'drugs', stock: 25, max: 25, level: 1 },
  { item: 'veylx_vial', label: 'Veyl-X', description: 'Nobody knows what is in it.', price: 1500, category: 'drugs', stock: 8, max: 8, level: 4 },
  { item: 'chem_precursor', label: 'Chemical Precursor', price: 260, category: 'lab', stock: 30, max: 30, level: 1 },
  { item: 'lockpick', label: 'Lockpick', description: 'Picks simple locks. Might break.', price: 220, category: 'tools', stock: 20, max: 20, level: 0 },
  { item: 'thermite', label: 'Thermite', description: 'Burns through a lock.', price: 4200, category: 'tools', stock: 5, max: 5, level: 3 },
  { item: 'hacking_device', label: 'Hacking Device', price: 6500, category: 'hacking', stock: 3, max: 3, level: 3 },
  { item: 'usb_darkweb', label: 'Black USB Drive', description: 'Unlocks a hidden app on your phone.', price: 3000, category: 'hacking', stock: 4, max: 4, level: 2 },
];

let items: E[] = [];
let cash = 0;
const LEVEL = 2;

const view = () => ({ id: 'docks', label: 'Dock Fixer', categories: CATS, cash, level: LEVEL, maxPerLine: 50,
  items: items.map((e) => ({ ...e, locked: e.level > LEVEL })) });

export const bmApi = (name: string, args: unknown[]): NuiResponse | undefined => {
  if (name === 'view') return ok(view());
  if (name === 'buy') {
    const [item, qty] = args as [string, number];
    const e = items.find((x) => x.item === item);
    if (!e) return err('INVALID_INPUT', 'Bad request');
    if (e.level > LEVEL) return err('LEVEL_REQUIRED', `He wants a reputation of ${e.level} first`);
    if (e.stock < qty) return err('OUT_OF_STOCK', e.stock > 0 ? `Only ${e.stock} left` : 'Sold out');
    if (e.price * qty > cash) return err('INSUFFICIENT_FUNDS', 'You cannot afford that');
    cash -= e.price * qty; e.stock -= qty;
    return ok({ stock: e.stock, cash }, `Bought ${qty}x ${e.label} for $${e.price * qty}`);
  }
  return undefined;
};

export const bmDemo = {
  open(startCash = 60000) { items = BASE.map((e) => ({ ...e })); cash = startCash; devEmit('blackmarket:open', { data: view() }); },
};
