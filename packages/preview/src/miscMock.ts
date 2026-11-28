// Preview-only fixtures for City Hall, Management, Emotes, Death screen, Dispatch and the MDT. Never shipped to FiveM.
import { devEmit, type NuiResponse } from '@veyl/ui';

const ok = <T,>(data?: T, message?: string): NuiResponse<T> => ({ ok: true, data, message });
const now = () => Math.floor(Date.now() / 1000);

export type MiscScreen = 'cityhall' | 'management' | 'emotes' | 'medical' | 'dispatch' | 'mdt';
export const MISC: MiscScreen[] = ['cityhall', 'management', 'emotes', 'medical', 'dispatch', 'mdt'];
export const isMisc = (s: string): s is MiscScreen => (MISC as string[]).includes(s);

// ---- City Hall
const cityhall = (empty: boolean) => ({
  person: { firstname: 'Alex', lastname: 'Morgan', birthdate: '1994-03-12', gender: 0, nationality: 'American', phone: '555-0142', citizenid: 'ABC12345', job: 'Los Santos Police', grade: 'Officer' },
  licences: empty ? [] : [
    { key: 'driver', label: "Driver's licence", description: 'Drive on public roads.', price: 500, held: true },
    { key: 'weapon', label: 'Weapons licence', description: 'Carry a licensed firearm. Background check required.', price: 5000, held: false },
    { key: 'boat', label: 'Boating licence', description: 'Operate boats and jet skis.', price: 800, held: false },
  ],
  documents: empty ? [] : [
    { key: 'id', label: 'Identity card', description: 'A replacement ID card.', price: 50, allowed: true },
    { key: 'birth', label: 'Birth certificate', description: 'An official copy.', price: 25, allowed: true },
    { key: 'record', label: 'Police record extract', description: 'Your own record, certified.', price: 100, requires: 'police', requiresLabel: 'Police only', allowed: false },
  ],
  jobs: empty ? [] : [
    { job: 'taxi', label: 'Downtown Cab Co.', description: 'Drive passengers around the city.', open: true, apply: 'Apply at the depot', locationLabel: 'Taxi HQ', hasLocation: true, grades: [{ grade: 0, name: 'Driver', pay: 120 }, { grade: 1, name: 'Dispatcher', pay: 180 }], member: false, current: false },
    { job: 'police', label: 'Los Santos Police', description: 'Serve and protect.', open: false, apply: 'Applications by invitation', hasLocation: false, grades: [{ grade: 0, name: 'Cadet', pay: 80 }, { grade: 1, name: 'Officer', pay: 150 }], member: true, current: true },
  ],
  methods: ['cash', 'bank'], balances: { cash: 420, bank: 12840 },
});

// ---- Management
const management = () => ({
  kind: 'job', name: 'police', label: 'Los Santos Police', myGrade: 4, offerSeconds: 60,
  grades: [{ grade: 0, name: 'Cadet', pay: 80, isboss: false }, { grade: 1, name: 'Officer', pay: 150, isboss: false }, { grade: 2, name: 'Sergeant', pay: 210, isboss: false }, { grade: 3, name: 'Lieutenant', pay: 260, isboss: false }, { grade: 4, name: 'Chief', pay: 340, isboss: true }],
  members: [
    { citizenid: 'A1', name: 'Alex Morgan', grade: 4, gradeName: 'Chief', online: true, onduty: true, primary: true, self: true, manageable: false },
    { citizenid: 'A2', name: 'Riley Park', grade: 3, gradeName: 'Lieutenant', online: true, onduty: true, primary: true, self: false, manageable: true },
    { citizenid: 'A3', name: 'Jamie Cole', grade: 2, gradeName: 'Sergeant', online: true, onduty: false, primary: true, self: false, manageable: true },
    { citizenid: 'A4', name: 'Casey Nguyen', grade: 1, gradeName: 'Officer', online: false, onduty: false, primary: false, self: false, manageable: true },
    { citizenid: 'A5', name: 'Dee Okafor', grade: 0, gradeName: 'Cadet', online: false, onduty: false, primary: true, self: false, manageable: true },
  ],
  nearby: [{ id: 14, distance: 2.1 }, { id: 22, distance: 3.4 }],
});

