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
