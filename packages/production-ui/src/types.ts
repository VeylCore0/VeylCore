// The shapes the server sends (resources/[veyl]/veyl_production/server/callbacks.lua: tabletState, shop.lua, workstations.lua, properties.lua).

export interface BranchProgress { label: string; icon: string; color: string; xp: number; level: number; levelName: string; nextXp?: number; floor: number; progress: number }
export interface Progress { branches: Record<string, BranchProgress>; stats: Record<string, number>; reputation: { level: number; name: string; xp: number; next?: number; floor: number } }

export interface PlantStatus { id: number; variety: string; label: string; state: 'growing' | 'ready' | 'dead'; x: number; y: number; property?: string | null; growth: number; water: number; nutrient: number; health: number; stage: number; minutesLeft: number; careRatio: number }
export interface Variety { key: string; label: string; branch: string; rarity: string; level: number; locked: boolean; growMinutes: number; yield: number[]; seed: string }
export interface Spot { id: string; label: string; branch: string; level: number; locked: boolean; points: number; ready: number; cooldown: number; x: number; y: number }

export interface Batch { id: number; recipe: string; label: string; state: 'queued' | 'running' | 'done'; startsAt: number; endsAt: number; quality: number; tier?: string; output?: { item: string; count: number }; stage?: string | null; progress: number }
export interface Recipe { id: string; label: string; level: number; branch: string; skill?: number; hazard?: boolean; noQuality?: boolean; locked: boolean; inputs: { item: string; count: number }[]; output: { item: string; count: number }; seconds: number; stages: { label: string; seconds: number }[] }
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

export interface Supplier { id: string; label: string; level: number; locked: boolean; fee: number; open: boolean; hours: number[]; runsLeft: number; minutes: number; kits: number[]; x: number; y: number }
export interface Group { leader: string; members: { id: string; name: string }[]; max: number }
export interface Run { group?: Group; member?: boolean; id: number; supplier: string; state: 'active' | 'picked'; kits: number; expiresAt: number; serverTime: number; pickup: { label: string; x: number; y: number; z: number }; drop?: { label: string; x: number; y: number; z: number } }
export interface SupplierState { suppliers: Supplier[]; run: Run | null; cancelWait: number }
export interface MarketRow { item: string; label: string; base: number; price: number; mult: number; trend: 'high' | 'low' | 'steady'; street: boolean }
export interface Territory { id: string; label: string; x: number; y: number; price: number; accept: number; heat: number; controller?: string | null; controlled: boolean; influence: number; bonus: number }
export interface Regular { id: number; name: string; territory: string; loyalty: number; sales: number; bonus: number; wait: number }
export interface StreetState { market: MarketRow[]; territories: Territory[]; regulars: Regular[]; meet?: { x: number; y: number } | null }
export interface CrewState {
  enabled: boolean; createCost: number; max: number; invite?: { crew: string; from: string } | null;
  crew?: { name: string; xp: number; level: number; nextXp?: number; floor: number; share: boolean; leader: boolean; bonus: number; members: { id: string; name: string; leader: boolean; me: boolean }[] } | null;
}
export interface Activity { kind: string; text: string; at: number }
export interface TabletState {
  player: { name: string }; progress: Progress; plants: PlantStatus[]; varieties: Variety[]; workstations: Bench[]; properties: Properties; gathering: Spot[];
  street: StreetState; crew: CrewState; supplier: SupplierState; shops: { id: string; label: string; branch: string; x: number; y: number }[]; exposure: number;
  recent: Activity[]; police: { enabled: boolean; dispatch: boolean; isPolice: boolean };
  branches: Record<string, { label: string; icon: string; color: string; enabled: boolean }>; ui: { Brand: string; Accent: string; Accent2: string; Currency: string };
  tiers: { max: number; label: string; mult: number }[]; levelNames: string[]; itemLabels: Record<string, string>; serverTime: number;
}

export interface ShopItem { item: string; label: string; price: number; stock: number; max: number; level: number; locked: boolean }
export interface ShopView { unlimited?: boolean; id?: string; label?: string; items: ShopItem[]; sell: { item: string; label: string; base: number; price?: number; trend?: 'high' | 'low' | 'steady' }[]; quality: { max: number; label: string; mult: number }[]; restockMinutes: number }

export type View = { view: 'tablet'; data: { state: TabletState; page?: string } } | { view: 'shop' | 'buyer'; data: ShopView } | { view: 'bench'; data: Bench };
