// Preview-only phone backend: an in-memory stand-in for veyl_phone's server (same names, shapes and pushes as docs/PHONE.md),
// so every screen of the phone UI can be used in the browser. Never shipped to FiveM.
import { devEmit, type NuiResponse } from '@veyl/ui';
import type { App, Call, Contact, Conversation, Hello, MailFull, MailItem, Message, Notification, Recent, Settings } from '../../phone-ui/src/types';

const now = () => Math.floor(Date.now() / 1000);
const fmt = (n: string) => `${n.slice(0, 3)}-${n.slice(3)}`;
const ok = <T,>(data?: T, message?: string): NuiResponse<T> => ({ ok: true, data, message });
const err = (code: string, message: string): NuiResponse<never> => ({ ok: false, code, message });

const ME = '5550142';
const PRESETS = {
  wallpapers: ['default', 'sunset', 'aurora', 'midnight', 'mono'], accents: ['#8b63d6', '#4f8cff', '#2fbf8a', '#f2b443', '#ef6f7c', '#e3e3ea'],
  ringtones: ['default', 'pulse', 'classic', 'chime'], notifySounds: ['default', 'tap', 'none'], themes: ['dark', 'light'],
  cases: ['black', 'blue', 'green', 'orange', 'pink', 'purple', 'red', 'yellow'],
};
const APPS: Omit<App, 'installed'>[] = [
  { id: 'phone', label: 'Phone', core: true, dock: true }, { id: 'messages', label: 'Messages', core: true, dock: true },
  { id: 'contacts', label: 'Contacts', core: true, dock: true }, { id: 'settings', label: 'Settings', core: true, dock: true },
  { id: 'mail', label: 'Mail', core: true, dock: false }, { id: 'store', label: 'App Store', core: true, dock: false },
  { id: 'calculator', label: 'Calculator', core: false, dock: false, description: 'A simple calculator.' },
  { id: 'clock', label: 'Clock', core: false, dock: false, description: 'Time, stopwatch and timer.' },
];
const EXTERNAL = [
  { id: 'apartments', label: 'Apartments', icon: 'home', color: '#8b63d6' }, { id: 'invoices', label: 'Invoices', icon: 'receipt', color: '#d08b4f' },
  { id: 'boosting', label: 'Boosting', icon: 'car', color: '#3b1f4f' }, { id: 'darkweb', label: 'Silk Road', icon: 'eye', color: '#1b1b1f' },
];

interface Conv { id: number; kind: 'direct' | 'group'; name?: string; peer?: string; members: string[]; admins: string[]; muted: boolean; msgs: Message[]; read: Record<string, number>; hidden?: boolean }

let seq = 100;
let contacts: Contact[] = [];
let convs: Conv[] = [];
let mail: MailFull[] = [];
let notifs: Notification[] = [];
let recents: Recent[] = [];
let blocked: string[] = [];
let settings: Settings;
type MockCall = Call & { number: string; dir: 'in' | 'out' };
let call: MockCall | null = null;
let callTimers: number[] = [];
let voiceOk = true;
const badges: Record<string, number> = {};

const nameOf = (n: string) => contacts.find((c) => c.number === n)?.name ?? fmt(n);
const contact = (name: string, number: string, favorite = false, note?: string): Contact => ({ id: ++seq, name, number, display: fmt(number), favorite, note });
const msg = (conversationId: number, sender: string, body: string, ago: number, extra: Partial<Message> = {}): Message =>
  ({ id: ++seq, conversationId, sender, senderDisplay: nameOf(sender), mine: sender === ME, time: now() - ago, kind: 'text', body, ...extra });

