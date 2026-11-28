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

// ---- Group 2 state: maps, services, voicemail
let mapSaved: { id: number; label: string; x: number; y: number }[] = [{ id: 1, label: 'My garage', x: 215, y: -810 }, { id: 2, label: 'Fishing pier', x: -1850, y: -1230 }];
const MAP_PLACES = [
  { label: 'City Hall', category: 'City', x: -544, y: -204 }, { label: 'Legion Square', category: 'City', x: 195, y: -934 },
  { label: 'Mission Row PD', category: 'Services', x: 441, y: -981 }, { label: 'Pillbox Hospital', category: 'Services', x: 298, y: -584 },
  { label: 'Burger Shot', category: 'Food', x: -1195, y: -884 }, { label: 'Bean Machine', category: 'Food', x: 280, y: -1030 },
  { label: 'Premium Deluxe Motorsport', category: 'Vehicles', x: -33, y: -1102 }, { label: 'Del Perro Apartments', category: 'Housing', x: -1447, y: -537 },
  { label: 'Job Center', category: 'Jobs', x: -265, y: -963 },
];
const SERVICES = [
  { id: 'police', label: 'Police', icon: 'shield', onDuty: 3 }, { id: 'ems', label: 'EMS', icon: 'heart', onDuty: 1 },
  { id: 'mechanic', label: 'Mechanic', icon: 'wrench', onDuty: 2 }, { id: 'taxi', label: 'Taxi', icon: 'car', onDuty: 0 },
];
let svcMine: { id: number; service: string; message: string; status: 'open' | 'taken' | 'closed'; taken_by: string | null; at: number }[] = [];
let vms: { id: number; from_number: string; from_name: string | null; body: string; is_read: number; at: number }[] = [
  { id: 1, from_number: '5550177', from_name: 'Jamie Cole', body: 'Hey, your car is ready at the shop. Come grab it before six, I close early today.', is_read: 0, at: now() - 1800 },
  { id: 2, from_number: '5550911', from_name: null, body: 'This is a message about your vehicle extended warranty.', is_read: 1, at: now() - 90000 },
];
export function appsReset2() { mapSaved = mapSaved.slice(0, 2); svcMine = []; }

// ---- Group 3 state: camera, jobs, bills, news, racing
let photos: { id: number; at: number; image: string }[] = [];
export function previewShot(): string {
  const c = document.createElement('canvas'); c.width = 240; c.height = 320;
  const g = c.getContext('2d');
  if (!g) return '';
  const sky = g.createLinearGradient(0, 0, 0, 320); sky.addColorStop(0, '#ff9a5a'); sky.addColorStop(0.55, '#b3489a'); sky.addColorStop(1, '#241a4a');
  g.fillStyle = sky; g.fillRect(0, 0, 240, 320);
  g.fillStyle = '#ffe9a8'; g.beginPath(); g.arc(150, 120, 34, 0, 7); g.fill();
  g.fillStyle = '#1a1230'; for (let i = 0; i < 9; i++) { const h = 60 + ((i * 53) % 90); g.fillRect(i * 28, 320 - h, 24, h); }
  return c.toDataURL('image/jpeg', 0.7);
}
let jobsMine = [
  { name: 'mechanic', label: 'Mechanic', grade: 'Technician', pay: 480, primary: true },
  { name: 'taxi', label: 'Taxi Driver', grade: 'Driver', pay: 310, primary: false },
];
let jobsOnDuty = false;
const JOB_BOARD = [
  { job: 'mechanic', label: 'Mechanic', description: 'Repair and tune vehicles at Strawberry Customs.', open: true, apply: true, member: true },
  { job: 'police', label: 'Police Officer', description: 'Serve and protect Los Santos. Background check required.', open: false, apply: true, member: false },
  { job: 'ems', label: 'Paramedic', description: 'Respond to emergencies across the city.', open: false, apply: true, member: false },
  { job: 'burgershot', label: 'Burger Shot', description: 'Flip burgers, serve customers. No experience needed.', open: true, apply: true, member: false },
];
let jobApps: { id: number; job: string; status: string; at: number }[] = [{ id: 900, job: 'police', status: 'pending', at: now() - 7200 }];
let jobInbox: { id: number; name: string; number: string; message: string; status: string; at: number }[] = [
  { id: 801, name: 'Casey Nguyen', number: '5550166', message: 'Three years in a body shop, can start immediately and work nights.', status: 'open', at: now() - 3000 },
];
let bills: { kind: 'invoice' | 'citation'; id: number; amount: number; label: string; at: number }[] = [
  { kind: 'invoice', id: 31, amount: 450, label: 'Invoice #31 · Engine repair', at: now() - 86400 },
  { kind: 'citation', id: 12, amount: 200, label: 'Citation #12 · Speeding', at: now() - 172800 },
  { kind: 'invoice', id: 36, amount: 85, label: 'Invoice #36 · Tow', at: now() - 3600 },
];
let standing: { id: number; to_label: string; amount: number; every_days: number; note: string | null; next_at: number; failures: number }[] = [
  { id: 71, to_label: 'Jamie Cole', amount: 250, every_days: 7, note: 'Rent', next_at: now() + 86400 * 3, failures: 0 },
];
let news: { id: number; author: string; title: string; body: string; breaking: number; at: number }[] = [
  { id: 1003, author: 'Mia Torres', title: 'Bank robbery foiled on Vinewood Boulevard', body: 'Police say a three-person crew was stopped outside Fleeca early this morning.\nNo injuries were reported and two suspects are in custody.', breaking: 1, at: now() - 900 },
  { id: 2, author: 'Mia Torres', title: 'Street racing season returns to the harbor', body: 'Organisers confirmed new tracks around the docks this weekend, with prizes for the fastest laps in each class.', breaking: 0, at: now() - 14400 },
  { id: 3, author: 'Dan Okoye', title: 'City Hall opens new job board', body: 'Residents can now browse openings and apply straight from their phones. Several businesses are already hiring.', breaking: 0, at: now() - 90000 },
];
let raceTracks: { id: number; name: string; creator: string; points: number; best: number | null }[] = [
  { id: 1, name: 'Harbor Sprint', creator: 'Casey Nguyen', points: 12, best: 61840 },
  { id: 2, name: 'Vinewood Loop', creator: 'Jamie Cole', points: 8, best: null },
];
let raceOpen: { id: number; track: string; host: string; racers: number; mine: boolean; joined: boolean }[] = [
  { id: 41, track: 'Harbor Sprint', host: 'Casey Nguyen', racers: 3, mine: false, joined: false },
];

