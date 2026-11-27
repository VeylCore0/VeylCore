// A tiny global store (no dependency): pushes from the server keep arriving while the phone is closed, so state
// cannot live inside components.
import { useSyncExternalStore } from 'react';
import type { Banner, Call, Conversation, ExternalApp, Hello, Notification, Settings, ShareRequest, World } from './types';

export const DEFAULT_SETTINGS: Settings = {
  wallpaper: 'default', accent: '#8b63d6', ringtone: 'default', notifySound: 'default', theme: 'dark', case: 'black',
  volume: 70, brightness: 100, dnd: false, airplane: false, silent: false, streamer: false, installed: [], home: [],
};

export interface State {
  hello: Hello | null;
  settings: Settings;
  open: boolean;
  openId: number;                      // changes on every open (remounts apps, resets scroll)
  world: World | null;
  external: ExternalApp[];
  badges: Record<string, number>;
  unread: { messages: number; notifications: number; mail: number };
  call: Call | null;
  callMin: boolean;                    // the in-call screen is minimised to the island
  app: string | null;                  // null = home screen
  route: string | undefined;
  shade: boolean;                      // notification centre
  banners: Banner[];
  conversations: Conversation[] | null;
  notifications: Notification[] | null;
  share: ShareRequest | null;          // a "share number" prompt waiting for an answer
}

const initial: State = {
  hello: null, settings: DEFAULT_SETTINGS, open: false, openId: 0, world: null, external: [], badges: {},
  unread: { messages: 0, notifications: 0, mail: 0 }, call: null, callMin: false, app: null, route: undefined, shade: false,
  banners: [], conversations: null, notifications: null, share: null,
};

let state = initial;
const listeners = new Set<() => void>();

export const getState = () => state;
export function setState(patch: Partial<State> | ((s: State) => Partial<State>)) {
  const next = typeof patch === 'function' ? patch(state) : patch;
  state = { ...state, ...next };
  listeners.forEach((l) => l());
}
export function resetState() { state = { ...initial, openId: state.openId }; listeners.forEach((l) => l()); }

const subscribe = (l: () => void) => { listeners.add(l); return () => { listeners.delete(l); }; };
/** Select a primitive or an existing reference from the store (never build a new object in the selector). */
export function useStore<T>(selector: (s: State) => T): T {
  return useSyncExternalStore(subscribe, () => selector(state), () => selector(state));
}