function reset(empty: boolean) {
  seq = 100; blocked = []; call = null; callTimers.forEach(clearTimeout); callTimers = [];
  settings = { wallpaper: 'default', accent: '#8b63d6', ringtone: 'default', notifySound: 'default', theme: 'dark', case: 'black', volume: 70, brightness: 100, dnd: false, airplane: false, silent: false, streamer: false, installed: ['calculator', 'clock'], home: [] };
  Object.keys(badges).forEach((k) => delete badges[k]);
  if (empty) { contacts = []; convs = []; mail = []; notifs = []; recents = []; return; }
  contacts = [
    contact('Jamie Cole', '5550177', true, 'Runs the garage on Strawberry'), contact('Riley Park', '5550123', true), contact('Alex Carter', '5550188'),
    contact('Marcus Webb', '5550166'), contact('Sofia Reyes', '5550155'), contact('Dee Okafor', '5550134'), contact('Tony "Tiny" Russo', '5550109'),
  ];
  const mk = (kind: 'direct' | 'group', members: string[], extra: Partial<Conv> = {}): Conv => ({ id: ++seq, kind, members, admins: kind === 'group' ? [ME] : [], muted: false, msgs: [], read: {}, ...extra });
  const jamie = mk('direct', [ME, '5550177'], { peer: '5550177' });
  jamie.msgs = [
    msg(jamie.id, '5550177', 'Yo, car is ready. Come grab it whenever.', 7200), msg(jamie.id, ME, 'Nice. Heading over after my shift', 7100),
    msg(jamie.id, '5550177', 'Cool. I fixed the brakes too, no charge', 6900), msg(jamie.id, ME, 'You are the best', 6800),
    msg(jamie.id, '5550177', 'See you in 20?', 240, {}),
  ];
  jamie.read = { [ME]: jamie.msgs[3].id, '5550177': jamie.msgs[3].id };
  const crew = mk('group', [ME, '5550177', '5550123', '5550188'], { name: 'Friday crew', admins: [ME] });
  crew.msgs = [
    msg(crew.id, ME, 'Created the group', 90000, { kind: 'system', body: 'You created the group' }),
    msg(crew.id, '5550123', 'Who is in for the meet tonight?', 3600), msg(crew.id, '5550188', 'Me. Bringing the Sultan', 3500),
    msg(crew.id, ME, 'Count me in', 3400), msg(crew.id, '5550177', 'Pin dropped', 3300, { kind: 'location', body: 'Vinewood Boulevard, Vinewood', payload: { x: 213.4, y: -812.1 } }),
  ];
  crew.read = { [ME]: crew.msgs[crew.msgs.length - 1].id };
  const sofia = mk('direct', [ME, '5550155'], { peer: '5550155' });
  sofia.msgs = [msg(sofia.id, '5550155', 'Did you get my message about Saturday?', 90000), msg(sofia.id, ME, 'Yes! Works for me', 89000)];
  sofia.read = { [ME]: sofia.msgs[1].id, '5550155': sofia.msgs[0].id };
  const city = mk('direct', [ME, '0000000'], { peer: '0000000' });
  city.msgs = [msg(city.id, '0000000', 'Taxi: your driver Marcus is two minutes away.', 200000)];
  city.read = { [ME]: city.msgs[0].id };
  convs = [jamie, crew, sofia, city];
  mail = [
    { id: ++seq, from: 'Los Santos City Hall', subject: 'Your driver licence is ready', body: 'Good news!\n\nYour driver licence has been processed and is ready at the front desk of City Hall. Bring photo ID.\n\nOffice hours: 9am to 5pm.\n\nLos Santos City Hall', read: false, time: now() - 1800 },
    { id: ++seq, from: 'LS Customs', subject: 'Invoice #4821 - $1,240', body: 'Thanks for visiting LS Customs.\n\nService: Turbo install + tune\nTotal: $1,240\n\nPay it from the Invoices app.', read: false, time: now() - 9000 },
    { id: ++seq, from: 'Burger Shot', subject: 'We are hiring!', body: 'Hi! We have openings for cooks and cashiers. Apply from the Jobs board or visit the store.', read: true, time: now() - 200000 },
  ];
  notifs = [
    { id: ++seq, app: 'apartments', title: 'Rent due tomorrow', body: 'Room 4 at the Starlite Motel. $450.', route: 'apartments', read: false, time: now() - 600 },
    { id: ++seq, app: 'phone', title: 'Missed call', body: 'Marcus Webb', route: 'phone/recents', read: false, time: now() - 4000 },
    { id: ++seq, app: 'invoices', title: 'Mechanic invoice', body: 'LS Customs sent you an invoice for $1,240.', read: true, time: now() - 9000 },
  ];
  recents = [
    { id: ++seq, direction: 'in', number: '5550166', display: 'Marcus Webb', missed: true, reason: 'timeout', time: now() - 4000, duration: 0 },
    { id: ++seq, direction: 'out', number: '5550177', display: 'Jamie Cole', missed: false, time: now() - 9000, duration: 134 },
    { id: ++seq, direction: 'in', number: '5550123', display: 'Riley Park', missed: false, time: now() - 90000, duration: 47 },
    { id: ++seq, direction: 'out', number: '5559021', display: '555-9021', missed: false, time: now() - 200000, duration: 12 },
  ];
  badges.invoices = 1;
}

