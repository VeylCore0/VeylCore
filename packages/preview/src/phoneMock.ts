// Preview-only stand-in for the veyl_phone server callbacks. Shapes mirror resources/[veyl]/veyl_phone/server/*.lua.
import { devEmit, type NuiResponse } from '@veyl/ui';
import type { Contact, ConversationItem, Message, Session, Settings } from '../../phone-ui/src/types';

const ME = '3105422';
const now = () => Math.floor(Date.now() / 1000);
const fmt = (n: string) => `${n.slice(0, 3)}-${n.slice(3)}`;
const ok = <T,>(data?: T, message?: string): NuiResponse<T> => ({ ok: true, data, message });
const err = (code: string, message: string): NuiResponse => ({ ok: false, code, message });

const baseSettings = (): Settings => ({
  wallpaper: 'aurora', accent: '#b892f4', ringtone: 'veyl', notifySound: 'tap', ringVolume: 0, notifyVolume: 0,
  silent: false, dnd: false, lockPreview: 'sender', readReceipts: true, showBank: true,
  widgets: { clock: true, recent: true, bank: true }, scale: 1, position: 'bottom-right', reducedMotion: false, layout: null, appPrefs: {},
});

interface Conv { id: number; kind: 'direct' | 'group'; name?: string; members: string[]; muted: boolean; messages: Message[] }
let state: { settings: Settings; contacts: Contact[]; blocked: string[]; convs: Conv[]; recents: any[]; nextId: number; ops: Record<string, Message> };

export function phoneReset(empty: boolean) {
  const t = now();
  const contacts: Contact[] = empty ? [] : [
    { id: 1, name: 'Jamie Cole', number: '5551021', display: fmt('5551021'), color: 0, favorite: true },
    { id: 2, name: 'Riley Park', number: '3237784', display: fmt('3237784'), color: 1, favorite: false },
    { id: 3, name: 'Hayes Auto', number: '4240912', display: fmt('4240912'), color: 3, favorite: false, note: 'Mechanic on Strawberry' },
  ];
  const m = (id: number, convId: number, sender: string, body: string, ago: number, st?: Message['state']): Message =>
    ({ id, convId, sender, kind: 'text', body, at: t - ago, state: st, deliveredCount: st === 'sent' ? 0 : 1, total: 1 });
  state = {
    settings: baseSettings(), contacts, blocked: [], recents: [], nextId: 100, ops: {},
    convs: empty ? [] : [
      { id: 1, kind: 'direct', members: [ME, '5551021'], muted: false, messages: [
        m(1, 1, '5551021', 'You around tonight?', 3600), m(2, 1, ME, 'Yeah, after 9', 3500, 'read'), m(3, 1, '5551021', 'Meet at the pier', 600),
      ] },
      { id: 2, kind: 'group', name: 'Crew', members: [ME, '5551021', '3237784'], muted: false, messages: [
        m(4, 2, '3237784', 'Who is driving?', 7200), m(5, 2, ME, 'I can', 7100, 'delivered'),
      ] },
    ],
  };
  if (!empty) state.recents = [
    { id: 1, number: '5551021', display: 'Jamie Cole', outgoing: false, answered: false, missed: true, at: t - 1800 },
    { id: 2, number: '4240912', display: 'Hayes Auto', outgoing: true, answered: true, missed: false, seconds: 74, at: t - 86400 },
  ];
}
phoneReset(false);

const nameOf = (n: string) => state.contacts.find((c) => c.number === n)?.name;
const titleOf = (c: Conv) => (c.kind === 'group' ? c.name ?? 'Group' : (() => { const o = c.members.find((x) => x !== ME)!; return nameOf(o) ?? fmt(o); })());
const unreadOf = (c: Conv) => c.messages.filter((x) => x.sender !== ME && !(x as any).seen).length;

export function phoneSession(empty: boolean): Session {
  return {
    number: ME, display: fmt(ME), name: 'Ann Avery', settings: state.settings,
    apps: [{ id: 'phone', label: 'Phone', dock: true }, { id: 'messages', label: 'Messages', dock: true }, { id: 'contacts', label: 'Contacts', dock: true }, { id: 'settings', label: 'Settings', dock: true }],
    external: [{ id: 'mechanic', label: 'Hayes Auto', icon: 'wrench', color: '#d08b4f' }],
    voice: { available: true, provider: 'pma-voice' }, serverTime: now(), unread: empty ? 0 : 1, notificationsUnread: 0,
    presets: { wallpapers: ['aurora', 'dusk', 'vinewood', 'midnight', 'violet', 'mono'], accents: ['#b892f4', '#7aa7ff', '#5fd3a5', '#f2c66d', '#ef8f96', '#e3e3ea'], ringtones: ['veyl', 'pulse', 'classic', 'chime'], notifySounds: ['tap', 'bell', 'none'] },
    limits: { message: 500, groupMembers: 12 },
    world: { hour: 21, minute: 14, weather: 'CLEAR' }, money: { bank: 12840 },
  };
}

