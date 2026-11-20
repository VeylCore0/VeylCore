// Message types shared between Lua and the NUI apps (protocol v1). Keep in sync with the Lua senders.

// ---------------- veyl_lib ----------------
export interface MenuOption {
  id: string;
  label: string;
  description?: string;
  icon?: string;
  right?: string;
  disabled?: boolean;
  disabledReason?: string;
  hasChildren?: boolean;
}

export interface MenuOpen {
  token: string;
  id: string;
  title: string;
  subtitle?: string;
  breadcrumb?: string[];
  options: MenuOption[];
  canGoBack?: boolean;
}

export type FieldType = 'text' | 'number' | 'select' | 'checkbox' | 'date';

export interface FormField {
  name: string;
  label: string;
  type: FieldType;
  required?: boolean;
  min?: number;
  max?: number;
  maxLength?: number;
  placeholder?: string;
  default?: string | number | boolean;
  options?: { value: string; label: string }[];
}

export interface FormOpen {
  token: string;
  title: string;
  submitLabel?: string;
  fields: FormField[];
}

export interface AlertOpen {
  token: string;
  title: string;
  message: string;
  confirmLabel?: string;
  cancelLabel?: string;
  destructive?: boolean;
}

export interface NotifyMessage {
  id: string;
  title?: string;
  message: string;
  type: 'info' | 'success' | 'warning' | 'error';
  duration: number;
}

export interface ProgressMessage {
  label: string;
  duration: number;
  canCancel: boolean;
}

export interface TextUIMessage {
  key?: string;
  text: string;
}

// ---------------- veyl_target ----------------
export interface TargetOption {
  index: number;
  label: string;
  icon?: string;
}

export interface TargetState {
  active: boolean;
  options: TargetOption[];
  selected: number;
}

// ---------------- veyl_inventory ----------------
export interface ItemDef {
  name: string;
  label: string;
  description?: string;
  image?: string;
  weight: number;
  stack: boolean;
  maxStack?: number;
  usable: boolean;
}

export interface SlotItem {
  slot: number;
  name: string;
  count: number;
  metadata?: Record<string, unknown>;
  durability?: number;
}

export interface InventoryView {
  ref: 'primary' | 'secondary';
  id: string;
  label: string;
  type: 'player' | 'stash';
  slots: number;
  maxWeight: number;
  weight: number;
  revision: number;
  items: SlotItem[];
}

export interface InventoryOpen {
  primary: InventoryView;
  secondary?: InventoryView;
  items: Record<string, ItemDef>;
  imagePath: string;
}

export interface InventoryDelta {
  ref: 'primary' | 'secondary';
  revision: number;
  weight: number;
  slots: { slot: number; item: SlotItem | null }[];
}
