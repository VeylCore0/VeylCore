// veyl_phone data shapes. The contract is documented in docs/PHONE.md (server: resources/[veyl]/veyl_phone/server/*.lua).

export type Settings = {
  wallpaper: string; accent: string; ringtone: string; notifySound: string; theme: 'dark' | 'light'; case: string;
  volume: number; brightness: number; size: number;
  dnd: boolean; airplane: boolean; silent: boolean; streamer: boolean;
  installed: string[]; home: string[];
};
export type App = { id: string; label: string; description?: string; core: boolean; dock: boolean; installed: boolean };
export type ExternalApp = { id: string; label: string; icon: string; color: string };
export type World = { hour: number; minute: number; weather?: string };
export type Presets = { wallpapers: string[]; accents: string[]; ringtones: string[]; notifySounds: string[]; themes: string[]; cases: string[] };
export type Call = {
  id: number; state: 'incoming' | 'outgoing' | 'connected' | 'ended'; reason?: string;
  peer: { number: string; display: string }; startedAt: number; answeredAt?: number;
};
/** Account and PIN state. `email` is hidden while the phone is locked. */
export type Security = { email?: string | null; hasPin: boolean; setupDone: boolean; grace: number; domain: string; passwordMin: number };
export type Hello = {
  number: string; display: string; name: string; settings: Settings; apps: App[];
  /** A PIN is set and has not been entered: the server sends no personal data until `unlock` succeeds. */
  locked: boolean; security: Security;
  /** false = no SIM card: no service until one is inserted (right-click the phone in the inventory). */
  sim?: boolean;
  voice: { available: boolean; provider?: string; reason?: string };
  call: Call | null;
  unread: { messages: number; notifications: number; mail: number };
  badges: Record<string, number>;
  presets: Presets;
  limits: { message: number; groupMembers: number; groupName: number; name: number; pageSize: number };
  serverTime: number;
  external?: ExternalApp[];
  world?: World;
  open?: { app?: string; route?: string };
};
export type Notification = { id: number; app: string; title: string; body: string; route?: string; read: boolean; time: number };
export type Contact = { id: number; name: string; number: string; display: string; note?: string; favorite: boolean; photo?: string | null };
export type Message = {
  id: number; conversationId: number; sender: string; senderDisplay?: string; mine: boolean; time: number;
  kind: 'text' | 'location' | 'contact' | 'system' | 'photo'; body: string;
  payload?: { x?: number; y?: number; number?: string; name?: string; photo?: number; photoId?: number };
  // client only
  pending?: boolean; failed?: boolean; clientOp?: string;
};
export type Conversation = {
  id: number; kind: 'direct' | 'group'; title: string; peer?: string;
  members: { number: string; display: string; admin: boolean }[];
  muted: boolean; admin: boolean; unread: number; last: Message | null; peerReadId?: number;
};
export type Recent = { id: number; direction: 'in' | 'out'; number: string; display: string; missed: boolean; reason?: string; time: number; duration: number };
export type MailItem = { id: number; from: string; subject: string; preview: string; read: boolean; time: number };
export type MailFull = { id: number; from: string; subject: string; body: string; read: boolean; time: number; unread?: number };

export type PushEvent =
  | { event: 'notification'; data: { notification: Notification; unread: number; silent: boolean } }
  | { event: 'badge'; data: { app: string; count: number } }
  | { event: 'sim'; data: { sim: boolean; hello?: Hello } }
  | { event: 'message'; data: { conversation: Conversation; message: Message; silent: boolean } }
  | { event: 'read'; data: { conversationId: number; number: string; lastReadId: number } }
  | { event: 'conversation'; data: { conversation?: Conversation; removed?: number } }
  | { event: 'call'; data: Call }
  | { event: 'mail'; data: { mail: MailItem; unread: number; silent: boolean } }
  | { event: 'share'; data: ShareRequest };

/** Someone nearby is sharing their number with you (expires = unix seconds). */
export type ShareRequest = { id: number; from: { name: string; number: string; display: string }; expires: number };
export type Nearby = { id: number; name: string; distance: number };

export type Banner = {
  id: number; app: string; title: string; body: string; route?: string; kind: 'notification' | 'message' | 'mail' | 'call' | 'timer' | 'share'; sticky?: boolean;
};
