// Shapes sent by resources/[veyl]/veyl_hud/client/main.lua (and cleaned by client/settings.lua).

export type GroupKey = 'status' | 'voice' | 'vehicle' | 'info' | 'location';
export type VehicleMode = 'car' | 'motorcycle' | 'boat' | 'heli' | 'bicycle';

export interface Settings {
  enabled: boolean; scale: number; opacity: number; borderOpacity: number; showPercent: boolean; reducedMotion: boolean; snap: boolean;
  colors: { primary: string; secondary: string; text: string };
  player: {
    health: boolean; armor: boolean; hunger: boolean; thirst: boolean; stress: boolean; stamina: boolean; oxygen: boolean; voice: boolean;
    cash: boolean; bank: boolean; playerId: boolean; clock: boolean; location: boolean; postal: boolean; hideFull: boolean; layout: 'list' | 'compact';
  };
  thresholds: { health: number; armor: number; hunger: number; thirst: number; stress: number; stamina: number; oxygen: number };
  minimap: { shape: 'square' | 'circle'; mode: 'always' | 'vehicle' | 'never'; northUp: boolean; scale: number; offsetX: number; offsetY: number;
    street: boolean; direction: boolean; postal: boolean };
  vehicle: {
    auto: boolean; modes: Record<VehicleMode, boolean>; roadUnit: 'MPH' | 'KMH'; airSeaUnit: 'KTS' | 'MPH' | 'KMH'; altUnit: 'FT' | 'M';
    vsUnit: 'FPM' | 'MS'; altMode: 'AGL' | 'MSL'; fuel: boolean; engine: boolean; rpm: boolean; gear: boolean; bikeStamina: boolean;
    seatbelt: boolean; seatbeltAlert: boolean;
  };
  positions: Partial<Record<GroupKey, { x: number; y: number }>>;
}

export interface Caps { circle: boolean; postal: boolean; fuel: string; voice: string; seatbelt: boolean }

export interface Layout { left: number; bottom: number; width: number; height: number; shape: 'square' | 'circle'; safe: number; shown?: boolean }
export interface Status { health?: number; armor?: number; hunger?: number; thirst?: number; stress?: number; stamina?: number; oxygen?: number }
export interface Voice { talking: boolean; mode?: string; level?: number; radio?: boolean; available: boolean }
export interface Info { id: number; cash?: number; bank?: number; time: string }
export interface Location { heading: number; dir: string; street: string; cross?: string; zone?: string; postal?: string }
export interface Vehicle {
  mode: VehicleMode; speed: number; unit: string; rpm?: number; gear?: string; fuel?: number; engine?: 'off' | 'warn' | 'critical';
  seatbelt?: 'on' | 'off'; beltAlert?: boolean; heading?: number; alt?: number; altUnit?: string; altMode?: string; vs?: number; vsUnit?: string; stamina?: number;
}
export interface Frame {
  visible: boolean; layout?: Layout; status?: Status; voice?: Voice; info?: Info; location?: Location; vehicle?: Vehicle | false;
}
