// Messages for veyl_garages ('garage:open') and veyl_dealership ('dealer:open').

export type Method = 'cash' | 'bank';

export interface GarageVehicle {
  id: number; model: string; plate: string; name: string; brand?: string; label?: string;
  state: 'out' | 'garaged' | 'impound'; garage?: string; garageLabel?: string;
  fuel: number; engine: number; body: number; // percentages
  impoundFee: number; impoundReason?: string;
  here: boolean; // can be taken out at this garage / released at this impound lot
  out: boolean;  // a live instance exists in the world
}

export interface GarageOpen {
  kind: 'garage' | 'impound'; placeId: string; title: string;
  vehicles: GarageVehicle[];
  balances: { cash: number; bank: number };
  methods: Method[];
  imagePath?: string; // default nui://veyl_vehicles/web/images (one <model>.webp per model)
}

export interface DealerVehicle { model: string; name: string; brand?: string; price: number; category: string }

export interface DealerOpen {
  title: string; subtitle: string;
  categories: { id: string; label: string }[];
  vehicles: DealerVehicle[];
  balances: { cash: number; bank: number };
  methods: Method[];
  imagePath?: string; // default nui://veyl_vehicles/web/images (one <model>.webp per model)
}

export const REASONS: Record<string, string> = {
  abandoned: 'Left abandoned', destroyed: 'Wrecked', deleted: 'Removed', impounded: 'Impounded by staff',
};