/** Returns undefined for names this file does not handle. */
export function appsApi(name: string, a: unknown[]): NuiResponse | undefined {
  switch (name) {
    // ---- maps
    case 'mapsData': return ok({ saved: mapSaved, shared: [{ id: 1, from_name: 'Jamie Cole', x: 120, y: -900, live: 1, expires: now() + 780 }, { id: 2, from_name: 'Riley Park', x: -50, y: 300, live: 0, expires: now() + 300 }], places: MAP_PLACES, shareMinutes: [5, 15, 30, 60] });
    case 'placeSave': { const l = String(a[0] ?? '').trim(); if (!l) return err('INVALID_INPUT', 'Name it first'); mapSaved.push({ id: ++seq, label: l, x: 215, y: -810 }); return ok(undefined, 'Place saved'); }
    case 'placeDelete': mapSaved = mapSaved.filter((p) => p.id !== a[0]); return ok(undefined, 'Place deleted');
    case 'shareLocation': { if (!payees[String(a[0]).replace(/\D/g, '')]) return err('NOT_FOUND', 'No phone with that number'); return ok(undefined, `Location shared for ${a[1]} min`); }
    // ---- services
    case 'servicesData': return ok({ services: SERVICES, mine: svcMine, duty: null, queue: null });
    case 'serviceRequest': { const m = String(a[1] ?? '').trim(); if (m.length < 3) return err('INVALID_INPUT', 'Say what you need'); svcMine.unshift({ id: ++seq, service: String(a[0]), message: m, status: 'open', taken_by: null, at: now() }); return ok(undefined, 'Request sent'); }
    case 'serviceClose': svcMine = svcMine.filter((r) => r.id !== a[0]); return ok(undefined, 'Request closed');
    case 'serviceTake': return ok({ x: 215, y: -810 });
    // ---- voicemail
    case 'voicemailList': return ok([...vms].sort((x, y) => y.at - x.at));
    case 'voicemailRead': { const v = vms.find((x) => x.id === a[0]); if (v) v.is_read = 1; return ok(); }
    case 'voicemailDelete': vms = vms.filter((x) => x.id !== a[0]); return ok(undefined, 'Voicemail deleted');
    case 'voicemailLeave': { if (!payees[String(a[0]).replace(/\D/g, '')]) return err('NOT_FOUND', 'No phone with that number'); return ok(undefined, 'Voicemail sent'); }
    // ---- camera
    case 'photoSave': { if (photos.length >= 40) return err('LIMIT', 'Your gallery is full (40 photos)'); const id = ++seq; photos.unshift({ id, at: now(), image: String(a[0]) }); return ok({ id }, 'Saved to Gallery'); }
    case 'photoList': return ok(photos.map((p) => ({ id: p.id, at: p.at })));
    case 'photoGet': { const p = photos.find((x) => x.id === a[0]); return p ? ok({ image: p.image }) : err('NOT_FOUND', 'Photo not found'); }
    case 'photoDelete': photos = photos.filter((x) => x.id !== a[0]); return ok(undefined, 'Photo deleted');
    // ---- jobs
    case 'jobsData': return ok({ mine: jobsMine, primary: jobsMine.find((j) => j.primary)?.name ?? 'unemployed', onduty: jobsOnDuty, jobLabel: jobsMine.find((j) => j.primary)?.label ?? 'Unemployed', board: JOB_BOARD, apps: jobApps, inbox: jobInbox });
    case 'jobsDuty': jobsOnDuty = !jobsOnDuty; return ok(undefined, jobsOnDuty ? 'Clocked in' : 'Clocked out');
    case 'jobsPrimary': jobsMine = jobsMine.map((j) => ({ ...j, primary: j.name === a[0] })); return ok(undefined, 'Main job changed');
    case 'jobsApply': { if (String(a[1] ?? '').trim().length < 10) return err('INVALID_INPUT', 'Write a few words about yourself'); const b = JOB_BOARD.find((x) => x.job === a[0]); jobApps.unshift({ id: ++seq, job: String(a[0]), status: 'pending', at: now() }); return ok(undefined, `Application sent to ${b?.label ?? 'them'}`); }
    case 'jobsAppClose': jobInbox = jobInbox.filter((x) => x.id !== a[0]); return ok();
    // ---- bills
    case 'billsData': return ok({ bills, standing, score: 712 + (3 - bills.length) * 8 });
    case 'billPay': { const b = bills.find((x) => x.kind === a[0] && x.id === a[1]); if (!b) return err('NOT_FOUND', 'Already paid or not yours'); bills = bills.filter((x) => x !== b); return ok(undefined, 'Paid'); }
    case 'standingCreate': { const n = String(a[0]).replace(/\D/g, ''); if (!payees[n]) return err('NOT_FOUND', 'No phone with that number'); standing.push({ id: ++seq, to_label: payees[n].name, amount: Number(a[1]), every_days: Number(a[2]), note: String(a[3] ?? '') || null, next_at: now() + 86400, failures: 0 }); return ok(undefined, `$${a[1]} to ${payees[n].name} every ${a[2]} days`); }
    case 'standingCancel': standing = standing.filter((x) => x.id !== a[0]); return ok(undefined, 'Standing order cancelled');
    // ---- music
    case 'speakerPlay': return ok(undefined, 'Playing out loud');
    case 'speakerStop': return ok();
    // ---- news
    case 'newsList': return ok({ articles: [...news].sort((x, y) => y.id - x.id), reporter: true });
    case 'newsPost': { const t = String(a[0] ?? '').trim(); const b = String(a[1] ?? '').trim(); if (t.length < 5 || b.length < 20) return err('INVALID_INPUT', 'Write a headline and a story'); news.push({ id: ++seq, author: 'Alex Morgan', title: t, body: b, breaking: a[2] === true ? 1 : 0, at: now() }); return ok(undefined, 'Published'); }
    // ---- racing
    case 'raceData': return ok({ tracks: raceTracks, open: raceOpen });
    case 'raceBoard': return ok([{ name: 'Casey Nguyen', ms: 61840 }, { name: 'Jamie Cole', ms: 63220 }, { name: 'Alex Morgan', ms: 65010 }]);
    case 'raceTrackSave': { if (!Array.isArray(a[1]) || a[1].length < 2) return err('INVALID_INPUT', 'A track needs 2 to 40 checkpoints'); raceTracks.unshift({ id: ++seq, name: String(a[0]), creator: 'Alex Morgan', points: a[1].length, best: null }); return ok(undefined, 'Track saved'); }
    case 'raceHost': { const t = raceTracks.find((x) => x.id === a[0]); if (!t) return err('NOT_FOUND', 'Track not found'); raceOpen.unshift({ id: ++seq, track: t.name, host: 'Alex Morgan', racers: 1, mine: true, joined: true }); return ok({ id: seq, start: { x: 215, y: -810, z: 30 } }, 'Race open'); }
    case 'raceJoin': { const r = raceOpen.find((x) => x.id === a[0]); if (!r) return err('NOT_FOUND', 'That race is gone'); r.joined = true; r.racers++; return ok({ start: { x: 215, y: -810, z: 30 } }, 'Joined. Wait for the host to start.'); }
    case 'raceStart': raceOpen = raceOpen.filter((x) => x.id !== a[0]); return ok(undefined, 'Starting');
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
