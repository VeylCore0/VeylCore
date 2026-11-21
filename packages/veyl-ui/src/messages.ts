// Message contracts between Lua and the NUI apps (protocol v1). Keep in sync with the Lua senders/handlers
// documented in docs/UI-SUITE.md.

// ---------------- veyl_lib (menus / dialogs / notify / progress) ----------------
export interface MenuOption {
  id: string; label: string; description?: string; icon?: string; image?: string; right?: string;
  disabled?: boolean; disabledReason?: string; hasChildren?: boolean;
}
export interface MenuOpen { token: string; id: string; title: string; subtitle?: string; breadcrumb?: string[]; options: MenuOption[]; canGoBack?: boolean }
export type FieldType = 'text' | 'number' | 'select' | 'checkbox' | 'date';
export interface FormField {
  name: string; label: string; type: FieldType; required?: boolean; min?: number; max?: number; maxLength?: number;
  placeholder?: string; default?: string | number | boolean; options?: { value: string; label: string }[];
}
export interface FormOpen { token: string; title: string; submitLabel?: string; fields: FormField[] }
export interface AlertOpen { token: string; title: string; message: string; confirmLabel?: string; cancelLabel?: string; destructive?: boolean }
export interface NotifyMessage { id: string; title?: string; message: string; type: 'info' | 'success' | 'warning' | 'error'; duration: number }
export interface ProgressMessage { label: string; duration: number; canCancel: boolean }
export interface TextUIMessage { key?: string; text: string }

// ---------------- veyl_target ----------------
export interface TargetOption { index: number; label: string; icon?: string }
export interface TargetState {
  active: boolean;
  options: TargetOption[];
  selected: number;
  /** Context heading, e.g. VEHICLE / PERSON / OBJECT / AREA */
  title?: string;
  /** Short state, e.g. Locked / Unlocked */
  state?: string;
  stateIcon?: string;
  keys?: { hold: string; select: string };
}

// ---------------- veyl_inventory ----------------
export interface ItemDef {
  name: string; label: string; description?: string; image?: string; weight: number; stack: boolean; maxStack?: number; usable: boolean;
}
export interface SlotItem { slot: number; name: string; count: number; metadata?: Record<string, unknown>; durability?: number }
export interface InventoryView {
  ref: 'primary' | 'secondary'; id: string; label: string; type: 'player' | 'stash' | 'trunk' | 'glovebox' | 'drop';
  slots: number; maxWeight: number; weight: number; revision: number; items: SlotItem[];
}
export interface InventoryOpen { primary: InventoryView; secondary?: InventoryView; items: Record<string, ItemDef>; imagePath: string; hotbarSlots?: number }
export interface InventoryDelta { ref: 'primary' | 'secondary'; revision: number; weight: number; slots: { slot: number; item: SlotItem | null }[] }
export interface NearbyPlayer { id: number; name: string; distance: number }

// ---------------- veyl_shops ----------------
export interface ShopCategory { id: string; label: string }
export interface ShopProduct {
  index: number; item: string; label: string; price: number; category: string; image?: string;
  /** null = unlimited */
  stock: number | null;
}
export interface ShopOpen {
  shopId: string; title: string; subtitle: string; categories: ShopCategory[]; products: ShopProduct[];
  methods: ('cash' | 'bank')[]; balances: { cash: number; bank: number }; imagePath: string; maxPerLine: number;
}
export interface CheckoutLine { index: number; count: number }
export interface CheckoutResult { total: number; delivered: { item: string; count: number }[]; refunded: number; balances: { cash: number; bank: number } }

// ---------------- veyl_banking ----------------
export interface BankActivity { id: string; type: 'cash' | 'bank' | string; delta: number; balance: number; reason: string; at: string; icon?: string }
export interface BankOverview {
  name: string; hour: number; bank: number; cash: number; account: string; accountMasked: string; recent: BankActivity[];
}
export interface BankHistoryPage { rows: BankActivity[]; nextOffset: number | null }
export interface RecipientPreview { token: string; name: string; accountMasked: string }

// ---------------- veyl_hud ----------------
export interface HudStatus { health: number; armor: number; hunger: number; thirst: number; stress: number; stamina?: number; oxygen?: number }
export interface HudVehicle { speed: number; unit: 'MPH' | 'KMH'; gear: string; rpm: number; fuel: number | null; seatbelt: 'on' | 'off' | 'unavailable' }
export interface HudVoice { talking: boolean; range: number | null; available: boolean }
export interface HudInfo { serverId: number; cash: number | null; bank: number | null }
export interface HudCompass { heading: number; street: string; zone?: string }
export interface HudSettings { scale: number; showMoney: boolean; showCompass: boolean; showStatus: boolean; showVehicle: boolean; showBrand: boolean; unit: 'MPH' | 'KMH' }
export interface HudMinimap { left: number; bottom: number; width: number; height: number }
export interface HudFrame {
  visible: boolean; status?: HudStatus; vehicle?: HudVehicle | null; voice?: HudVoice; info?: HudInfo; compass?: HudCompass | null;
  minimap?: HudMinimap; settings?: HudSettings;
}
