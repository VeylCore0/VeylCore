// Everything that talks to the game: messages from Lua, server pushes, and the actions apps trigger.
// The server owns all state; this file only mirrors it into the store.
import { api, post } from './api';
import { clockText, setClockOffset } from './format';
import { getState, resetState, setState, DEFAULT_SETTINGS } from './store';
import { playNotify, playTimerDone, startRing, stopRing } from './sound';
import { say, toast } from './ui';
import type { Banner, Call, Conversation, ExternalApp, Hello, MailItem, Notification, PushEvent, Settings, World } from './types';

// ---------------------------------------------------------------------------
// Push bus: components that show live data (an open thread, the inbox) listen here
// ---------------------------------------------------------------------------
type PushListener = (e: PushEvent) => void;
const pushListeners = new Set<PushListener>();
export function onPush(fn: PushListener) { pushListeners.add(fn); return () => { pushListeners.delete(fn); }; }

/** The conversation currently on screen (no banner, no unread, read receipt sent). */
let activeThread: number | null = null;
export const setActiveThread = (id: number | null) => { activeThread = id; };

// ---------------------------------------------------------------------------
// Banners
// ---------------------------------------------------------------------------
let bannerSeq = 0;
export function banner(b: Omit<Banner, 'id'>, ms = 4600) {
  const id = ++bannerSeq;
  setState((s) => ({ banners: [...s.banners.filter((x) => !(b.sticky && x.kind === b.kind)).slice(-2), { ...b, id }] }));
  if (!b.sticky) window.setTimeout(() => dismissBanner(id), ms);
  return id;
}
export function dismissBanner(id: number) { setState((s) => ({ banners: s.banners.filter((b) => b.id !== id) })); }
const dropBanners = (kind: Banner['kind']) => setState((s) => ({ banners: s.banners.filter((b) => b.kind !== kind) }));

// ---------------------------------------------------------------------------
// Messages from Lua (action names: docs/PHONE.md)
// ---------------------------------------------------------------------------
const mergeHello = (h: Hello) => {
  setClockOffset(h.serverTime);
  const settings = { ...DEFAULT_SETTINGS, ...h.settings };
  setState((s) => ({
    hello: h, settings, badges: h.badges ?? {}, unread: h.unread ?? s.unread, external: h.external ?? s.external,
    world: h.world ?? s.world, call: h.call ?? null,
  }));
  if (h.call) applyCall(h.call, false);
};

export function onSession(h: Hello) { mergeHello(h); }

export function onOpen(h: Hello) {
  mergeHello(h);
  setState((s) => ({
    open: true, openId: s.openId + 1, shade: false, callMin: false,
    app: h.open?.app ?? s.app, route: h.open?.app ? h.open.route : s.route,
    banners: s.banners.filter((b) => b.kind === 'call'),
  }));
}

export function onClosed() { setState({ open: false, shade: false }); }

export function onReset() {
  stopRing();
  resetState();
}

export function onTick(world: World) { setState({ world }); }
export function onApps(external: ExternalApp[]) { setState({ external }); }
export function onNavigate(app: string, route?: string) { setState({ app, route, shade: false }); }

// ---------------------------------------------------------------------------
// Pushes
// ---------------------------------------------------------------------------
const upsertConversation = (list: Conversation[] | null, c: Conversation) => {
  if (!list) return list;
  return [c, ...list.filter((x) => x.id !== c.id)];
};

