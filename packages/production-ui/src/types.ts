// The shapes the server sends (resources/[veyl]/veyl_production/server/callbacks.lua: tabletState, shop.lua, workstations.lua, properties.lua).

export interface BranchProgress { label: string; icon: string; color: string; xp: number; level: number; levelName: string; nextXp?: number; floor: number; progress: number }
export interface Progress { branches: Record<string, BranchProgress>; stats: Record<string, number>; reputation: { level: number; name: string; xp: number; next?: number; floor: number } }

export interface PlantStatus { id: number; variety: string; label: string; state: 'growing' | 'ready' | 'dead'; x: number; y: number; property?: string | null; growth: number; water: number; nutrient: number; health: number; stage: number; minutesLeft: number; careRatio: number }
export interface Variety { key: string; label: string; rarity: string; level: number; locked: boolean; growMinutes: number; yield: number[]; seed: string }
export interface Spot { id: string; label: string; level: number; locked: boolean; cooldown: number; x: number; y: number }

export interface Batch { id: number; recipe: string; label: string; state: 'queued' | 'running' | 'done'; startsAt: number; endsAt: number; quality: number; tier?: string; output?: { item: string; count: number }; stage?: string | null; progress: number }
export interface Recipe { id: string; label: string; level: number; locked: boolean; inputs: { item: string; count: number }[]; output: { item: string; count: number }; seconds: number; stages: { label: string; seconds: number }[] }
export interface Bench { id: number; type: string; label: string; property?: string | null; mine: boolean; x: number; y: number; slots: number; batches: Batch[]; recipes: Recipe[]; serverTime: number }

export interface Upgrade { label: string; icon: string; levels: { price: number; [k: string]: number }[] }
export interface Member { id: string; role: 'employee' | 'guest'; name: string }
export interface Property {
  id: string; label: string; description?: string; price: number; level: number; branch: string; role?: 'owner' | 'employee' | 'guest' | null; owned: boolean; locked: boolean;
  forSale?: boolean; levelOk?: boolean; reserved?: boolean; buyback?: { price: number; seconds: number };
  upgrades?: Record<string, number>; storage?: { slots: number; weight: number }; benches?: { used: number; max: number }; hasCode?: boolean; inside?: boolean;
  pricePaid?: number; raidCooldown?: number; members?: Member[]; sellFor?: number;
}
export interface Properties { properties: Property[]; owned: number; maxOwned: number; upgrades: Record<string, Upgrade> }

export interface Activity { kind: string; text: string; at: number }
export interface TabletState {
  player: { name: string }; progress: Progress; plants: PlantStatus[]; varieties: Variety[]; workstations: Bench[]; properties: Properties; gathering: Spot[];
  recent: Activity[]; police: { enabled: boolean; dispatch: boolean; isPolice: boolean };
  branches: Record<string, { label: string; icon: string; color: string; enabled: boolean }>; ui: { Brand: string; Accent: string; Accent2: string; Currency: string };
  tiers: { max: number; label: string; mult: number }[]; levelNames: string[]; itemLabels: Record<string, string>; serverTime: number;
}

export interface ShopItem { item: string; label: string; price: number; stock: number; max: number; level: number; locked: boolean }
export interface ShopView { items: ShopItem[]; sell: { item: string; label: string; base: number }[]; quality: { max: number; label: string; mult: number }[]; restockMinutes: number }

export type View = { view: 'tablet'; data: { state: TabletState; page?: string } } | { view: 'shop' | 'buyer'; data: ShopView } | { view: 'bench'; data: Bench };
