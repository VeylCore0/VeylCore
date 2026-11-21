// Preview-only stand-ins for the veyl_phone app callbacks (server/apps.lua, flock.lua, bank.lua, garage.lua, market.lua).
import type { NuiResponse } from '@veyl/ui';
import type { AppDef } from '../../phone-ui/src/types';

const now = () => Math.floor(Date.now() / 1000);
const ok = <T,>(data?: T, message?: string): NuiResponse<T> => ({ ok: true, data, message });
const err = (code: string, message: string): NuiResponse => ({ ok: false, code, message });

export const APP_CATALOG: AppDef[] = [
  { id: 'phone', label: 'Phone', dock: true, core: true, installed: true },
  { id: 'messages', label: 'Messages', dock: true, core: true, installed: true },
  { id: 'contacts', label: 'Contacts', dock: true, core: true, installed: true },
  { id: 'settings', label: 'Settings', dock: true, core: true, installed: true },
  { id: 'store', label: 'App Store', core: true, installed: true, category: 'Utilities', description: 'Find and install apps for your phone.' },
  { id: 'flock', label: 'Flock', installed: true, category: 'Social', description: 'Short posts from around the city. Follow people, reply, like and mention with @handle.' },
  { id: 'bank', label: 'Bank', installed: true, category: 'Finance', description: 'Check your balance and activity, and send money to a phone number or account.' },
  { id: 'garage', label: 'Garage', installed: true, category: 'Vehicles', description: 'See every vehicle you own, where it is, and set a waypoint to it.' },
  { id: 'market', label: 'Marketplace', installed: false, category: 'Shopping', description: 'Buy and sell with other residents. Post a listing and get messages or calls.' },
  { id: 'notes', label: 'Notes', installed: false, category: 'Utilities', description: 'Private notes saved to your phone.' },
  { id: 'calculator', label: 'Calculator', installed: true, category: 'Utilities', description: 'A simple calculator.' },
];

type Post = { id: number; body: string; replyTo?: number | null; likes: number; replies: number; at: number; handle: string; display: string; liked: boolean; mine: boolean; canDelete: boolean };
let s: {
  installed: Set<string>; profile: { handle: string; display: string; bio?: string } | null; posts: Post[]; following: Set<string>;
  bank: number; history: { id: string; type: string; delta: number; balance: number; reason: string; at: number }[]; ops: Set<string>;
  notes: { id: number; title: string; body: string; at: number }[]; market: any[]; next: number;
};

export function appsReset(empty: boolean) {
  const t = now();
  s = {
    installed: new Set(APP_CATALOG.filter((a) => !a.core && a.installed).map((a) => a.id)),
    profile: empty ? null : { handle: 'ann', display: 'Ann Avery', bio: 'New in town.' },
    posts: empty ? [] : [
      { id: 3, body: 'Anyone else see the fireworks over Vinewood last night? 🎆', likes: 12, replies: 2, at: t - 600, handle: 'riley', display: 'Riley Park', liked: true, mine: false, canDelete: false },
      { id: 2, body: 'Hayes Auto is open late this week. Bring your car in! @ann', likes: 4, replies: 0, at: t - 5400, handle: 'hayesauto', display: 'Hayes Auto', liked: false, mine: false, canDelete: false },
      { id: 1, body: 'First day in Los Santos. Where should I eat?', likes: 7, replies: 1, at: t - 86400, handle: 'ann', display: 'Ann Avery', liked: false, mine: true, canDelete: true },
      { id: 10, replyTo: 3, body: 'Saw it from Mirror Park, looked amazing', likes: 1, replies: 0, at: t - 300, handle: 'jamie', display: 'Jamie Cole', liked: false, mine: false, canDelete: false },
    ],
    following: new Set(['riley']),
    bank: 12840, ops: new Set(),
    history: empty ? [] : [
      { id: '3', type: 'bank', delta: -640, balance: 12840, reason: 'Invoice #1042: Repairs', at: t - 3600 },
      { id: '2', type: 'bank', delta: 2500, balance: 13480, reason: 'Paycheck', at: t - 86400 },
      { id: '1', type: 'bank', delta: -45, balance: 10980, reason: '24/7 purchase', at: t - 172800 },
    ],
    notes: empty ? [] : [{ id: 1, title: 'Shopping list', body: 'Shopping list\nmilk\neggs\nrepair kit', at: t - 7200 }],
    market: empty ? [] : [
      { id: 1, title: 'Sultan RS, clean title', body: 'Low miles, new tyres. Meet at Legion Square.', price: 42000, category: 'vehicles', number: '3237784', display: '323-7784', seller: 'Riley Park', at: t - 1800, expires: t + 86400 * 6, mine: false, canDelete: false },
      { id: 2, title: 'Lawn mowing', body: 'Vinewood Hills only.', price: 50, category: 'services', number: '5551021', display: '555-1021', seller: 'Jamie Cole', at: t - 9000, expires: t + 86400 * 5, mine: false, canDelete: false },
      { id: 3, title: 'Old radio', body: '', price: 0, category: 'items', number: '3105422', display: '310-5422', seller: 'Ann Avery', at: t - 20000, expires: t + 86400 * 2, mine: true, canDelete: true },
    ],
    next: 1000,
  };
}
appsReset(false);