// ---- Emotes
const emotes = () => {
  const mk = (id: string, label: string, cat: string, extra: Partial<{ prop: boolean; shared: boolean; loop: boolean }> = {}) => ({ id, label, cat, prop: false, shared: false, loop: false, ...extra });
  return {
    categories: [{ id: 'dance', label: 'Dances' }, { id: 'gesture', label: 'Gestures' }, { id: 'sit', label: 'Sit and lean' }, { id: 'work', label: 'Work' }],
    emotes: [
      mk('wave', 'Wave', 'gesture'), mk('thumbsup', 'Thumbs up', 'gesture'), mk('facepalm', 'Facepalm', 'gesture'), mk('salute', 'Salute', 'gesture'), mk('shrug', 'Shrug', 'gesture'),
      mk('dance1', 'Dance: smooth', 'dance', { loop: true }), mk('dance2', 'Dance: party', 'dance', { loop: true }), mk('dance3', 'Dance: club', 'dance', { loop: true }), mk('handshake', 'Handshake', 'gesture', { shared: true }),
      mk('sit', 'Sit', 'sit', { loop: true }), mk('lean', 'Lean on wall', 'sit', { loop: true }), mk('chair', 'Sit on chair', 'sit', { loop: true }),
      mk('clipboard', 'Clipboard', 'work', { prop: true, loop: true }), mk('tablet', 'Tablet', 'work', { prop: true, loop: true }), mk('coffee', 'Drink coffee', 'work', { prop: true }), mk('hammer', 'Hammering', 'work', { prop: true, loop: true }),
    ],
    favourites: ['wave', 'dance1', 'sit'], current: null, command: 'e', maxFavourites: 6,
  };
};

// ---- Dispatch
const call = (id: number, code: string, title: string, street: string, priority: number, ago: number, extra: object = {}) => ({
  id, code, title, street, priority, x: 215, y: -810, z: 30, at: now() - ago, services: ['police'], responders: [], message: 'Caller reports shots fired near the parking lot.', distance: 340 + id * 120, ...extra,
});
const dispatch = () => ({
  service: 'police', serviceLabels: { police: 'Police', ems: 'EMS' },
  me: { id: 1, status: 'available' }, statuses: [{ id: 'available', label: 'Available' }, { id: 'busy', label: 'Busy' }, { id: 'enroute', label: 'En route' }, { id: 'off', label: 'Off duty' }],
  calls: [
    call(1, '10-71', 'Shots fired', 'Vinewood Boulevard', 1, 90, { panic: false }),
    call(2, '10-38', 'Traffic stop assistance', 'Alta Street', 2, 600, { responders: ['Riley Park'], message: 'Unit requests backup on a traffic stop.' }),
    call(3, '10-31', 'Suspicious person', 'Strawberry Avenue', 3, 2400, { message: 'Person looking into parked cars.' }),
  ],
  units: [
    { id: 1, service: 'police', name: 'Alex Morgan', grade: 'Chief', status: 'available' }, { id: 2, service: 'police', name: 'Riley Park', grade: 'Lieutenant', status: 'enroute' },
    { id: 3, service: 'police', name: 'Jamie Cole', grade: 'Sergeant', status: 'busy' },
  ],
});

