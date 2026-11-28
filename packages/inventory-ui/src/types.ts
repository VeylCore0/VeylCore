import type { SlotItem } from '@veyl/ui';

export type Ref = 'primary' | 'secondary' | 'equip' | 'backpack';
export interface SlotAddress { ref: Ref; slot: number }

export interface View {
  ref: Ref; id: string; label: string; type?: string; slots: number; maxWeight: number; weight: number; revision: number; items: SlotItem[];
}
export interface Delta { ref: Ref; id: string; revision: number; weight: number; slots: { slot: number; item: SlotItem | null }[] }

export interface Def {
  name: string; label: string; description?: string; image?: string; weight: number; stack: boolean; maxStack: number; usable: boolean;
  actions?: { id: string; label: string; icon?: string; tray?: boolean }[]; equip?: string; category?: string;
}
export interface EquipSlot { slot: number; id: string; label: string; icon: string; side: 'left' | 'right' }
export interface Category { id: string; label: string }
export interface Profile { cid: string; name?: string; phone?: string; job?: string }

export interface OpenPayload {
  primary: View; secondary?: View; equip?: View; backpack?: View; equipSlots?: EquipSlot[]; categories?: Category[]; profile?: Profile;
  items: Record<string, Def>; imagePath: string; hotbarSlots?: number; shop?: import('./ShopPanel').ShopInfo;
}

export const key = (a: SlotAddress) => `${a.ref}:${a.slot}`;
export const kgText = (grams: number) => (grams / 1000).toFixed(grams % 1000 === 0 ? 0 : 1);