export function onPushEvent(e: PushEvent) {
  const s = getState();
  switch (e.event) {
    case 'notification': {
      const n = e.data.notification;
      setState((st) => ({
        unread: { ...st.unread, notifications: e.data.unread },
        notifications: st.notifications ? [n, ...st.notifications.filter((x) => x.id !== n.id)] : st.notifications,
      }));
      banner({ app: n.app, title: n.title, body: n.body, route: n.route, kind: 'notification' });
      playNotify(s.settings, e.data.silent);
      break;
    }
    case 'badge':
      setState((st) => ({ badges: { ...st.badges, [e.data.app]: e.data.count } }));
      break;
    case 'message': {
      const { conversation: c, message: m } = e.data;
      const viewing = s.open && s.app === 'messages' && activeThread === c.id;
      const conv = viewing ? { ...c, unread: 0 } : c;
      setState((st) => ({
        conversations: upsertConversation(st.conversations, conv),
        unread: m.mine || viewing ? st.unread : { ...st.unread, messages: st.unread.messages + 1 },
      }));
      if (!m.mine && !viewing) {
        const preview = m.kind === 'location' ? 'Shared a location' : m.kind === 'contact' ? `Shared contact ${m.body}` : m.body;
        banner({ app: 'messages', title: c.kind === 'group' ? `${c.title}` : c.title, body: c.kind === 'group' && m.senderDisplay ? `${m.senderDisplay}: ${preview}` : preview, route: `thread/${c.id}`, kind: 'message' });
        playNotify(s.settings, e.data.silent);
      }
      break;
    }
    case 'read':
      setState((st) => ({
        conversations: st.conversations?.map((c) => (c.id === e.data.conversationId && c.kind === 'direct' ? { ...c, peerReadId: e.data.lastReadId } : c)) ?? null,
      }));
      break;
    case 'conversation':
      if (e.data.removed !== undefined) setState((st) => ({ conversations: st.conversations?.filter((c) => c.id !== e.data.removed) ?? null }));
      else if (e.data.conversation) setState((st) => ({ conversations: upsertConversation(st.conversations, e.data.conversation!) }));
      break;
    case 'call': applyCall(e.data, true); break;
    case 'mail': {
      const m: MailItem = e.data.mail;
      setState((st) => ({ unread: { ...st.unread, mail: e.data.unread } }));
      banner({ app: 'mail', title: m.from, body: m.subject, kind: 'mail' });
      playNotify(s.settings, e.data.silent);
      break;
    }
  }
  pushListeners.forEach((l) => l(e));
}

// ---------------------------------------------------------------------------
// Calls (the server's `call` push is the single source of truth)
// ---------------------------------------------------------------------------
let endTimer: number | undefined;
function applyCall(c: Call, live: boolean) {
  window.clearTimeout(endTimer);
  const s = getState();
  if (c.state === 'incoming') {
    setState({ call: c, callMin: false });
    if (live) startRing(s.settings);
    banner({ app: 'phone', title: 'Incoming call', body: c.peer.display, route: 'call', kind: 'call', sticky: true });
    return;
  }
  stopRing();
  dropBanners('call');
  if (c.state === 'ended') {
    setState({ call: c });
    endTimer = window.setTimeout(() => { if (getState().call?.id === c.id) setState({ call: null, callMin: false }); }, 2200);
    return;
  }
  setState((st) => ({ call: c, callMin: st.call?.id === c.id ? st.callMin : false }));
}

export async function startCall(number: string) {
  const res = await api<Call>('callStart', number);
  if (!say(res)) return false;
  if (res.data) applyCall(res.data, false);
  return true;
}
export async function answerCall() {
  const c = getState().call;
  if (!c) return;
  stopRing();
  const res = await api<Call>('callAnswer', c.id);
  if (!say(res)) return;
  if (res.data) applyCall(res.data, false);
}
export async function declineCall() {
  const c = getState().call;
  if (!c) return;
  stopRing();
  say(await api('callDecline', c.id));
  setState({ call: null });
  dropBanners('call');
}
export async function endCall() {
  const c = getState().call;
  if (!c) return;
  stopRing();
  say(await api('callEnd', c.id));
}

// ---------------------------------------------------------------------------
// Navigation and settings
// ---------------------------------------------------------------------------
export function openApp(id: string, route?: string) {
  const ext = getState().external.find((e) => e.id === id);
  if (ext) { void post('openExternal', { id }); return; }
  setState({ app: id, route, shade: false });
}
export const goHome = () => setState({ app: null, route: undefined, shade: false });
export const closePhone = () => { void post('close'); };

/** Notification / banner tap: open the app and route it names. */
export function followRoute(app: string, route?: string) {
  if (app === 'phone' && route === 'call') { setState({ callMin: false }); return; }
  openApp(app === 'system' ? 'settings' : app, route?.startsWith(`${app}/`) ? route.slice(app.length + 1) : route);
}

export async function updateSettings(patch: Partial<Settings>) {
  const before = getState().settings;
  setState({ settings: { ...before, ...patch } });
  const res = await api<Settings>('settingsSave', patch);
  if (res.ok && res.data) setState({ settings: { ...DEFAULT_SETTINGS, ...res.data } });
  else { setState({ settings: before }); say(res); }
  return res.ok;
}

export async function loadNotifications() {
  const res = await api<{ items: Notification[]; unread: number }>('notifications');
  if (res.ok && res.data) setState((s) => ({ notifications: res.data!.items, unread: { ...s.unread, notifications: res.data!.unread } }));
  return res.ok;
}

export function worldClock() {
  const w = getState().world;
  return w ? clockText(w.hour, w.minute) : '';
}

export function timerDone(label: string) {
  playTimerDone(getState().settings);
  banner({ app: 'clock', title: 'Timer', body: label, route: 'timer', kind: 'timer' }, 6000);
  toast(label);
}
