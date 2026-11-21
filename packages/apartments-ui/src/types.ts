// veyl_apartments message and data types (see resources/[veyl]/veyl_apartments/server/*.lua).
import { nui, type NuiResponse } from '@veyl/ui';

export type Perms = Partial<Record<'enter' | 'storage' | 'wardrobe' | 'furniture' | 'guests' | 'roommates' | 'lease', boolean>>;

export interface LeaseView {
  id: number; unitId: number; number: number; floor: number; building: string; buildingLabel: string; address: string;
  status: string; rent: number; deposit: number; intervalDays: number; paidUntil: number; nextChargeAt: number; serverTime: number;
  autopay: boolean; overdueSince?: number | null; directory: boolean; startedAt: number; periodsPaid: number;
}

export interface ApartmentType {
  id: string; label: string; description: string; rent: number; intervalDays: number; deposit: number; initial: number;
  storage: number; furnitureLimit: number; image: string; amenities: string[]; terms: string[]; available: number;
}
export interface UnitView { id: number; number: number; floor: number; wing: string; type: string; available: boolean }
export interface Catalog {
  building: { id: string; label: string; address: string; amenities: string[] };
  types: ApartmentType[]; units: UnitView[]; myLease: LeaseView | null; canLease: boolean;
  balances: { bank: number; cash: number }; tour: boolean;
}

export interface Roommate { citizenid: string; name: string; status: 'invited' | 'active'; perms: string[]; expires?: number }
export interface GuestPass { id: number; name: string; source: string; singleUse: boolean; used: boolean; expires: number }
export interface Visit { id: number; name: string; expires: number }
export interface Home extends LeaseView {
  role: 'leaseholder' | 'roommate' | 'guest'; perms: Perms; roommates?: Roommate[]; guests?: GuestPass[]; visits?: Visit[];
  blocked?: { citizenid: string; name: string }[]; leaseholder?: { citizenid: string; name: string }; overdue?: boolean;
  furnitureLimit?: number; parking?: { id: string; label: string; x: number; y: number } | null; waypoint: { x: number; y: number };
}
export interface Dashboard {
  homes: Home[]; invites: { leaseId: number; from: string; label: string }[]; parcels: number; recovery: number;
  inside?: { unitId: number; leaseId?: number; kind: string } | null; balances: { bank: number; cash: number };
  categories: string[]; roommatePermissions: string[]; phone: boolean; maxGuestHours: number;
}

export interface FurnitureItem { key: string; label: string; model: string; category: string; price: number }
export interface Piece { id: number; item: string; label: string; model?: string; x: number; y: number; z: number; heading: number; owner: string; price: number; state: string; mine?: boolean }
export interface FurnitureCatalog {
  categories: { id: string; label: string }[]; items: FurnitureItem[]; stored: Piece[]; placedList: Piece[]; canEdit: boolean;
  placed: number; limit: number; sellRate: number; balances: { bank: number }; missing: string[];
}

export const api = <T = unknown>(name: string, ...args: unknown[]): Promise<NuiResponse<T>> => nui<T>('api', { name, args });

export const fmtDate = (ts?: number | null) => (ts ? new Date(ts * 1000).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : '—');
export const fmtDateTime = (ts?: number | null) => (ts ? new Date(ts * 1000).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : '—');
export function relative(ts: number, now: number) {
  const d = ts - now;
  const abs = Math.abs(d);
  const unit = abs >= 86400 ? `${Math.round(abs / 86400)} day${Math.round(abs / 86400) === 1 ? '' : 's'}` : abs >= 3600 ? `${Math.round(abs / 3600)} h` : `${Math.max(1, Math.round(abs / 60))} min`;
  return d >= 0 ? `in ${unit}` : `${unit} ago`;
}

export const PERM_LABEL: Record<string, string> = {
  enter: 'Enter', storage: 'Shared storage', wardrobe: 'Wardrobe', furniture: 'Furniture', guests: 'Guests & visitors', roommates: 'Roommates', lease: 'Lease & rent',
};
export const ROLE_LABEL: Record<string, string> = { leaseholder: 'Leaseholder', roommate: 'Roommate', guest: 'Guest' };
/** Hides the page right away for actions that hand control back to the game (tour, placement, storage). */
export const handOff = (action: string, payload: Record<string, unknown>) => { window.dispatchEvent(new Event('apt-hide')); return nui(action, payload); };
export const newOp = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
