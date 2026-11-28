// Preview-only backend for the phone's apps (Notes, Bank, Garage, Marketplace, Flock, ...). Same names, shapes and
// rules as veyl_phone's server (docs/PHONE.md); never shipped to FiveM.
import { devEmit, type NuiResponse } from '@veyl/ui';

const now = () => Math.floor(Date.now() / 1000);
const ok = <T,>(data?: T, message?: string): NuiResponse<T> => ({ ok: true, data, message });
const err = (code: string, message: string): NuiResponse<never> => ({ ok: false, code, message });
const fmt = (n: string) => `${n.slice(0, 3)}-${n.slice(3)}`;
let seq = 1000;

// ---------------------------------------------------------------------------- state
type Note = { id: number; title: string; body: string; at: number };
type Act = { id: string; type: string; delta: number; balance: number; reason: string; at: number };
type Listing = { id: number; title: string; body: string; price: number; category: string; number: string; display: string; seller: string; at: number; expires: number; mine: boolean; canDelete: boolean };
type FPost = { id: number; body: string; replyTo: number | null; likes: number; replies: number; at: number; handle: string; display: string; liked: boolean; mine: boolean; canDelete: boolean };
type FProfile = { handle: string; display: string; bio?: string | null };

let notes: Note[] = [];
let bank = { name: 'Alex Morgan', bank: 12840, cash: 420, account: 'VC00000482', accountMasked: '•••• 0482', max: 250000 };
let activity: Act[] = [];
let pendingPayee: { token: string; name: string; label: string } | null = null;
let listings: Listing[] = [];
let flockMe: FProfile | null = null;
let posts: FPost[] = [];
const following = new Set<string>();
const flockProfiles: Record<string, FProfile> = {
  jamie: { handle: 'jamie', display: 'Jamie Cole', bio: 'Mechanic. Strawberry Ave. DM me for parts.' },
  riley: { handle: 'riley', display: 'Riley Park', bio: 'Night shift. Coffee first.' },
  casey: { handle: 'casey', display: 'Casey Nguyen', bio: null },
};
const fromHandle = (h: string): FPost['display'] => flockProfiles[h]?.display ?? h;
let vehicles: Record<string, unknown>[] = [];

export function appsReset(empty: boolean) {
  seq = 1000;
  pendingPayee = null; following.clear();
  bank = { name: 'Alex Morgan', bank: 12840, cash: 420, account: 'VC00000482', accountMasked: '•••• 0482', max: 250000 };
  if (empty) { notes = []; activity = []; listings = []; posts = []; flockMe = null; vehicles = []; return; }
  notes = [
    { id: 1, title: 'Shopping list', body: 'Milk\nEggs\nCoffee beans\nBandages x5', at: now() - 3600 },
    { id: 2, title: 'Heist ideas (just kidding)', body: 'Never. Honest work only. Maybe take the taxi job this weekend.', at: now() - 90000 },
    { id: 3, title: 'Plates to remember', body: 'WTP 0193 - white Sultan near Legion\nKFR 8820 - black Baller, speeding', at: now() - 400000 },
  ];
  activity = [
    { id: 'a1', type: 'bank', delta: 1500, balance: 12840, reason: 'Paycheck', at: now() - 6000 },
    { id: 'a2', type: 'bank', delta: -37, balance: 11340, reason: 'Store purchase', at: now() - 9000 },
    { id: 'a3', type: 'bank', delta: -2500, balance: 11377, reason: 'Vehicle payment', at: now() - 90000 },
    { id: 'a4', type: 'bank', delta: -120, balance: 13877, reason: 'Phone transfer: Rent split', at: now() - 150000 },
    { id: 'a5', type: 'bank', delta: 800, balance: 13997, reason: 'Phone transfer', at: now() - 260000 },
  ];
  listings = [
    { id: 1, title: 'Sultan RS, clean', body: 'Low miles, full tune. Meet at Legion Square.', price: 38000, category: 'vehicles', number: '5550177', display: fmt('5550177'), seller: 'Jamie Cole', at: now() - 5400, expires: now() + 500000, mine: false, canDelete: false },
    { id: 2, title: 'Lawn mowing', body: 'Any size lawn in Vinewood. Quick and cheap.', price: 40, category: 'services', number: '5550123', display: fmt('5550123'), seller: 'Riley Park', at: now() - 20000, expires: now() + 500000, mine: false, canDelete: false },
    { id: 3, title: 'Studio apartment', body: 'Starlite Motel, room 12, furnished.', price: 450, category: 'property', number: '5550188', display: fmt('5550188'), seller: 'Alex Carter', at: now() - 70000, expires: now() + 500000, mine: false, canDelete: false },
    { id: 4, title: 'Lockpick set', body: '', price: 0, category: 'items', number: '5550142', display: fmt('5550142'), seller: 'Alex Morgan', at: now() - 3000, expires: now() + 500000, mine: true, canDelete: true },
  ];
  flockMe = { handle: 'alexm', display: 'Alex Morgan', bio: 'Los Santos local.' };
  const post = (id: number, handle: string, body: string, ago: number, likes: number, replies: number, extra: Partial<FPost> = {}): FPost =>
    ({ id, body, replyTo: null, likes, replies, at: now() - ago, handle, display: fromHandle(handle), liked: false, mine: handle === 'alexm', canDelete: handle === 'alexm', ...extra });
  posts = [
    post(11, 'jamie', 'Fresh brakes, fresh tires, fresh attitude. Come get your car @alexm', 1200, 14, 2),
    post(10, 'riley', 'Anyone else see that chase on Vinewood Blvd? Wild.', 5400, 31, 1, { liked: true }),
    post(9, 'alexm', 'Long shift, good coffee. Los Santos never sleeps.', 18000, 6, 0),
    post(8, 'casey', 'New in town. Where is the best burger?', 50000, 22, 0),
  ];
  following.add('jamie');
  vehicles = [
    { id: 1, model: 'sultan', plate: 'VKX 4821', name: 'Sultan', brand: 'Karin', state: 'garaged', fuel: 78, engine: 98, body: 91, impoundFee: 0, place: 'Legion Square Parking' },
    { id: 2, model: 'banshee', plate: 'WTP 0193', name: 'Banshee', brand: 'Bravado', state: 'out', fuel: 18, engine: 64, body: 46, impoundFee: 0 },
    { id: 3, model: 'blista', plate: 'CUE 3355', name: 'Blista', brand: 'Dinka', state: 'impound', fuel: 10, engine: 30, body: 20, impoundFee: 500, place: 'Impound Lot' },
  ];
}