function unreadOf(c: Conv) { const r = c.read[ME] ?? 0; return c.msgs.filter((m) => m.id > r && !m.mine && m.kind !== 'system' && !blocked.includes(m.sender)).length; }
function summary(c: Conv): Conversation {
  const visible = c.msgs.filter((m) => !blocked.includes(m.sender));
  const last = visible[visible.length - 1] ?? null;
  const peer = c.peer;
  return {
    id: c.id, kind: c.kind, peer, title: c.kind === 'group' ? c.name ?? 'Group' : nameOf(peer!),
    members: c.members.filter((n) => n !== '0000000').map((n) => ({ number: n, display: n === ME ? 'You' : nameOf(n), admin: c.admins.includes(n) })),
    muted: c.muted, admin: c.admins.includes(ME), unread: unreadOf(c), last: last ? { ...last, mine: last.sender === ME, senderDisplay: nameOf(last.sender) } : null,
    peerReadId: c.kind === 'direct' && peer ? c.read[peer] ?? 0 : undefined,
  };
}
const unreadTotal = () => convs.reduce((n, c) => n + (c.members.includes(ME) ? unreadOf(c) : 0), 0);
const mailUnread = () => mail.filter((m) => !m.read).length;
const notifUnread = () => notifs.filter((n) => !n.read).length;
const push = (event: string, data: unknown) => devEmit('phone:push', { event, data });
const callView = (c: MockCall): Call => ({ id: c.id, state: c.state, reason: c.reason, peer: c.peer, startedAt: c.startedAt, answeredAt: c.answeredAt });

export function phoneSession(empty: boolean): Hello {
  void empty;
  const installed = new Set(settings.installed);
  return {
    number: ME, display: fmt(ME), name: 'Alex Morgan', settings, apps: APPS.map((a) => ({ ...a, installed: a.core || installed.has(a.id) })),
    voice: voiceOk ? { available: true, provider: 'pma-voice' } : { available: false, reason: 'Calls need a voice resource (start pma-voice).' },
    call: call ? callView(call) : null, unread: { messages: unreadTotal(), notifications: notifUnread(), mail: mailUnread() }, badges: { ...badges },
    presets: PRESETS, limits: { message: 500, groupMembers: 12, groupName: 32, name: 40, pageSize: 30 }, serverTime: now(),
    external: EXTERNAL, world: { hour: 21, minute: 41, weather: 'CLEAR' },
  };
}

export function phoneReset(empty: boolean) { reset(empty); devEmit('phone:reset'); }

/** Preview buttons: simulate things the server pushes. */
export function phoneDemo(kind: 'message' | 'call' | 'notification' | 'mail' | 'group' | 'share') {
  if (kind === 'message') {
    const c = convs.find((x) => x.peer === '5550177') ?? convs[0];
    if (!c) return;
    const m = msg(c.id, c.peer ?? '5550123', ['Where are you?', 'Pull up to the garage', 'Got the parts you wanted', 'lol you will not believe this'][Math.floor(Math.random() * 4)], 0);
    c.msgs.push(m);
    push('message', { conversation: summary(c), message: m, silent: c.muted });
  } else if (kind === 'group') {
    const c = convs.find((x) => x.kind === 'group');
    if (!c) return;
    const m = msg(c.id, '5550123', 'Meet is moved to 11pm, same spot', 0);
    c.msgs.push(m);
    push('message', { conversation: summary(c), message: m, silent: c.muted });
  } else if (kind === 'call') {
    if (call) return;
    call = { id: ++seq, state: 'incoming', peer: { number: '5550166', display: 'Marcus Webb' }, startedAt: now(), number: '5550166', dir: 'in' };
    push('call', callView(call));
    callTimers.push(window.setTimeout(() => { if (call?.state === 'incoming') endCall('timeout'); }, 30000));
  } else if (kind === 'share') {
    const id = ++seq;
    pendingShares.set(id, { name: 'Jordan Lee', number: '5550611' });
    push('share', { id, from: { name: 'Jordan Lee', number: '5550611', display: fmt('5550611') }, expires: now() + 60 });
  } else if (kind === 'notification') {
    const n: Notification = { id: ++seq, app: 'apartments', title: 'Visitor at your door', body: 'Riley Park is asking to come in.', route: 'apartments', read: false, time: now() };
    notifs.unshift(n);
    push('notification', { notification: n, unread: notifUnread(), silent: false });
  } else {
    const m: MailItem = { id: ++seq, from: 'LS Customs', subject: 'Your car is ready for pickup', preview: 'The work on your Sultan is done. Come by any time.', read: false, time: now() };
    mail.unshift({ ...m, body: 'The work on your Sultan is done.\nCome by any time before 8pm.' });
    push('mail', { mail: m, unread: mailUnread(), silent: false });
  }
}

