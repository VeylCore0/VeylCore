// Message schema for veyl_appearance (Lua -> NUI 'appearance:open'; NUI requests resolve with the same payload when it changes).

export type Mode = 'create' | 'admin' | 'clothing' | 'barber';
export type Kind = 'component' | 'prop' | 'overlay' | 'heritage' | 'features' | 'eyes';
export type Focus = 'head' | 'body' | 'legs' | 'feet' | 'full';
export type Group = 'character' | 'face' | 'skin' | 'hair' | 'clothing' | 'accessories';

export interface Category {
  key: string; group: Group; label: string; icon: string; camera: Focus; kind: Kind;
  color?: 'hair' | 'makeup'; color2?: boolean;
  max?: number;      // highest style index (component/prop/overlay)
  textures?: number; // variants for the current style
}

/** One category's value. Component/prop: d, t. Overlay: d (-1 none), opacity, color. Heritage/features/eyes use their own fields. */
export interface Slot {
  d?: number; t?: number; opacity?: number; color?: number; color2?: number;
  mother?: number; father?: number; shapeMix?: number; skinMix?: number;
  values?: number[];
}

export interface Outfit { id: number; name: string; slots: Record<string, Slot> }

export interface StoreInfo {
  prices: Record<string, number>;
  balances: { cash: number; bank: number };
  methods: ('cash' | 'bank')[];
  outfits?: Outfit[] | null;
}

export interface AppearanceOpen {
  mode: Mode; allowCancel: boolean; title: string; subtitle: string; sex: 'm' | 'f';
  categories: Category[];
  values: Record<string, Slot>;
  original: Record<string, Slot>;
  palettes: { hair: string[]; makeup: string[] };
  store?: StoreInfo | null;
}

const FIELDS: (keyof Slot)[] = ['d', 't', 'opacity', 'color', 'color2', 'mother', 'father', 'shapeMix', 'skinMix'];

/** Same comparison the server uses to decide what changed. */
export function sameSlot(a?: Slot, b?: Slot): boolean {
  if (!a || !b) return a === b;
  for (const f of FIELDS) if ((a[f] ?? null) !== (b[f] ?? null)) return false;
  if (a.values || b.values) {
    for (let i = 0; i < 20; i++) if ((a.values?.[i] ?? 0) !== (b.values?.[i] ?? 0)) return false;
  }
  return true;
}

export const GROUP_LABELS: Record<Group, string> = {
  character: 'Character', face: 'Face', skin: 'Skin', hair: 'Hair & makeup', clothing: 'Clothing', accessories: 'Accessories',
};

export const MODE_SECTION: Record<Mode, string> = { create: 'Character', admin: 'Appearance', clothing: 'Clothing Store', barber: 'Barber' };

// GTA heritage faces 0-45 (21-41 and 45 are the female faces).
export const PARENTS = [
  'Benjamin', 'Daniel', 'Joshua', 'Noah', 'Andrew', 'Juan', 'Alex', 'Isaac', 'Evan', 'Ethan', 'Vincent', 'Angel', 'Diego', 'Adrian',
  'Gabriel', 'Michael', 'Santiago', 'Kevin', 'Louis', 'Samuel', 'Anthony', 'Hannah', 'Audrey', 'Jasmine', 'Giselle', 'Amelia',
  'Isabella', 'Zoe', 'Ava', 'Camila', 'Violet', 'Sophia', 'Evelyn', 'Nicole', 'Ashley', 'Grace', 'Brianna', 'Natalie', 'Olivia',
  'Elizabeth', 'Charlotte', 'Emma', 'Claude', 'Niko', 'John', 'Misty',
];

export const FEATURE_GROUPS: { label: string; items: { index: number; label: string; low: string; high: string }[] }[] = [
  { label: 'Nose', items: [
    { index: 0, label: 'Width', low: 'Narrow', high: 'Wide' }, { index: 1, label: 'Peak height', low: 'Low', high: 'High' },
    { index: 2, label: 'Peak length', low: 'Short', high: 'Long' }, { index: 3, label: 'Bone height', low: 'Low', high: 'High' },
    { index: 4, label: 'Tip', low: 'Up', high: 'Down' }, { index: 5, label: 'Bridge twist', low: 'Left', high: 'Right' },
  ] },
  { label: 'Brows', items: [
    { index: 6, label: 'Height', low: 'Low', high: 'High' }, { index: 7, label: 'Depth', low: 'In', high: 'Out' },
  ] },
  { label: 'Cheeks', items: [
    { index: 8, label: 'Bone height', low: 'Low', high: 'High' }, { index: 9, label: 'Bone width', low: 'Narrow', high: 'Wide' },
    { index: 10, label: 'Fullness', low: 'Gaunt', high: 'Full' },
  ] },
  { label: 'Eyes & lips', items: [
    { index: 11, label: 'Eye opening', low: 'Open', high: 'Squint' }, { index: 12, label: 'Lip thickness', low: 'Thin', high: 'Full' },
  ] },
  { label: 'Jaw & chin', items: [
    { index: 13, label: 'Jaw width', low: 'Narrow', high: 'Wide' }, { index: 14, label: 'Jaw shape', low: 'Round', high: 'Square' },
    { index: 15, label: 'Chin height', low: 'Low', high: 'High' }, { index: 16, label: 'Chin depth', low: 'In', high: 'Out' },
    { index: 17, label: 'Chin width', low: 'Narrow', high: 'Wide' }, { index: 18, label: 'Chin cleft', low: 'None', high: 'Deep' },
  ] },
  { label: 'Neck', items: [{ index: 19, label: 'Thickness', low: 'Thin', high: 'Thick' }] },
];

export const EYE_COLORS: { label: string; hex: string }[] = [
  ['Green', '#3f7a4a'], ['Emerald', '#2f8f6a'], ['Light blue', '#79a8d6'], ['Ocean blue', '#2f6fae'], ['Light brown', '#8b6a44'],
  ['Dark brown', '#4a3222'], ['Hazel', '#7c6a3a'], ['Dark grey', '#4b5058'], ['Light grey', '#9aa1a8'], ['Pink', '#d48aa8'],
  ['Yellow', '#d6c04a'], ['Purple', '#7d55b8'], ['Blackout', '#101010'], ['Shades of grey', '#6e6e6e'], ['Tequila sunrise', '#e0873a'],
  ['Atomic', '#9fd23c'], ['Warp', '#6ad0d8'], ['eCola', '#c0392b'], ['Space ranger', '#3d5fd6'], ['Ying yang', '#d0d0d0'],
  ['Bullseye', '#d03a3a'], ['Lizard', '#8fb03a'], ['Dragon', '#c46a2a'], ['Extra terrestrial', '#4bd08a'], ['Goat', '#b89a4a'],
  ['Smiley', '#e8d24a'], ['Possessed', '#f0f0f0'], ['Demon', '#a01818'], ['Infected', '#b0c87a'], ['Alien', '#58e0b0'],
  ['Undead', '#c8c8b8'], ['Zombie', '#8a9a6a'],
].map(([label, hex]) => ({ label, hex }));

export const FOCUS_LABELS: { id: Focus; label: string }[] = [
  { id: 'head', label: 'Face' }, { id: 'body', label: 'Body' }, { id: 'legs', label: 'Legs' }, { id: 'feet', label: 'Shoes' }, { id: 'full', label: 'Full' },
];
