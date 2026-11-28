// The shapes the server sends (resources/[veyl]/veyl_boosting/server/main.lua: tabletState, contracts.lua: view, offersFor).

export type Tier = 'standard' | 'premium' | 'luxury';
export type ContractState = 'reserved' | 'active' | 'vehicle_acquired' | 'delivery_started' | 'completed' | 'failed' | 'expired' | 'cancelled';

export interface Offer {
  id: string; template: string; label: string; badge: string; description: string; difficulty: number;
  model?: string; vehicleLabel?: string; tier?: Tier; mode: 'solo' | 'group' | 'both'; crew: { min: number; max: number };
  vehicles: number; timeLimit: number; tracked: boolean; minRep: number; minRank: string;
  rewardMin: number; rewardMax: number; repReward: number; risk: number; locked?: string | null;
}

export interface ContractVehicle { index: number; model: string; label: string; tier: Tier; status: 'waiting' | 'acquired' | 'delivered'; netId?: number }
export interface Member { id: string; name: string; leader: boolean; online: boolean; me: boolean }
export interface ActiveContract {
  id: string; template: string; label: string; badge: string; description: string; state: ContractState; difficulty: number;
  leader: boolean; vehicles: ContractVehicle[]; acquired: number; members: Member[]; tracked: boolean; trackerOff: boolean;
  reward: number; repReward: number; createdAt: number; startedAt?: number; expiresAt?: number; reserveUntil?: number;
  area?: { x: number; y: number; r: number }; drop?: { label: string; x: number; y: number; z: number; radius: number };
  canStart: boolean; canCancel: boolean; needsCrew: boolean; timeLimit: number; serverTime: number;
}

export interface CatalogueVehicle { model: string; label: string; tier: Tier; difficulty: number; baseReward: number; minRep: number; unlocked: boolean; solo: boolean; group: boolean }
export interface RankRow { id: string; label: string; rep: number; perk?: string; current: boolean; reached: boolean }
export interface HeatLevel { id: string; max: number; label: string; color: string; rewardMult: number }
export interface Challenge { id: string; kind: 'daily' | 'weekly'; label: string; goal: number; reward: number; progress: number; done: boolean }
export interface Activity { kind: string; text: string; detail?: string | null; at: number }
export interface CrewView { id: string; leader: boolean; members: Member[]; max: number; log: { at: number; text: string }[]; locked: boolean }

export interface TabletState {
  player: { name: string; rank: string; rankIndex: number; rep: number; nextRank?: string; nextRep?: number; rankFloor: number; progress: number };
  heat: { value: number; max: number; level: string; label: string; color: string; rewardMult: number; levels: HeatLevel[]; decay: number; police: boolean };
  active: ActiveContract | null;
  offers: Offer[]; offersAt: number; offersTTL: number;
  catalogue: CatalogueVehicle[]; ranks: RankRow[]; tiers: Record<Tier, { label: string; color: string }>;
  stats: { completed: number; failed: number; rate: number; earnings: number; best?: number | null; rep: number };
  challenges: Challenge[]; recent: Activity[];
  crew: CrewView | null; invite: { from: string; seconds: number } | null;
  event: boolean; ui: { Brand: string; Tagline: string; Accent: string; Accent2: string; Currency: string }; crewMax: number; serverTime: number;
  dropRadius: number; blips: unknown;
}

export interface MinigameStage { stage: number; stages: number; strikes: number; maxStrikes: number; seq: number[]; showMs: number; maxInputMs: number; glyphs: number; token: string }
