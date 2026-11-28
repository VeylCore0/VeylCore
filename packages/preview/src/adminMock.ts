// Preview-only backend for the staff menu. Same callback names and shapes as veyl_admin's server/menu.lua; never shipped to FiveM.
import { devEmit, type NuiResponse } from '@veyl/ui';

const ok = <T,>(data?: T, message?: string): NuiResponse<T> => ({ ok: true, data, message });
const err = (code: string, message: string): NuiResponse<never> => ({ ok: false, code, message });

const PLAYERS = [
  { id: 1, name: 'MoosyMoose2', character: 'Alex Carter', citizenid: 'ABC12345', ping: 24, job: 'Police', staff: true },
  { id: 4, name: 'nightowl', character: 'Mia Torres', citizenid: 'XYZ98765', ping: 71, job: 'Unemployed', staff: false },
  { id: 7, name: 'driftking', character: 'Jonas Reed', citizenid: 'QWE45612', ping: 168, job: 'Mechanic', staff: false },
];
const state = { self: { noclip: false, god: false, invisible: false, names: false, spectating: false, speed: 3 }, banned: [] as number[], reports: [
  { id: 12, name: 'nightowl', message: 'Someone is shooting at spawn, please help', status: 'open', at: '2026-11-28 02:10' },
  { id: 11, name: 'driftking', message: 'Lost my car after a restart', status: 'closed', handler: 'MoosyMoose2', at: '2026-11-27 21:44' },
] };

const overview = () => ({ players: PLAYERS.length, inCity: 3, max: 48, uptime: 13520, resources: 61, reports: state.reports.filter((r) => r.status === 'open').length, bans: 1,
  world: { hour: 14, minute: 30, weather: 'CLEAR', frozen: false }, me: { id: 1, name: 'MoosyMoose2' },
  weather: ['EXTRASUNNY', 'CLEAR', 'CLOUDS', 'OVERCAST', 'RAIN', 'THUNDER', 'FOGGY', 'SNOW'],
  jobs: [{ id: 'police', label: 'Police' }, { id: 'ambulance', label: 'EMS' }, { id: 'mechanic', label: 'Mechanic' }, { id: 'unemployed', label: 'Unemployed' }],
  gangs: [{ id: 'none', label: 'None' }, { id: 'ballas', label: 'Ballas' }] });

export const adminApi = (name: string, args: unknown[]): NuiResponse | undefined => {
  switch (name) {
    case 'overview': return ok(overview());
    case 'players': return ok(PLAYERS);
    case 'playerInfo': {
      const p = PLAYERS.find((x) => x.id === args[0]);
      if (!p) return err('NOT_FOUND', 'That player is not online');
      return ok({ ...p, identifiers: { license: 'license:7f3a91c2e1d04b8a9c5d', discord: 'discord:593209615047720974', fivem: 'fivem:7395833' },
        money: { cash: 1240, bank: 58200, crypto: 0 }, job: { label: p.job }, gang: { label: 'None' }, coords: { x: 215.3, y: -810.1, z: 30.7 }, health: 200, armor: 25,
        items: [{ name: 'lockpick', label: 'Lockpick', count: 2 }, { name: 'phone', label: 'Phone', count: 1 }, { name: 'weapon_pistol', label: 'Pistol', count: 1 }],
        warnings: [{ id: 1, reason: 'Fail RP in the bank', issued_by: 'MoosyMoose2', at: '2026-11-20 18:02' }] });
    }
    case 'action': {
      const [kind] = args as [string];
      const msgs: Record<string, string> = { teleport: 'Teleported to them', bring: 'Brought them', spectate: 'Spectating', freeze: 'Froze them', revive: 'Revived', heal: 'Healed', kill: 'Killed', message: 'Message sent', warn: 'Warning recorded', kick: 'Kicked', ban: 'Banned', money: 'New cash balance: $2,240', job: 'Job set', gang: 'Gang set', giveitem: 'Gave the item', takeitem: 'Took the item' };
      return msgs[kind] ? ok(undefined, msgs[kind]) : err('INVALID_INPUT', 'Unknown action or player');
    }
    case 'reports': return ok(state.reports);
    case 'closeReport': { const r = state.reports.find((x) => x.id === args[0]); if (r) { r.status = 'closed'; (r as { handler?: string }).handler = 'MoosyMoose2'; } return ok(undefined, 'Report closed'); }
    case 'bans': return ok([{ id: 3, name: 'cheater99', reason: 'Modding', bannedBy: 'MoosyMoose2', at: '2026-11-25 20:00', expires: null }]);
    case 'unban': return ok(undefined, 'Unbanned');
    case 'logs': return ok(Array.from({ length: 8 }, (_, i) => ({ id: i, resource: i % 2 ? 'veyl_admin' : 'veyl_core', action: i % 2 ? 'admin_money' : 'money_credit', citizenid: 'ABC12345', data: '{"kind":"cash","amount":500}', at: `11-28 02:${10 + i}:00` })));
    case 'announce': return ok(undefined, 'Sent to everyone');
    case 'world': return ok(undefined, 'Done');
    case 'resources': return ok([{ name: 'veyl_admin', state: 'started', locked: true }, { name: 'veyl_phone', state: 'started', locked: false }, { name: 'veyl_heists', state: 'stopped', locked: false }]);
    case 'resource': return ok(undefined, 'Done');
    case 'itemList': return ok([{ name: 'lockpick', label: 'Lockpick' }, { name: 'weapon_pistol', label: 'Pistol' }]);
    default: return undefined;
  }
};

export const adminTool = (kind: string, value: unknown): NuiResponse => {
  const s = state.self;
  if (kind === 'noclip') { s.noclip = !s.noclip; devEmit('admin:close'); }
  else if (kind === 'god') s.god = !s.god;
  else if (kind === 'invisible') s.invisible = !s.invisible;
  else if (kind === 'names') s.names = !s.names;
  else if (kind === 'speed') s.speed = Number(value);
  return { ok: true, message: ({ god: s.god ? 'God mode on' : 'God mode off', invisible: s.invisible ? 'You are invisible' : 'You are visible', names: s.names ? 'Names on' : 'Names off', heal: 'Healed', armor: 'Armour full', spawn: `Spawned ${value}`, fix: 'Vehicle repaired', clean: 'Vehicle cleaned', flip: 'Vehicle flipped upright', delete: 'Vehicle deleted', tpm: 'Teleporting' } as Record<string, string | undefined>)[kind], data: { state: { ...s } } };
};

export const adminDemo = { open() { state.self.noclip = false; devEmit('admin:open', { overview: overview(), self: { ...state.self }, vehicles: ['adder', 'zentorno', 'sultan', 'police'], speeds: [0.25, 0.5, 1, 2, 4, 8] }); } };