function endCall(reason: string) {
  if (!call) return;
  callTimers.forEach(clearTimeout); callTimers = [];
  const c = call; call = null;
  const missed = !c.answeredAt && c.peer.number !== ME;
  recents.unshift({ id: ++seq, direction: c.dir, number: c.number, display: nameOf(c.number), missed: missed && (reason === 'timeout' || reason === 'declined'), reason, time: now(), duration: c.answeredAt ? now() - c.answeredAt : 0 });
  push('call', { id: c.id, state: 'ended', reason, peer: c.peer, startedAt: c.startedAt, answeredAt: c.answeredAt });
}

const pendingShares = new Map<number, { name: string; number: string }>();
const NEARBY = [{ id: 14, name: 'Jamie Cole', distance: 0.8 }, { id: 22, name: 'Riley Park', distance: 2.4 }, { id: 31, name: 'Casey Nguyen', distance: 3.6 }];

const CANNED = ['Haha yeah', 'On my way', 'Give me 10 minutes', 'Sounds good to me', 'Send me the location', 'Can you call me?', 'Ok!'];

export function phoneApi(name: string, a: unknown[]): NuiResponse | Promise<NuiResponse> {
  switch (name) {
    case 'hello': return ok(phoneSession(false));
    case 'settingsSave': {
      const p = (a[0] ?? {}) as Partial<Settings>;
      settings = { ...settings, ...p };
      if (settings.airplane && call) endCall('unavailable');
      return ok(settings);
    }
    case 'profileSave': { const n = String(a[0] ?? '').trim(); return n.length < 2 ? err('INVALID_INPUT', 'Use 2 to 48 characters') : ok({ name: n }, 'Profile updated'); }
    case 'appInstall': {
      const [id, on] = a as [string, boolean];
      const list = settings.installed.filter((x) => x !== id); if (on) list.push(id);
      settings = { ...settings, installed: list };
      return ok({ apps: APPS.map((x) => ({ ...x, installed: x.core || list.includes(x.id) })) }, on ? 'Installed' : 'Removed');
    }
    case 'homeSave': return ok({ home: a[0] });
    case 'notifications': return ok({ items: notifs, unread: notifUnread(), more: false });
    case 'notificationsRead': notifs = notifs.map((n) => ({ ...n, read: true })); return ok({ unread: 0 });
    case 'notificationsClear': {
      const ids = a[0];
      notifs = ids === 'all' ? [] : notifs.filter((n) => !(ids as number[]).includes(n.id));
      return ok({ unread: notifUnread() });
    }
    case 'contacts': return ok([...contacts].sort((x, y) => Number(y.favorite) - Number(x.favorite) || x.name.localeCompare(y.name)));
    case 'contactSave': {
      const p = a[0] as { id?: number; name: string; number: string; note?: string; favorite?: boolean };
      const number = String(p.number).replace(/\D/g, '');
      if (!p.name?.trim()) return err('INVALID_INPUT', 'Enter a name');
      if (number.length !== 7) return err('INVALID_INPUT', 'Enter a 7-digit number');
      if (number === ME) return err('INVALID_INPUT', 'That is your own number');
      const existing = contacts.find((c) => c.id === p.id) ?? contacts.find((c) => c.number === number);
      if (existing) { Object.assign(existing, { name: p.name.trim(), number, display: fmt(number), note: p.note, favorite: p.favorite ?? existing.favorite }); return ok(existing, 'Contact saved'); }
      const c = contact(p.name.trim(), number, !!p.favorite, p.note); contacts.push(c); return ok(c, 'Contact saved');
    }
    case 'contactDelete': contacts = contacts.filter((c) => c.id !== a[0]); return ok(undefined, 'Contact deleted');
    case 'blocks': return ok(blocked.map((n) => ({ number: n, display: nameOf(n) })));
    case 'block': {
      const n = String(a[0]).replace(/\D/g, '');
      if (n.length !== 7) return err('INVALID_INPUT', 'Enter a valid number');
      blocked = a[1] === false ? blocked.filter((x) => x !== n) : [...new Set([...blocked, n])];
      return ok({ blocked: a[1] !== false }, a[1] === false ? 'Unblocked' : 'Blocked');
    }
    case 'conversations': return ok(convs.filter((c) => c.members.includes(ME) && !c.hidden && c.msgs.length).sort((x, y) => y.msgs[y.msgs.length - 1].time - x.msgs[x.msgs.length - 1].time).map(summary));
    case 'thread': {
      const c = convs.find((x) => x.id === a[0]); if (!c) return err('NOT_FOUND', 'Conversation not found');
      const before = Number(a[1]) || 0;
      const vis = c.msgs.filter((m) => !blocked.includes(m.sender) && (!before || m.id < before));
      const page = vis.slice(-30);
      return ok({ conversation: summary(c), messages: page.map((m) => ({ ...m, mine: m.sender === ME })), more: vis.length > 30 });
    }
    case 'read': {
      const c = convs.find((x) => x.id === a[0]); if (!c) return err('NOT_FOUND', 'Conversation not found');
      c.read[ME] = c.msgs[c.msgs.length - 1]?.id ?? 0;
      if (c.peer && c.peer !== '0000000') window.setTimeout(() => push('read', { conversationId: c.id, number: ME, lastReadId: c.read[ME] }), 0);
      return ok({ unread: unreadTotal() });
    }
    case 'send': {
      const p = a[0] as { conversationId?: number; to?: string; body?: string; kind?: Message['kind']; payload?: Message['payload']; clientOp: string };
      let c = convs.find((x) => x.id === p.conversationId);
      if (!c) {
        const to = String(p.to ?? '').replace(/\D/g, '');
        if (to.length !== 7 || to === ME) return err('INVALID_INPUT', 'Enter a valid number');
        c = convs.find((x) => x.peer === to);
        if (!c) { c = { id: ++seq, kind: 'direct', peer: to, members: [ME, to], admins: [], muted: false, msgs: [], read: {} }; convs.push(c); }
      }
      if (settings.airplane) return err('UNAVAILABLE', 'Turn off airplane mode first');
      c.hidden = false;
      const kind = p.kind ?? 'text';
      const body = kind === 'contact' ? String(p.payload?.name ?? '') : String(p.body ?? '').trim();
      if (!body) return err('INVALID_INPUT', 'Type a message');
      const payload = kind === 'location' ? { x: 215.4, y: -810.2 } : p.payload;
      const m = msg(c.id, ME, body, 0, { kind, payload });
      c.msgs.push(m); c.read[ME] = m.id;
      const target = c;
      // Pretend the other side reads and answers.
      if (target.peer && target.peer !== '0000000' && !blocked.includes(target.peer)) {
        window.setTimeout(() => { target.read[target.peer!] = m.id; push('read', { conversationId: target.id, number: target.peer, lastReadId: m.id }); }, 1100);
        window.setTimeout(() => {
          const r = msg(target.id, target.peer!, CANNED[Math.floor(Math.random() * CANNED.length)], 0);
          target.msgs.push(r);
          push('message', { conversation: summary(target), message: r, silent: target.muted });
        }, 2600);
      }
      push('message', { conversation: summary(c), message: m, silent: true });
      return ok({ conversation: summary(c), message: m });
    }
    case 'leave': {
      const c = convs.find((x) => x.id === a[0]); if (!c) return err('NOT_FOUND', 'Conversation not found');
      if (c.kind === 'group') c.members = c.members.filter((n) => n !== ME); else c.hidden = true;
      return ok(undefined, c.kind === 'group' ? 'You left the group' : 'Conversation removed');
    }
    case 'mute': { const c = convs.find((x) => x.id === a[0]); if (c) c.muted = a[1] === true; return ok({ muted: a[1] === true }); }
    case 'groupCreate': {
      const p = a[0] as { name: string; numbers: string[] };
      if (!p.name?.trim()) return err('INVALID_INPUT', 'Give the group a name');
      const c: Conv = { id: ++seq, kind: 'group', name: p.name.trim(), members: [ME, ...p.numbers], admins: [ME], muted: false, msgs: [], read: {} };
      c.msgs.push(msg(c.id, ME, '', 0, { kind: 'system', body: 'You created the group' })); convs.push(c);
      return ok(summary(c), 'Group created');
    }
    case 'groupRename': { const c = convs.find((x) => x.id === a[0]); if (c) c.name = String(a[1]); return ok({ name: a[1] }, 'Renamed'); }
    case 'groupAdd': { const c = convs.find((x) => x.id === a[0]); const n = String(a[1]).replace(/\D/g, ''); if (c && !c.members.includes(n)) c.members.push(n); return ok(undefined, 'Added'); }
    case 'groupRemove': { const c = convs.find((x) => x.id === a[0]); if (c) c.members = c.members.filter((n) => n !== a[1]); return ok(undefined, 'Removed'); }
    case 'nearby': return settings.airplane ? ok([]) : ok(NEARBY);
    case 'shareNumber': {
      if (settings.airplane) return err('UNAVAILABLE', 'Turn off airplane mode first');
      const p = NEARBY.find((x) => x.id === a[0]);
      return p ? ok(undefined, `Number sent to ${p.name}`) : err('NOT_FOUND', 'That person is not available');
    }
    case 'shareAnswer': {
      const p = pendingShares.get(Number(a[0]));
      if (!p) return err('NOT_FOUND', 'That request expired');
      pendingShares.delete(Number(a[0]));
      if (a[1] !== true) return ok({ saved: false });
      if (!contacts.some((c) => c.number === p.number)) contacts.push(contact(p.name, p.number));
      return ok({ saved: true }, 'Contact saved');
    }
    case 'callStart': {
      if (!voiceOk) return err('VOICE_UNAVAILABLE', 'Calls need a voice resource (start pma-voice).');
      if (call) return err('BUSY', 'You are already in a call');
      const n = String(a[0]).replace(/\D/g, '');
      if (n.length !== 7 || n === ME) return err('INVALID_INPUT', 'Enter a valid number');
      if (n === '5550000') return err('NOT_FOUND', 'The number you dialled is not in service');
      if (blocked.includes(n) || n === '5550134') return err('UNAVAILABLE', 'The person you are calling is not available');
      call = { id: ++seq, state: 'outgoing', peer: { number: n, display: nameOf(n) }, startedAt: now(), number: n, dir: 'out' };
      const c = call;
      callTimers.push(window.setTimeout(() => { if (call?.id === c.id && call.state === 'outgoing') { call.state = 'connected'; call.answeredAt = now(); push('call', callView(call)); } }, 2600));
      return ok(callView(call));
    }
    case 'callAnswer': { if (!call || call.state !== 'incoming') return err('NOT_FOUND', 'No incoming call'); call.state = 'connected'; call.answeredAt = now(); callTimers.forEach(clearTimeout); return ok(callView(call)); }
    case 'callDecline': endCall('declined'); return ok(undefined);
    case 'callEnd': endCall(call?.state === 'connected' ? 'hangup' : call?.state === 'incoming' ? 'declined' : 'cancelled'); return ok(undefined);
    case 'recents': return ok(recents.filter((r) => r.direction === 'out' || !blocked.includes(r.number)));
    case 'mailList': {
      const before = Number(a[0]) || 0;
      const list = mail.filter((m) => !before || m.id < before).map(({ body, ...m }) => ({ ...m, preview: body.slice(0, 120) }));
      return ok({ items: list, unread: mailUnread(), more: false });
    }
    case 'mailRead': { const m = mail.find((x) => x.id === a[0]); if (!m) return err('NOT_FOUND', 'Mail not found'); m.read = true; return ok({ ...m, unread: mailUnread() }); }
    case 'mailDelete': mail = mail.filter((m) => m.id !== a[0]); return ok({ unread: mailUnread() }, 'Deleted');
    default: return err('NOT_IMPLEMENTED', `No demo handler for ${name}`);
  }
}

/** Preview toggle: pretend pma-voice is not running. */
export function phoneVoice(on: boolean) { voiceOk = on; }
