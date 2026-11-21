// Preview-only stand-in for veyl_doorlocks (shapes mirror resources/[veyl]/veyl_doorlocks/server/main.lua).
import { devEmit, type NuiResponse } from '@veyl/ui';

const ok = <T,>(data?: T, message?: string): NuiResponse<T> => ({ ok: true, data, message });
const err = (code: string, message: string): NuiResponse => ({ ok: false, code, message });
const settings = (over: Record<string, unknown> = {}) => ({
  locked: true, autoLock: 10, distance: 2.5, hidePrompt: false,
  access: { jobs: { police: 1 }, gangs: {}, requireDuty: true, citizens: [{ citizenid: 'ABC123', name: 'Jamie Cole' }], items: ['keycard'], keys: true, managers: { police: 3 } },
  breach: { lockpick: false, lockpickChance: 0.35, ram: true, ramJobs: { police: 0 }, relock: 300 }, ...over,
});

let doors = [
  { id: 1, name: 'MRPD Front Desk', entities: [{ model: -1215222675, x: 434.7, y: -980.6, z: 30.8, heading: 270 }, { model: 320433149, x: 434.7, y: -983.2, z: 30.8, heading: 270 }], settings: settings(), locked: true, x: 434.7, y: -981.9, z: 30.8 },
  { id: 2, name: 'Hayes Auto Office', entities: [{ model: 1289778077, x: -1427.3, y: -458.1, z: 35.9, heading: 32 }], settings: settings({ access: { jobs: { mechanic: 0 }, gangs: {}, requireDuty: false, citizens: [], items: [], keys: true, managers: { mechanic: 2 } } }), locked: false, x: -1427.3, y: -458.1, z: 35.9 },
];

export function doorEditor(focus?: unknown) {
  return {
    doors, focus, player: { x: 430, y: -980, z: 30.8 },
    jobs: [{ name: 'police', label: 'Police Department', grades: [{ grade: 0, name: 'Cadet' }, { grade: 1, name: 'Officer' }, { grade: 2, name: 'Sergeant' }, { grade: 3, name: 'Chief' }] },
      { name: 'mechanic', label: 'Hayes Auto', grades: [{ grade: 0, name: 'Trainee' }, { grade: 1, name: 'Mechanic' }, { grade: 2, name: 'Owner' }] }],
    gangs: [{ name: 'ballas', label: 'Ballas', grades: [{ grade: 0, name: 'Member' }] }],
    items: [{ name: 'keycard', label: 'Keycard' }, { name: 'lockpick', label: 'Lockpick' }, { name: 'phone', label: 'Phone' }],
    limits: { distance: [1, 10], autoLock: 3600, maxEntities: 4 },
  };
}
export const doorManage = () => ({ id: 2, name: 'Hayes Auto Office', locked: false, businessOpen: false, grants: [{ id: 5, name: 'Riley Park', expires: Math.floor(Date.now() / 1000) + 7200 }],
  keys: 2, maxKeys: 20, maxHours: 168, keysEnabled: true, serverTime: Math.floor(Date.now() / 1000), phone: true });

export async function doorHandler(action: string, payload: any): Promise<NuiResponse> {
  if (action === 'close') { devEmit('door:close'); return ok(); }
  if (action === 'teleport') { devEmit('door:close'); return ok(); }
  if (action === 'pickDoors') {
    devEmit('door:close');
    devEmit('door:select', { visible: true, count: 0, max: 4, aiming: true, already: false, isDoor: true });
    window.setTimeout(() => {
      devEmit('door:select', { visible: false });
      const draft = { ...payload.draft, entities: [{ model: 1289778077, x: -1427.3, y: -458.1, z: 35.9, heading: 32 }] };
      devEmit('door:open', { view: 'editor', data: doorEditor({ draft }) });
    }, 900);
    return ok();
  }
  if (action !== 'api') return err('NOT_IMPLEMENTED', action);
  const [n, a] = [payload.name as string, (payload.args ?? []) as any[]];
  switch (n) {
    case 'adminData': return ok(doorEditor());
    case 'adminSave': {
      const d = a[0];
      if (!String(d.name ?? '').trim()) return err('INVALID_INPUT', 'Give the door a name');
      if (d.id) doors = doors.map((x) => (x.id === d.id ? { ...x, ...d } : x));
      else doors = [...doors, { ...d, id: doors.length + 10, locked: d.settings.locked, x: d.entities[0].x, y: d.entities[0].y, z: d.entities[0].z }];
      return ok({ id: d.id ?? doors.length + 9 }, d.id ? 'Door saved' : 'Door created');
    }
    case 'adminToggle': { const d = doors.find((x) => x.id === a[0])!; d.locked = !d.locked; return ok({ locked: d.locked }, d.locked ? 'Locked' : 'Unlocked'); }
    case 'adminDelete': doors = doors.filter((x) => x.id !== a[0]); return ok(undefined, 'Deleted');
    case 'adminLog': return ok([{ citizenid: 'ABC123', action: 'unlock', detail: 'job', at: Math.floor(Date.now() / 1000) - 600 }, { citizenid: 'system', action: 'auto_lock', at: Math.floor(Date.now() / 1000) - 590 }]);
    case 'adminLookup': return a[0] === 7 ? ok({ citizenid: 'XYZ789', name: 'Ann Avery' }) : err('NOT_FOUND', 'No character with that server id is online');
    case 'manage': return ok(doorManage());
    case 'grant': return ok(undefined, 'Access given');
    case 'makeKey': return ok(undefined, 'Cut a key for Hayes Auto Office');
    case 'businessOpen': return ok({ businessOpen: a[1], locked: !a[1] }, a[1] ? 'Open: the door stays unlocked' : 'Closed and locked');
    default: return ok(undefined, 'Done (demo)');
  }
}
