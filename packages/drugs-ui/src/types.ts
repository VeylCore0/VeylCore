// Messages for veyl_drugs. Passive: 'drugs:placement', 'drugs:card'. Modal: 'drugs:journal' (closed by 'drugs:close').

export interface PlacementState {
  visible: boolean; valid?: boolean; reason?: string | null; label?: string; product?: string;
  container?: 'ground' | 'pot' | 'tub'; canToggle?: boolean;
}

export interface PlantView {
  id: number; typeLabel: string; stage: number; ready: boolean; own: boolean; container?: string;
  // owner / crew only:
  type?: string; variety?: string; varietyLabel?: string; trait?: string; state?: string;
  growth?: number; water?: number; care?: number; health?: number; quality?: number; grade?: string; gradeId?: string;
  expectedYield?: number; etaMinutes?: number; isOwner?: boolean;
  coords?: { x: number; y: number; z: number }; area?: string; street?: string;
}

export interface JournalData {
  plants: PlantView[];
  stats: { plants: number; ready: number; locations: number; limit: number };
}

export const STAGES = ['Seedling', 'Growing', 'Maturing', 'Ready'];
export const CONTAINERS: Record<string, string> = { ground: 'In the ground', pot: 'In a pot', tub: 'Grow tub' };

export function eta(min?: number) {
  if (!min || min <= 0) return 'Ready';
  if (min < 60) return `${min} min`;
  return `${Math.floor(min / 60)} h ${min % 60} min`;
}

/** What the plant needs most, in words. */
export function needs(p: PlantView): { text: string; tone: 'ok' | 'warn' | 'bad' | 'ready' } {
  if (p.ready) return { text: 'Ready to harvest', tone: 'ready' };
  if ((p.water ?? 100) <= 15 || (p.care ?? 100) <= 15) return { text: (p.water ?? 100) <= 15 ? 'Needs water' : 'Needs nutrients', tone: 'bad' };
  if ((p.water ?? 100) < 40 || (p.care ?? 100) < 40) return { text: (p.water ?? 100) < 40 ? 'Getting dry' : 'Could use nutrients', tone: 'warn' };
  return { text: 'Growing', tone: 'ok' };
}

// Equipment ('drugs:equipment')
export interface BatchMeta { product: string; variety: string; varietyLabel: string; grade: string; quality: number; batch: string }
export interface RecipeView {
  id: string; label: string; icon: string; challenge: 'timing' | 'calibration'; msPerUnit: number;
  inputs: { item: string; label: string; count: number; batch: boolean; have: number }[];
  output: { item: string; label: string; count: number };
  batches: { metadata: BatchMeta; count: number }[];
}
export interface EquipmentView {
  id: number; kind: string; label: string; condition: number; maxUnits: number; challengeQuality: number;
  recipes: RecipeView[]; tray: { item: string; label: string; count: number; grade?: string }[]; busy: boolean;
}