const threadOf = (id: number) => {
  const post = posts.find((p) => p.id === id);
  if (!post) return err('NOT_FOUND', 'This post was removed');
  return ok({ post, replies: posts.filter((p) => p.replyTo === id).sort((a, b) => a.id - b.id) });
};

const payees: Record<string, { name: string }> = { '5550177': { name: 'Jamie Cole' }, '5550123': { name: 'Riley Park' }, '5550188': { name: 'Alex Carter' }, '5550166': { name: 'Marcus Webb' } };

/** Returns undefined for names this file does not handle. */
export function appsApi(name: string, a: unknown[]): NuiResponse | undefined {
  switch (name) {
    // ---- notes
    case 'notes': return ok([...notes].sort((x, y) => y.at - x.at));
    case 'noteSave': {
      const n = a[0] as { id?: number; title: string; body: string };
      const body = String(n.body ?? '');
      const title = String(n.title ?? '').trim() || body.split('\n')[0].slice(0, 48);
      if (!title) return err('INVALID_INPUT', 'Write something first');
      if (n.id) { const x = notes.find((v) => v.id === n.id); if (!x) return err('NOT_FOUND', 'Note not found'); Object.assign(x, { title, body, at: now() }); return ok({ id: x.id }, 'Saved'); }
      const id = ++seq; notes.push({ id, title, body, at: now() }); return ok({ id }, 'Saved');
    }
    case 'noteDelete': notes = notes.filter((n) => n.id !== a[0]); return ok(undefined, 'Note deleted');

    // ---- bank
    case 'bankOverview': return ok({ ...bank, recent: activity.slice(0, 5), });
    case 'bankHistory': { const off = Number(a[0]) || 0; const rows = activity.slice(off, off + 3); return ok({ rows, nextOffset: off + 3 < activity.length ? off + 3 : null }); }
    case 'bankResolve': {
      const t = String(a[0]).replace(/\D/g, '');
      if (t === '5550142') return err('INVALID_INPUT', 'You cannot send money to yourself');
      const p = payees[t];
      if (!p) return err('NOT_FOUND', 'That number is not in service');
      pendingPayee = { token: 'tok' + ++seq, name: p.name, label: fmt(t) };
      return ok(pendingPayee);
    }
    case 'bankSend': {
      const [token, amount, ref] = a as [string, number, string, string];
      if (!pendingPayee || pendingPayee.token !== token) return err('INVALID_STATE', 'Please confirm the recipient again');
      if (!Number.isInteger(amount) || amount < 1 || amount > bank.max) return err('INVALID_INPUT', 'Enter a whole amount');
      if (amount > bank.bank) return err('INSUFFICIENT_FUNDS', 'Insufficient funds');
      bank.bank -= amount;
      activity.unshift({ id: 'a' + ++seq, type: 'bank', delta: -amount, balance: bank.bank, reason: ref ? `Phone transfer: ${ref}` : 'Phone transfer', at: now() });
      const who = pendingPayee.name; pendingPayee = null;
      return ok({ ...bank, recent: activity.slice(0, 5) }, `Sent $${amount} to ${who}`);
    }
    case 'bankStatus': return ok({ applied: true });

    // ---- garage
    case 'garageList': return ok({ vehicles, valetFee: 250 });
    case 'garageLocate': return ok({ x: 215, y: -810, label: 'Legion Square Parking' }, undefined);
    case 'garageValet': {
      if (bank.bank < 250) return err('INSUFFICIENT_FUNDS', 'Valet costs $250 from your bank');
      bank.bank -= 250;
      const v = vehicles.find((x) => x.id === a[0]); if (v) { v.state = 'out'; v.place = undefined; }
      return ok({ x: 214, y: -806 }, 'Your vehicle is waiting on the road ($250)');
    }

    // ---- marketplace
    case 'marketList': {
      const cat = String(a[0]);
      const items = listings.filter((l) => (cat === 'mine' ? l.mine : cat === 'all' || l.category === cat)).sort((x, y) => y.id - x.id);
      return ok({ items, categories: ['vehicles', 'items', 'services', 'property', 'other'] });
    }
    case 'marketPost': {
      const i = a[0] as { title: string; body: string; price: number; category: string };
      if (!String(i.title).trim()) return err('INVALID_INPUT', 'Give your listing a title');
      const l: Listing = { id: ++seq, title: i.title.trim(), body: i.body ?? '', price: i.price, category: i.category, number: '5550142', display: fmt('5550142'), seller: 'Alex Morgan', at: now(), expires: now() + 600000, mine: true, canDelete: true };
      listings.unshift(l); return ok(l, 'Listing posted');
    }
    case 'marketDelete': listings = listings.filter((l) => l.id !== a[0]); return ok(undefined, 'Listing removed');

    // ---- flock
    case 'flockMe': return ok({ profile: flockMe, counts: flockMe ? { posts: posts.filter((p) => p.mine && !p.replyTo).length, followers: 3, following: following.size } : undefined });
    case 'flockSetup': {
      const h = String(a[0]).replace(/^@/, '').toLowerCase();
      if (!/^[a-z0-9_]{3,15}$/.test(h)) return err('INVALID_INPUT', 'Handles are 3-15 letters, numbers or _');
      if (flockProfiles[h]) return err('DUPLICATE', `@${h} is taken`);
      flockMe = { handle: h, display: String(a[1] || 'Alex Morgan'), bio: String(a[2] ?? '') || null };
      return ok(flockMe, 'Profile saved');
    }
    case 'flockFeed': {
      const items = posts.filter((p) => !p.replyTo && (a[0] !== 'following' || p.mine || following.has(p.handle))).sort((x, y) => y.id - x.id);
      return ok({ items });
    }
    case 'flockThread': return threadOf(Number(a[0]));
    case 'flockUser': {
      const h = String(a[0]).toLowerCase();
      const p = h === flockMe?.handle ? flockMe : flockProfiles[h];
      if (!p) return err('NOT_FOUND', `No one is using @${h}`);
      const items = posts.filter((x) => x.handle === h && !x.replyTo).sort((x, y) => y.id - x.id);
      return ok({ profile: p, counts: { posts: items.length, followers: 12 + (following.has(h) ? 1 : 0), following: 8 }, me: h === flockMe?.handle, following: following.has(h), items });
    }
    case 'flockPost': {
      const i = a[0] as { body: string; replyTo?: number };
      if (!flockMe) return err('NO_PROFILE', 'Pick a handle first');
      if (!String(i.body).trim()) return err('INVALID_INPUT', 'Write something first');
      const p: FPost = { id: ++seq, body: i.body.trim(), replyTo: i.replyTo ?? null, likes: 0, replies: 0, at: now(), handle: flockMe.handle, display: flockMe.display, liked: false, mine: true, canDelete: true };
      posts.push(p);
      if (i.replyTo) { const parent = posts.find((x) => x.id === i.replyTo); if (parent) parent.replies++; }
      return ok(p);
    }
    case 'flockLike': {
      const p = posts.find((x) => x.id === a[0]); if (!p) return err('NOT_FOUND', 'This post was removed');
      const on = a[1] === true; if (on !== p.liked) p.likes += on ? 1 : -1; p.liked = on;
      return ok({ likes: p.likes, liked: on });
    }
    case 'flockDelete': { const p = posts.find((x) => x.id === a[0]); posts = posts.filter((x) => x.id !== a[0]); if (p?.replyTo) { const par = posts.find((x) => x.id === p.replyTo); if (par) par.replies--; } return ok(undefined, 'Post deleted'); }
    case 'flockFollow': { const h = String(a[0]).toLowerCase(); if (a[1]) following.add(h); else following.delete(h); return ok({ following: a[1] === true, counts: { posts: 4, followers: 12 + (a[1] ? 1 : 0), following: 8 } }); }
  }
  void devEmit;
  return undefined;
}