// ---- MDT
const mdt = () => ({
  officer: 'Chief A. Morgan',
  warrants: [
    { id: 1, citizenid: 'X1', name: 'Marcus Webb', reason: 'Armed robbery, failure to appear', issued_by: 'Judge Hale', status: 'active', at: now() - 86400 },
    { id: 2, citizenid: 'X2', name: 'Tony Russo', reason: 'Vehicle theft', issued_by: 'Judge Hale', status: 'active', at: now() - 259200 },
  ],
  reports: [
    { id: 11, type: 'arrest', title: 'Arrest: Pillbox Hill bank', author_name: 'R. Park', role: 'officer', at: now() - 7200 },
    { id: 12, type: 'incident', title: 'Noise complaint, Starlite Motel', author_name: 'J. Cole', role: 'officer', at: now() - 40000 },
    { id: 13, type: 'traffic', title: 'Speeding, Great Ocean Highway', author_name: 'A. Morgan', role: 'officer', at: now() - 90000 },
  ],
  flagged: [{ plate: 'WTP 0193', stolen: 1, bolo: 0, notes: 'Reported stolen outside Legion Square' }, { plate: 'KFR 8820', stolen: 0, bolo: 1, notes: 'Suspect vehicle, armed' }],
  charges: [
    { id: 'c1', label: 'Speeding', category: 'Traffic', fine: 250, months: 0 }, { id: 'c2', label: 'Reckless driving', category: 'Traffic', fine: 600, months: 0 },
    { id: 'c3', label: 'Vehicle theft', category: 'Property', fine: 2500, months: 8 }, { id: 'c4', label: 'Armed robbery', category: 'Violent', fine: 9000, months: 24 },
  ],
  roster: [{ id: 1, name: 'Alex Morgan', grade: 'Chief', status: 'available' }, { id: 2, name: 'Riley Park', grade: 'Lieutenant', status: 'enroute' }],
  canLicence: true,
});

export function miscOpen(screen: MiscScreen, empty: boolean) {
  switch (screen) {
    case 'cityhall': devEmit('cityhall:open', cityhall(empty)); break;
    case 'management': devEmit('management:open', management()); break;
    case 'emotes': devEmit('emotes:open', emotes()); break;
    case 'dispatch': devEmit('dispatch:open', dispatch()); break;
    case 'mdt': devEmit('mdt:open', mdt()); break;
    case 'medical': devEmit('medical:state', { visible: true, state: 'down', remainingMs: 252000, totalMs: 300000, callMs: 0, ems: 2, alerted: 2, fee: 750, hospital: 'Pillbox Hill Medical' }); break;
  }
}

/** Demo extras: the preview buttons for these screens. */
export function miscDemo(screen: MiscScreen, what: string) {
  if (screen === 'dispatch' && what === 'alert') devEmit('dispatch:alert', { call: call(9, '10-90', 'Bank alarm', 'Pillbox Hill', 1, 5), seconds: 12, respondKey: 'E' });
  if (screen === 'medical' && what === 'dead') devEmit('medical:state', { visible: true, state: 'dead', remainingMs: 0, totalMs: 300000, helpedMs: 0, ems: 0, alerted: 0, fee: 750, hospital: 'Pillbox Hill Medical', respawning: false });
  if (screen === 'medical' && what === 'down') miscOpen('medical', false);
}

export function miscHandler(screen: MiscScreen, action: string, payload: Record<string, unknown>): NuiResponse {
  if (action === 'ui:ready' || action === 'ui:typing' || action === 'waypoint' || action === 'play' || action === 'stop' || action === 'favourite') return ok();
  if (action === 'close') { devEmit(`${screen}:close`); return ok(); }
  if (action === 'status') { const d = dispatch(); d.me.status = String(payload.status); return ok(d); }
  if (action === 'api') {
    const p = payload as { name: string; args: unknown[] };
    if (screen === 'mdt' && p.name === 'dashboard') return ok(mdt());
    if (screen === 'cityhall' || screen === 'management') return ok(undefined, 'Done (demo)');
    return { ok: false, code: 'NOT_IMPLEMENTED', message: `No demo data for ${p.name}` };
  }
  return { ok: false, code: 'NOT_IMPLEMENTED', message: `No demo handler for ${action}` };
}
