// Preview-only stand-in for veyl_apartments (shapes mirror resources/[veyl]/veyl_apartments/server/*.lua).
import { devEmit, type NuiResponse } from '@veyl/ui';
import type { Catalog, Dashboard, FurnitureCatalog } from '../../apartments-ui/src/types';

const now = () => Math.floor(Date.now() / 1000);
const ok = <T,>(data?: T, message?: string): NuiResponse<T> => ({ ok: true, data, message });
const err = (code: string, message: string): NuiResponse => ({ ok: false, code, message });

const terms = [
  'Rent is $450 every 7 days, charged from your bank account when each period ends.',
  'You pay the first period and a $450 deposit today.',
  'If a payment fails we retry every 6 hours; after 3 days overdue the lease ends and your storage moves to recovery.',
  'Belongings are never deleted: after a lease ends you can collect them at the front desk for 14 days.',
  'If you move out yourself with no rent owed, your deposit is refunded. Rent already paid is not refunded.',
];

export function aptCatalog(empty: boolean): Catalog {
  const wings = (i: number) => (i % 10 <= 3 ? 'East' : i % 10 <= 6 ? 'South' : 'West');
  const units = Array.from({ length: 30 }, (_, i) => ({ id: i + 1, number: i + 1, floor: Math.floor(i / 10) + 1, wing: wings(i), type: 'starlite_room',
    available: empty ? false : ![0, 4, 11, 12, 19, 22, 27].includes(i) }));
  return {
    building: { id: 'starlite', label: 'Starlite Motel', address: 'East Vinewood, Los Santos', amenities: [] },
    types: [{ id: 'starlite_room', label: 'Starlite Room', description: 'A renovated motel room with a front window onto the walkway. Unfurnished: make it yours.',
      rent: 450, intervalDays: 7, deposit: 450, initial: 900, storage: 40, furnitureLimit: 25, image: 'starlite_room',
      amenities: ['Private entrance', 'Front-desk parcels', 'Courtyard parking'], terms, available: units.filter((u) => u.available).length }],
    units, myLease: null, canLease: true, balances: { bank: 12840, cash: 420 }, tour: true,
  };
}

export function aptDashboard(empty: boolean): Dashboard {
  const t = now();
  if (empty) return { homes: [], invites: [{ leaseId: 9, from: 'Riley Park', label: 'Starlite Motel · Room 14' }], parcels: 0, recovery: 1, inside: null,
    balances: { bank: 12840, cash: 420 }, categories: ['plumbing', 'electrical', 'appliance', 'pest', 'other'], roommatePermissions: ['enter', 'storage', 'wardrobe', 'furniture', 'guests'], phone: true, maxGuestHours: 72 };
  return {
    homes: [{
      id: 3, unitId: 12, number: 12, floor: 2, building: 'starlite', buildingLabel: 'Starlite Motel', address: 'East Vinewood, Los Santos', status: 'active',
      rent: 450, deposit: 450, intervalDays: 7, paidUntil: t + 4 * 86400, nextChargeAt: t + 4 * 86400, serverTime: t, autopay: true, overdueSince: null,
      directory: false, startedAt: t - 10 * 86400, periodsPaid: 2, role: 'leaseholder',
      perms: { enter: true, storage: true, wardrobe: true, furniture: true, guests: true, roommates: true, lease: true },
      roommates: [{ citizenid: 'C', name: 'Cal Reyes', status: 'active', perms: ['enter', 'storage', 'wardrobe'] }, { citizenid: 'D', name: 'Dee Park', status: 'invited', perms: ['enter'] }],
      guests: [{ id: 4, name: 'Jamie Cole', source: 'pass', singleUse: false, used: false, expires: t + 3 * 3600 }],
      visits: [{ id: 7, name: 'Alex Carter', expires: t + 50 }], blocked: [], leaseholder: { citizenid: 'A', name: 'Ann Avery' },
      overdue: false, furnitureLimit: 25, parking: null, waypoint: { x: 960, y: -210 },
    }],
    invites: [], parcels: 1, recovery: 0, inside: null, balances: { bank: 12840, cash: 420 },
    categories: ['plumbing', 'electrical', 'appliance', 'pest', 'other'], roommatePermissions: ['enter', 'storage', 'wardrobe', 'furniture', 'guests'], phone: true, maxGuestHours: 72,
  };
}