let liveCall = 0;
export function phoneDemo(kind: 'message' | 'call' | 'notification') {
  if (kind === 'message') {
    const c = state.convs.find((x) => x.id === 1) ?? state.convs[0];
    if (!c) return;
    const msg: Message = { id: state.nextId++, convId: c.id, sender: '5551021', kind: 'text', body: 'Running 5 minutes late', at: now() };
    c.messages.push(msg);
    devEmit('phone:push', { event: 'message', data: { message: msg, title: titleOf(c) } });
  } else if (kind === 'call') {
    liveCall = state.nextId++;
    devEmit('phone:push', { event: 'call', data: { id: liveCall, state: 'incoming', number: '3237784', display: 'Riley Park' } });
  } else {
    devEmit('phone:push', { event: 'notification', data: { id: state.nextId++, app: 'mechanic', title: 'Hayes Auto', body: 'Invoice #1042: $640 for repairs', route: 'mechanic', at: now() } });
  }
}

export async function phoneApi(name: string, args: unknown[]): Promise<NuiResponse> {
  const a = args as any[];
  switch (name) {
    case 'saveSettings': state.settings = { ...state.settings, ...(a[0] as Partial<Settings>) }; return ok(state.settings);
    case 'setProfile': return ok({ name: String(a[0]) }, 'Profile updated');
    case 'contacts': return ok(state.contacts.slice().sort((x, y) => Number(y.favorite) - Number(x.favorite) || x.name.localeCompare(y.name)));
    case 'contactSave': {
      const c = a[0] as Contact;
      const number = String(c.number ?? '').replace(/\D/g, '');
      if (number.length !== 7) return err('INVALID_INPUT', 'Enter a 7-digit number');
      if (!c.name?.trim()) return err('INVALID_INPUT', 'Enter a name');
      const existing = state.contacts.find((x) => x.id === c.id);
      if (state.contacts.some((x) => x.number === number && x.id !== c.id)) return err('DUPLICATE', 'That number is already saved');
      if (existing) { Object.assign(existing, { ...c, number, display: fmt(number) }); return ok({ id: existing.id }, 'Contact saved'); }
      const id = state.nextId++;
      state.contacts.push({ id, name: c.name.trim(), number, display: fmt(number), color: c.color ?? 0, favorite: !!c.favorite, note: c.note });
      return ok({ id }, 'Contact added');
    }
    case 'contactDelete': state.contacts = state.contacts.filter((x) => x.id !== a[0]); return ok(undefined, 'Contact deleted');
    case 'blocked': return ok(state.blocked.map((n) => ({ number: n, display: fmt(n), name: nameOf(n) })));
    case 'block': {
      const n = String(a[0]).replace(/\D/g, '');
      if (n.length !== 7) return err('INVALID_INPUT', 'Enter a 7-digit number');
      state.blocked = a[1] ? [...new Set([...state.blocked, n])] : state.blocked.filter((x) => x !== n);
      return ok(undefined, `${fmt(n)} ${a[1] ? 'blocked' : 'unblocked'}`);
    }
    case 'conversations': {
      const items: ConversationItem[] = state.convs.slice().sort((x, y) => (y.messages[y.messages.length - 1]?.at ?? 0) - (x.messages[x.messages.length - 1]?.at ?? 0)).map((c) => {
        const other = c.members.find((x) => x !== ME);
        return { id: c.id, kind: c.kind, title: titleOf(c), number: c.kind === 'direct' ? other : undefined, muted: c.muted, unread: unreadOf(c), last: c.messages[c.messages.length - 1] ?? null };
      });
      return ok({ items, nextOffset: null, unreadTotal: items.reduce((s, i) => s + i.unread, 0) });
    }
    case 'thread': {
      const c = state.convs.find((x) => x.id === a[0]);
      if (!c) return err('NO_PERMISSION', 'You are not in this conversation');
      return ok({
        conv: { id: c.id, kind: c.kind, title: titleOf(c), muted: c.muted, role: 'admin' },
        members: c.members.map((n) => ({ number: n, display: fmt(n), name: nameOf(n), role: n === ME ? 'admin' : 'member', me: n === ME })),
        items: c.messages.slice().reverse(), nextBefore: null,
      });
    }
    case 'read': { const c = state.convs.find((x) => x.id === a[0]); c?.messages.forEach((m) => ((m as any).seen = true)); return ok({ unreadTotal: state.convs.reduce((s, x) => s + unreadOf(x), 0) }); }
    case 'send': {
      const p = a[0] as { to?: string; convId?: number; kind: Message['kind']; body?: string; label?: string; contact?: { name: string; number: string }; clientOp: string };
      if (state.ops[p.clientOp]) return ok(state.ops[p.clientOp]);
      let c = p.convId ? state.convs.find((x) => x.id === p.convId) : state.convs.find((x) => x.kind === 'direct' && x.members.includes(String(p.to)));
      if (!c && p.to) {
        const to = String(p.to).replace(/\D/g, '');
        if (to.length !== 7) return err('INVALID_INPUT', 'Enter a valid number');
        if (to === '5550000') return err('NOT_FOUND', 'That number is not in service');
        c = { id: state.nextId++, kind: 'direct', members: [ME, to], muted: false, messages: [] };
        state.convs.push(c);
      }
      if (!c) return err('NO_PERMISSION', 'You are not in this conversation');
      const msg: Message = {
        id: state.nextId++, convId: c.id, sender: ME, kind: p.kind, body: p.kind === 'text' ? String(p.body ?? '') : '', at: now(), state: 'sent', deliveredCount: 0, total: c.members.length - 1,
        payload: p.kind === 'location' ? { x: 215.4, y: -810.2, label: p.label ?? 'Shared location' } : p.kind === 'contact' ? p.contact : null,
      };
      c.messages.push(msg);
      state.ops[p.clientOp] = msg;
      const convId = c.id; const id = msg.id; const total = msg.total!;
      setTimeout(() => { msg.state = 'delivered'; msg.deliveredCount = total; devEmit('phone:push', { event: 'receipt', data: { convId, id, state: 'delivered', delivered: total, total } }); }, 900);
      return ok(msg);
    }
    case 'mute': { const c = state.convs.find((x) => x.id === a[0]); if (c) c.muted = !!a[1]; return ok({ muted: !!a[1] }, a[1] ? 'Conversation muted' : 'Conversation unmuted'); }
    case 'groupCreate': {
      const members = (a[1] as string[]) ?? [];
      if (!String(a[0] ?? '').trim()) return err('INVALID_INPUT', 'Name the group');
      if (members.length < 2) return err('INVALID_INPUT', 'Pick at least two people');
      const id = state.nextId++;
      state.convs.push({ id, kind: 'group', name: String(a[0]).trim(), members: [ME, ...members], muted: false, messages: [] });
      return ok({ id }, 'Group created');
    }
    case 'groupRename': { const c = state.convs.find((x) => x.id === a[0]); if (c) c.name = String(a[1]); return ok(undefined, 'Group renamed'); }
    case 'groupAdd': { const c = state.convs.find((x) => x.id === a[0]); c?.members.push(String(a[1])); return ok(undefined, 'Member added'); }
    case 'groupRemove': { const c = state.convs.find((x) => x.id === a[0]); if (c) c.members = c.members.filter((n) => n !== a[1]); return ok(undefined, 'Member removed'); }
    case 'groupLeave': state.convs = state.convs.filter((x) => x.id !== a[0]); return ok(undefined, 'You left the group');
    case 'recents': return ok({ items: state.recents, voice: { available: true } });
    case 'notifications': return ok({ items: [], badges: {} });
    case 'notificationsRead': case 'notificationsClear': return ok({ unread: 0 });
    case 'callStart': {
      const n = String(a[0]).replace(/\D/g, '');
      if (n.length !== 7) return err('INVALID_INPUT', 'Enter a valid number');
      if (n === '5550000') return err('UNAVAILABLE', 'The number you called is unavailable');
      liveCall = state.nextId++;
      const id = liveCall;
      state.recents.unshift({ id, number: n, display: nameOf(n) ?? fmt(n), outgoing: true, answered: true, missed: false, at: now() });
      setTimeout(() => { if (liveCall === id) devEmit('phone:push', { event: 'call', data: { id, state: 'connected', since: now() } }); }, 1800);
      return ok({ id, state: 'ringing', number: n, display: nameOf(n) ?? fmt(n) });
    }
    case 'callAnswer': return ok({ id: a[0], state: 'connected', since: now() });
    case 'callDecline': case 'callEnd': liveCall = 0; return ok();
    case 'callMute': return ok({ muted: !!a[1] });
    default: return err('NOT_IMPLEMENTED', `No demo handler for ${name}`);
  }
}
