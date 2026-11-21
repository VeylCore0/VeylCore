// veyl_phone message and data types.

export interface Settings {
  wallpaper: string; accent: string; ringtone: string; notifySound: string; ringVolume: number; notifyVolume: number;
  silent: boolean; dnd: boolean; lockPreview: 'full' | 'sender' | 'hidden'; readReceipts: boolean; showBank: boolean;
  widgets: { clock: boolean; recent: boolean; bank: boolean };
  scale: number; position: 'bottom-right' | 'bottom-left' | 'center-right'; reducedMotion: boolean;
  layout: LayoutEntry[] | null; appPrefs: Record<string, { muted: boolean }>; installed?: string[] | null;
}
export type LayoutEntry = string | { folder: string; apps: string[] };

export interface AppDef {
  id: string; label: string; dock?: boolean; external?: boolean; icon?: string; color?: string;
  core?: boolean; installed?: boolean; category?: string; description?: string;
}

export interface Session {
  number: string; display: string; name: string; settings: Settings; apps: AppDef[];
  external?: { id: string; label: string; icon: string; color: string }[];
  voice: { available: boolean; reason?: string; provider?: string };
  serverTime: number; unread: number; notificationsUnread: number; badges?: Record<string, number>;
  presets: { wallpapers: string[]; accents: string[]; ringtones: string[]; notifySounds: string[] };
  limits: { message: number; groupMembers: number };
  world?: World | null; money?: { bank: number } | null; open?: { app?: string; route?: string };
}
export interface World { hour: number; minute: number; weather: string }

export interface Contact { id: number; name: string; number: string; display: string; note?: string; color: number; favorite: boolean }

export interface Message {
  id: number; convId: number; sender: string; kind: 'text' | 'contact' | 'location' | 'system'; body: string;
  payload?: { name?: string; number?: string; x?: number; y?: number; label?: string } | null; at: number;
  state?: 'sent' | 'delivered' | 'read'; deliveredCount?: number; total?: number; pending?: boolean; failed?: boolean;
}
export interface ConversationItem {
  id: number; kind: 'direct' | 'group'; title: string; number?: string; muted: boolean; unread: number; last?: Message | null; blocked?: boolean; role?: string;
}
export interface Member { number: string; display: string; name?: string; role: 'admin' | 'member'; me: boolean }

export interface Notification { id: number; app: string; title: string; body: string; route?: string | null; is_read?: number | boolean; at: number; quiet?: boolean }

export interface CallState {
  id: number; state: 'outgoing' | 'incoming' | 'connected' | 'ended'; number?: string; display?: string; since?: number; reason?: string; muted?: boolean;
}

export const WEATHER: Record<string, { label: string; icon: string }> = {
  EXTRASUNNY: { label: 'Sunny', icon: 'sun' }, CLEAR: { label: 'Clear skies', icon: 'sun' }, CLOUDS: { label: 'Cloudy', icon: 'cloud' },
  OVERCAST: { label: 'Overcast', icon: 'cloud' }, CLEARING: { label: 'Clearing', icon: 'cloud' }, SMOG: { label: 'Smog', icon: 'cloud' },
  FOGGY: { label: 'Foggy', icon: 'cloud' }, RAIN: { label: 'Rain', icon: 'rain' }, THUNDER: { label: 'Thunderstorm', icon: 'rain' },
  NEUTRAL: { label: 'Mild', icon: 'cloud' }, SNOW: { label: 'Snow', icon: 'cloud' }, SNOWLIGHT: { label: 'Light snow', icon: 'cloud' },
  BLIZZARD: { label: 'Blizzard', icon: 'cloud' }, XMAS: { label: 'Snow', icon: 'cloud' }, HALLOWEEN: { label: 'Eerie', icon: 'moon' },
};

export const APP_STYLE: Record<string, { icon: string; color: string }> = {
  phone: { icon: 'call', color: '#4fbf83' }, messages: { icon: 'chat', color: '#8b63d6' }, contacts: { icon: 'user', color: '#4aa39a' },
  settings: { icon: 'gear', color: '#5d5a6b' }, store: { icon: 'bag', color: '#5b8bd6' },
  flock: { icon: 'bird', color: '#3d9be0' }, bank: { icon: 'bank', color: '#3f9c6d' }, garage: { icon: 'car', color: '#d08b4f' },
  market: { icon: 'tag', color: '#c95d84' }, notes: { icon: 'note', color: '#d4a43c' }, calculator: { icon: 'calc', color: '#4b4a57' },
};

export const CONTACT_COLORS = ['#8b63d6', '#4aa39a', '#d08b4f', '#5b8bd6', '#c95d84', '#7aa34a', '#a07a5a', '#6a6a7a'];

export const fmtNumber = (n?: string) => (n && n.length === 7 ? `${n.slice(0, 3)}-${n.slice(3)}` : n ?? '');
export const initials = (s: string) => s.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]?.toUpperCase()).join('') || '#';

export function timeAgo(at: number, now = Date.now() / 1000) {
  const d = Math.max(0, now - at);
  if (d < 60) return 'now';
  if (d < 3600) return `${Math.floor(d / 60)}m`;
  if (d < 86400) return `${Math.floor(d / 3600)}h`;
  return new Date(at * 1000).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}
export const clock = (at: number) => new Date(at * 1000).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