export function aptFurniture(): FurnitureCatalog {
  const items = [
    ['kettle', 'Kettle', 'kitchen', 35], ['candles', 'Candles', 'decor', 40], ['table_lamp', 'Table lamp', 'lighting', 110], ['microwave', 'Microwave', 'kitchen', 120],
    ['plant_tall', 'Tall plant', 'decor', 140], ['side_table', 'Side table', 'tables', 150], ['armchair', 'Armchair', 'seating', 450], ['tv', 'Flat-screen TV', 'electronics', 800],
    ['sofa_two', 'Two-seat sofa', 'seating', 900], ['bed_double', 'Double bed', 'beds', 1400], ['bed_wide', 'Wide bed', 'beds', 1800], ['sofa_corner', 'Corner sofa', 'seating', 1600],
  ] as const;
  return {
    categories: [{ id: 'seating', label: 'Seating' }, { id: 'beds', label: 'Beds' }, { id: 'tables', label: 'Tables' }, { id: 'lighting', label: 'Lighting' },
      { id: 'kitchen', label: 'Kitchen' }, { id: 'electronics', label: 'Electronics' }, { id: 'decor', label: 'Decor' }],
    items: items.map(([key, label, category, price]) => ({ key, label, category, price, model: key })),
    stored: [{ id: 21, item: 'armchair', label: 'Armchair', x: 0, y: 0, z: 0, heading: 0, owner: 'A', price: 450, state: 'stored', mine: true }],
    placedList: [{ id: 20, item: 'bed_double', label: 'Double bed', x: -3.2, y: 1.8, z: -1.54, heading: 90, owner: 'A', price: 1400, state: 'placed' },
      { id: 22, item: 'tv', label: 'Flat-screen TV', x: -4.1, y: -1.2, z: -1.54, heading: 0, owner: 'A', price: 800, state: 'placed' }],
    canEdit: true, placed: 2, limit: 25, sellRate: 0.5, balances: { bank: 12840 }, missing: ['bed_wide'],
  };
}

let wardrobe = [{ id: 1, name: 'Work clothes' }, { id: 2, name: 'Night out' }];

export async function aptHandler(action: string, payload: any, mode: string): Promise<NuiResponse> {
  if (action === 'close') { devEmit('apt:close'); return ok(); }
  if (action === 'waypoint') return ok(undefined, 'Waypoint set');
  if (action === 'startPlacement') {
    devEmit('apt:close');
    devEmit('apt:placement', { visible: true, valid: false, reason: 'Keep the doorway clear', label: 'Two-seat sofa', price: 900 });
    return ok();
  }
  if (action === 'tour') { devEmit('apt:close'); devEmit('apt:tour', { seconds: 90, label: 'Starlite Motel · Room 3' }); return ok(); }
  if (action === 'openStash') { devEmit('apt:close'); return ok(); }
  if (action === 'doorbellAnswer') return payload?.id === 7 ? ok(undefined, 'Let Alex Carter in') : err('EXPIRED', 'That request has expired');
  if (action === 'wardrobeAction') {
    if (payload.action === 'save') { wardrobe = [{ id: Date.now(), name: payload.name }, ...wardrobe]; return ok({ outfits: wardrobe }, 'Outfit saved'); }
    if (payload.action === 'delete') { wardrobe = wardrobe.filter((o) => o.id !== payload.id); return ok({ outfits: wardrobe }, 'Outfit deleted'); }
    if (payload.action === 'rename') { wardrobe = wardrobe.map((o) => (o.id === payload.id ? { ...o, name: payload.name } : o)); return ok({ outfits: wardrobe }, 'Outfit renamed'); }
    return ok({ outfits: wardrobe }, 'Outfit changed');
  }
  if (action !== 'api') return err('NOT_IMPLEMENTED', action);
  if (mode === 'error') return err('DATABASE_ERROR', 'Demo: the server rejected this request.');
  const [n, a] = [payload.name as string, (payload.args ?? []) as any[]];
  switch (n) {
    case 'lease': return a[0].unitId === 4 ? err('TAKEN', 'Someone just leased that room. Pick another.') : ok({ id: 9, number: a[0].unitId, floor: 1, buildingLabel: 'Starlite Motel' }, `Room ${a[0].unitId} is yours`);
    case 'dashboard': return ok(aptDashboard(mode === 'empty'));
    case 'payments': return ok({ items: [{ id: 3, kind: 'rent', period: 2, amount: 450, method: 'bank', at: now() - 3 * 86400 }, { id: 1, kind: 'initial', period: 1, amount: 900, method: 'bank', at: now() - 10 * 86400 }], nextBefore: null });
    case 'maintenanceList': return ok([{ id: 1, category: 'plumbing', description: 'Sink drips', status: 'scheduled', staff_name: 'Front desk', scheduled_for: 'Tomorrow 6pm', allow_entry: 0, at: now() - 3600 }]);
    case 'directory': return ok([{ leaseId: 3, name: 'Ann Avery' }, { leaseId: 5, name: 'Riley Park' }].filter((r) => r.name.toLowerCase().includes(String(a[1] ?? '').toLowerCase())));
    case 'ringDirectory': return ok({ seconds: 60 }, 'You rang the bell');
    case 'parcels': return ok([{ id: 4, sender: 'Ammu-Nation', label: 'Order #77', status: 'waiting', items: [{ name: 'flashlight', count: 1 }], at: now() - 7200 }]);
    case 'recoveryList': return ok([{ id: 'apt_l2', label: 'Starlite Motel · Room 3', until_at: now() + 9 * 86400, open: true }]);
    case 'collectParcel': return ok(undefined, 'Collected: Order #77');
    case 'notices': return ok({ items: [{ id: 1, author: 'Cal Reyes', category: 'event', title: 'Courtyard BBQ', body: 'Saturday 6pm. Bring a dish!', at: now() - 7200, mine: false, canRemove: false, reports: 0 }], canPost: true, staff: false });
    case 'furnitureCatalog': return ok(aptFurniture());
    case 'payRent': return err('PAID_AHEAD', 'Rent is already paid for the next period');
    default: return ok(undefined, 'Done (demo)');
  }
}