export function appCatalog() {
  return APP_CATALOG.map((a) => ({ ...a, installed: a.core || s.installed.has(a.id) }));
}

const VEHICLES = [
  { id: 1, model: 'sultan', plate: 'VKX 4821', name: 'Sultan', brand: 'Karin', state: 'garaged', fuel: 76, engine: 98, body: 91, impoundFee: 0, place: 'Legion Square Parking' },
  { id: 2, model: 'banshee', plate: 'BNS 0042', name: 'Banshee', brand: 'Bravado', state: 'out', fuel: 41, engine: 88, body: 63, impoundFee: 0 },
  { id: 3, model: 'faggio', plate: 'MTP 0193', name: 'Faggio', brand: 'Pegassi', state: 'impound', fuel: 18, engine: 40, body: 22, impoundFee: 450, place: 'Impound Lot' },
];

export async function phoneAppsApi(name: string, a: any[]): Promise<NuiResponse | null> {
  switch (name) {
    case 'appInstall': {
      const app = APP_CATALOG.find((x) => x.id === a[0]);
      if (!app || app.core) return err('NOT_FOUND', 'That app is not available');
      if (a[1]) s.installed.add(app.id); else s.installed.delete(app.id);
      return ok({ installed: [...s.installed] }, `${app.label} ${a[1] ? 'installed' : 'removed'}`);
    }
    // Notes
    case 'notes': return ok([...s.notes].sort((x, y) => y.at - x.at));
    case 'noteSave': {
      const n = a[0] as { id?: number; title: string; body: string };
      const title = (n.title || '').trim() || (n.body || '').split('\n')[0].trim();
      if (!title) return err('INVALID_INPUT', 'Write something first');
      const existing = s.notes.find((x) => x.id === n.id);
      if (existing) { Object.assign(existing, { title, body: n.body, at: now() }); return ok({ id: existing.id }, 'Saved'); }
      const id = s.next++; s.notes.push({ id, title, body: n.body, at: now() }); return ok({ id }, 'Saved');
    }
    case 'noteDelete': s.notes = s.notes.filter((x) => x.id !== a[0]); return ok(undefined, 'Note deleted');
    // Flock
    case 'flockMe': return ok({ profile: s.profile, counts: s.profile ? { posts: 1, followers: 3, following: s.following.size } : null });
    case 'flockSetup': {
      const h = String(a[0]).replace(/^@/, '').toLowerCase();
      if (!/^[a-z0-9_]{3,15}$/.test(h)) return err('INVALID_INPUT', 'Handles are 3-15 letters, numbers or _');
      if (h === 'riley') return err('DUPLICATE', '@riley is taken');
      s.profile = { handle: h, display: String(a[1] || 'Ann Avery'), bio: a[2] }; return ok(s.profile, 'Profile saved');
    }
    case 'flockFeed': {
      const top = s.posts.filter((p) => !p.replyTo);
      return ok({ items: a[0] === 'following' ? top.filter((p) => s.following.has(p.handle) || p.mine) : top, nextBefore: null });
    }
    case 'flockThread': {
      const p = s.posts.find((x) => x.id === a[0] && !x.replyTo);
      if (!p) return err('NOT_FOUND', 'This post was removed');
      return ok({ post: p, replies: s.posts.filter((x) => x.replyTo === p.id).sort((x, y) => x.id - y.id) });
    }
    case 'flockUser': {
      const h = String(a[0]).toLowerCase();
      const posts = s.posts.filter((p) => p.handle === h && !p.replyTo);
      const mine = s.profile?.handle === h;
      if (!posts.length && !mine) return err('NOT_FOUND', `No one is using @${h}`);
      const display = mine ? s.profile!.display : posts[0].display;
      return ok({ profile: { handle: h, display, bio: mine ? s.profile!.bio : null }, counts: { posts: posts.length, followers: 3, following: 2 }, me: mine, following: s.following.has(h), items: posts, nextBefore: null });
    }
    case 'flockPost': {
      if (!s.profile) return err('NO_PROFILE', 'Pick a handle first');
      const p = a[0] as { body: string; replyTo?: number };
      const post: Post = { id: s.next++, body: p.body, replyTo: p.replyTo ?? null, likes: 0, replies: 0, at: now(), handle: s.profile.handle, display: s.profile.display, liked: false, mine: true, canDelete: true };
      s.posts.unshift(post);
      if (p.replyTo) { const parent = s.posts.find((x) => x.id === p.replyTo); if (parent) parent.replies++; }
      return ok(post);
    }
    case 'flockLike': { const p = s.posts.find((x) => x.id === a[0]); if (!p) return err('NOT_FOUND', 'Removed'); if (p.liked !== !!a[1]) { p.liked = !!a[1]; p.likes += a[1] ? 1 : -1; } return ok({ likes: p.likes, liked: p.liked }); }
    case 'flockDelete': { const p = s.posts.find((x) => x.id === a[0]); if (!p?.canDelete) return err('NO_PERMISSION', 'You can only delete your own posts'); s.posts = s.posts.filter((x) => x.id !== p.id); return ok(undefined, 'Post deleted'); }
    case 'flockFollow': { const h = String(a[0]); if (a[1]) s.following.add(h); else s.following.delete(h); return ok({ following: !!a[1], counts: { posts: 1, followers: a[1] ? 4 : 3, following: 2 } }); }
    // Bank
    case 'bankOverview': return ok({ name: 'Ann Avery', bank: s.bank, cash: 420, account: 'VC4471993', accountMasked: '•••• 1993', recent: s.history.slice(0, 5), max: 250000 });
    case 'bankHistory': return ok({ rows: s.history, nextOffset: null });
    case 'bankResolve': {
      const t = String(a[0]).replace(/\D/g, '');
      if (t === '3105422') return err('INVALID_INPUT', 'You cannot send money to yourself');
      if (t.length === 7) return t === '5550000' ? err('NOT_FOUND', 'That number is not in service') : ok({ token: 'demo', name: t === '5551021' ? 'Jamie Cole' : 'Resident', label: `${t.slice(0, 3)}-${t.slice(3)}` });
      return err('NOT_FOUND', 'No account with that number');
    }
    case 'bankSend': {
      const amount = Number(a[1]);
      if (s.ops.has(a[3])) return ok({ name: 'Ann Avery', bank: s.bank, cash: 420, account: '', accountMasked: '•••• 1993', recent: s.history.slice(0, 5), max: 250000 }, 'Already sent');
      if (amount > s.bank) return err('INSUFFICIENT_FUNDS', 'Not enough money in your bank account');
      s.ops.add(a[3]); s.bank -= amount;
      s.history.unshift({ id: String(s.next++), type: 'bank', delta: -amount, balance: s.bank, reason: a[2] ? `Phone transfer: ${a[2]}` : 'Phone transfer', at: now() });
      return ok({ name: 'Ann Avery', bank: s.bank, cash: 420, account: '', accountMasked: '•••• 1993', recent: s.history.slice(0, 5), max: 250000 }, `Sent $${amount} (demo)`);
    }
    case 'bankStatus': return ok({ applied: s.ops.has(a[0]) });
    // Garage
    case 'garageList': return ok({ vehicles: VEHICLES });
    case 'garageLocate': { const v = VEHICLES.find((x) => x.id === a[0]); return v ? ok({ x: 1, y: 2, label: v.state === 'out' ? v.plate : v.place }) : err('NOT_FOUND', 'Vehicle not found'); }
    // Marketplace
    case 'marketList': {
      const c = a[0]; const items = s.market.filter((l) => c === 'all' || (c === 'mine' ? l.mine : l.category === c));
      return ok({ items, nextBefore: null, categories: ['vehicles', 'items', 'services', 'property', 'other'] });
    }
    case 'marketPost': {
      const p = a[0];
      if (!String(p.title || '').trim()) return err('INVALID_INPUT', 'Give your listing a title');
      const l = { id: s.next++, title: p.title, body: p.body, price: p.price, category: p.category, number: '3105422', display: '310-5422', seller: 'Ann Avery', at: now(), expires: now() + 7 * 86400, mine: true, canDelete: true };
      s.market.unshift(l); return ok(l, 'Listing posted');
    }
    case 'marketDelete': s.market = s.market.filter((l) => l.id !== a[0]); return ok(undefined, 'Listing removed');
    default: return null;
  }
}
