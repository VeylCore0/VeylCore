// Preview-only backend for the boosting tablet. Same callback names and shapes as veyl_boosting's server (server/main.lua);
// never shipped to FiveM. It keeps just enough state to click through every screen.
import { devEmit, type NuiResponse } from '@veyl/ui';

const now = () => Math.floor(Date.now() / 1000);
const ok = <T,>(data?: T, message?: string): NuiResponse<T> => ({ ok: true, data, message });
const err = (code: string, message: string): NuiResponse<never> => ({ ok: false, code, message });

type Veh = { model: string; label: string; tier: 'standard' | 'premium' | 'luxury'; difficulty: number; baseReward: number; minRep: number; solo: boolean; group: boolean };
const CAT: Veh[] = [
  { model: 'blista', label: 'Blista', tier: 'standard', difficulty: 1, baseReward: 1000, minRep: 0, solo: true, group: true },
  { model: 'sultan', label: 'Sultan', tier: 'standard', difficulty: 2, baseReward: 2000, minRep: 100, solo: true, group: true },
  { model: 'buffalo', label: 'Buffalo', tier: 'standard', difficulty: 2, baseReward: 2300, minRep: 100, solo: true, group: true },
  { model: 'comet2', label: 'Comet', tier: 'premium', difficulty: 3, baseReward: 4200, minRep: 300, solo: true, group: true },
  { model: 'banshee', label: 'Banshee', tier: 'premium', difficulty: 3, baseReward: 4600, minRep: 300, solo: true, group: true },
  { model: 'jester', label: 'Jester', tier: 'premium', difficulty: 4, baseReward: 6200, minRep: 700, solo: true, group: true },
  { model: 'specter', label: 'Specter', tier: 'luxury', difficulty: 4, baseReward: 8000, minRep: 700, solo: true, group: true },
  { model: 'zentorno', label: 'Zentorno', tier: 'luxury', difficulty: 5, baseReward: 11000, minRep: 1500, solo: true, group: true },
  { model: 'adder', label: 'Adder', tier: 'luxury', difficulty: 5, baseReward: 13000, minRep: 1500, solo: false, group: true },
];
const RANKS = [
  { id: 'rookie', label: 'Rookie', rep: 0 }, { id: 'runner', label: 'Runner', rep: 100, perk: 'Premium contracts' },
  { id: 'operator', label: 'Operator', rep: 300, perk: 'High-risk contracts and group operations' }, { id: 'specialist', label: 'Specialist', rep: 700, perk: 'Event contracts and fast-lane luxury vehicles' },
  { id: 'elite', label: 'Elite', rep: 1500, perk: 'Hypercar contracts' }, { id: 'executive', label: 'Executive', rep: 3000, perk: 'All contracts and the best payouts' },
];
const LEVELS = [
  { id: 'LOW', max: 25, label: 'Low', color: '#34d27b', rewardMult: 1 }, { id: 'MEDIUM', max: 50, label: 'Medium', color: '#f2b443', rewardMult: 1.05 },
  { id: 'HIGH', max: 75, label: 'High', color: '#ef7a3a', rewardMult: 1.12 }, { id: 'EXTREME', max: 100, label: 'Extreme', color: '#e0576a', rewardMult: 1.2 },
];
const TEMPLATES = [
  { template: 'standard_recovery', label: 'Vehicle Recovery', badge: 'STANDARD', description: 'Recover the target vehicle and bring it to the handoff zone.', difficulty: 1, mode: 'both', crew: { min: 1, max: 2 }, vehicles: 1, timeLimit: 30, tracked: false, minRep: 0, minRank: 'Rookie', repReward: 25, risk: 0.15, mult: [0.9, 1.4], model: 'sultan' },
  { template: 'premium_recovery', label: 'Premium Recovery', badge: 'PREMIUM', description: 'Recover a high-value vehicle. More attention, better money.', difficulty: 3, mode: 'both', crew: { min: 1, max: 3 }, vehicles: 1, timeLimit: 45, tracked: false, minRep: 100, minRank: 'Runner', repReward: 45, risk: 0.35, mult: [1, 1.5], model: 'comet2' },
  { template: 'high_risk', label: 'High-Risk Recovery', badge: 'HIGH RISK', description: 'A challenging contract for experienced operators. The vehicle carries a tracker.', difficulty: 5, mode: 'both', crew: { min: 1, max: 4 }, vehicles: 1, timeLimit: 60, tracked: true, minRep: 300, minRank: 'Operator', repReward: 80, risk: 0.6, mult: [1.1, 1.7], model: 'specter' },
  { template: 'timed_delivery', label: 'Timed Delivery', badge: 'TIMED', description: 'The buyer will not wait. Deliver before the clock runs out for a bonus.', difficulty: 2, mode: 'solo', crew: { min: 1, max: 1 }, vehicles: 1, timeLimit: 20, tracked: false, minRep: 100, minRank: 'Runner', repReward: 40, risk: 0.25, mult: [1.2, 1.7], model: 'buffalo' },
  { template: 'group_operation', label: 'Group Operation', badge: 'CREW', description: 'Several vehicles, one buyer. Bring a crew and deliver them all.', difficulty: 4, mode: 'group', crew: { min: 2, max: 4 }, vehicles: 2, timeLimit: 60, tracked: false, minRep: 300, minRank: 'Operator', repReward: 95, risk: 0.5, mult: [1, 1.4], model: 'banshee' },
  { template: 'special_event', label: 'Special Event Contract', badge: 'EVENT', description: 'A limited-time contract that only exists while an event is running.', difficulty: 5, mode: 'both', crew: { min: 1, max: 4 }, vehicles: 1, timeLimit: 60, tracked: true, minRep: 700, minRank: 'Specialist', repReward: 150, risk: 0.7, mult: [1.8, 2.6], model: 'jester' },
];

type Active = { id: string; template: string; state: string; startedAt?: number; expiresAt?: number; reserveUntil: number; acquired: number; delivered: number; vehicles: number; model: string; reward: number; tracked: boolean; trackerOff: boolean; label: string; badge: string; description: string; difficulty: number; repReward: number; timeLimit: number };
let rep = 340, completed = 12, failed = 3, earnings = 68400, heat = 18;
let active: Active | null = null;
let crew: { leader: boolean; members: { id: string; name: string; leader: boolean; online: boolean; me: boolean }[]; log: { at: number; text: string }[] } | null = null;
let invite: { from: string; seconds: number } | null = null;
let recent = [
  { kind: 'complete', text: 'Contract Completed: Vehicle Recovery', detail: '+$4,200 | +25 Rep', at: now() - 140 },
  { kind: 'rank', text: 'Rank up: now Operator', detail: 'Operator', at: now() - 300 },
  { kind: 'contract', text: 'Contract accepted: Premium Recovery', detail: 'Comet', at: now() - 600 },
];
let offersAt = now();
let challengeDone = false;

const rankFor = () => { let i = 0; RANKS.forEach((r, n) => { if (rep >= r.rep) i = n; }); return i; };
const levelFor = () => LEVELS.find((l) => heat <= l.max) ?? LEVELS[3];

function offers() {
  const i = rankFor();
  return TEMPLATES.map((t) => {
    const v = CAT.find((x) => x.model === t.model) as Veh;
    let locked: string | null = null;
    if (t.template === 'special_event') locked = 'No event running';
    else if (rep < t.minRep) locked = `Requires ${t.minRep} reputation`;
    else if (active) locked = null;
    const base = v.baseReward * t.vehicles;
    return { id: `offer-${t.template}`, template: t.template, label: t.label, badge: t.badge, description: t.description, difficulty: t.difficulty, model: v.model, vehicleLabel: v.label, tier: v.tier,
      mode: t.mode, crew: t.crew, vehicles: t.vehicles, timeLimit: t.timeLimit, tracked: t.tracked, minRep: t.minRep, minRank: t.minRank,
      rewardMin: Math.floor(base * t.mult[0] * levelFor().rewardMult), rewardMax: Math.floor(base * t.mult[1] * levelFor().rewardMult), repReward: t.repReward, risk: t.risk, locked: i < 0 ? null : locked };
  });
}

function activeView() {
  if (!active) return null;
  const a = active;
  const veh = CAT.find((x) => x.model === a.model) as Veh;
  const vehicles = Array.from({ length: a.vehicles }, (_, i) => ({ index: i + 1, model: i === 0 ? a.model : 'banshee', label: i === 0 ? veh.label : 'Banshee', tier: veh.tier, status: i < a.delivered ? 'delivered' : i < a.acquired ? 'acquired' : 'waiting', netId: 100 + i }));
  const members = crew ? crew.members : [{ id: 'me', name: 'Alex Morgan', leader: true, online: true, me: true }];
  return { id: a.id, template: a.template, label: a.label, badge: a.badge, description: a.description, state: a.state, difficulty: a.difficulty, leader: true, vehicles, acquired: a.acquired,
    members, tracked: a.tracked && !a.trackerOff, trackerOff: a.trackerOff, reward: a.reward, repReward: a.repReward, createdAt: now() - 60, startedAt: a.startedAt, expiresAt: a.expiresAt, reserveUntil: a.reserveUntil,
    area: a.state !== 'reserved' ? { x: 215, y: -810, r: 160 } : undefined,
    drop: a.acquired > 0 ? { label: 'East Los Santos lot', x: 1017, y: -2528, z: 28, radius: 9 } : undefined,
    canStart: a.state === 'reserved', canCancel: true, needsCrew: a.template === 'group_operation', timeLimit: a.timeLimit, serverTime: now() };
}

export function boostState() {
  const i = rankFor();
  const r = RANKS[i], nx = RANKS[i + 1];
  const l = levelFor();
  const total = completed + failed;
  return {
    player: { name: 'Alex Morgan', rank: r.label, rankIndex: i + 1, rep, nextRank: nx?.label, nextRep: nx?.rep, rankFloor: r.rep, progress: nx ? (rep - r.rep) / (nx.rep - r.rep) : 1 },
    heat: { value: Math.round(heat), max: 100, level: l.id, label: l.label, color: l.color, rewardMult: l.rewardMult, levels: LEVELS, decay: 3, police: true },
    active: activeView(), offers: offers(), offersAt, offersTTL: 1200,
    catalogue: CAT.map((v) => ({ ...v, unlocked: rep >= v.minRep })), ranks: RANKS.map((x, n) => ({ ...x, current: n === i, reached: n <= i })),
    tiers: { standard: { label: 'Standard', color: '#3f8bff' }, premium: { label: 'Premium', color: '#8b5fd6' }, luxury: { label: 'Luxury', color: '#e8a33a' } },
    stats: { completed, failed, rate: total ? completed / total : 0, earnings, best: 612, rep },
    challenges: [
      { id: 'daily_complete', kind: 'daily', label: 'Complete 1 Contract', goal: 1, reward: 10000, progress: challengeDone ? 1 : 0, done: challengeDone },
      { id: 'daily_earn', kind: 'daily', label: 'Earn $12,000', goal: 12000, reward: 5000, progress: 4200, done: false },
      { id: 'weekly_complete', kind: 'weekly', label: 'Complete 8 Contracts', goal: 8, reward: 45000, progress: 5, done: false },
    ],
    recent, crew: crew ? { id: 'crew1', leader: true, members: crew.members, max: 4, log: crew.log, locked: !!active && active.state !== 'reserved' } : null, invite,
    event: false, ui: { Brand: 'VEYL BOOSTING', Tagline: 'Become the ultimate operator', Accent: '#8b5fd6', Accent2: '#3f8bff', Currency: '$' }, crewMax: 4, serverTime: now(), dropRadius: 9, blips: {},
  };
}

// ---- the puzzle ------------------------------------------------------------------------------------------------------
let stage = 1, strikes = 0, seq: number[] = [];
const newStage = () => {
  seq = Array.from({ length: 3 + stage - 1 }, () => 1 + Math.floor(Math.random() * 6));
  return { stage, stages: 2, strikes, maxStrikes: 3, seq, showMs: 550 * seq.length, maxInputMs: 14000, glyphs: 6, token: `tok-${stage}-${strikes}` };
};
export const boostMinigame = () => { stage = 1; strikes = 0; return newStage(); };

// ---- callbacks -----------------------------------------------------------------------------------------------------
export function boostApi(name: string, a: unknown[]): NuiResponse | undefined {
  switch (name) {
    case 'state': return ok(boostState());
    case 'sync': return ok(activeView());
    case 'refreshOffers': offersAt = now(); return ok(boostState(), 'Contracts refreshed');
    case 'accept': {
      const o = offers().find((x) => x.id === a[0]);
      if (!o) return err('NOT_FOUND', 'That contract is no longer on offer');
      if (active) return err('INVALID_STATE', 'Finish your current contract first');
      if (o.locked) return err('UNAVAILABLE', o.locked);
      const t = TEMPLATES.find((x) => x.template === o.template)!;
      const solo = t.mode !== 'group' && (!crew || crew.members.length === 1);
      if (t.mode === 'group' && (!crew || crew.members.length < 2)) return err('INVALID_STATE', `This contract needs a crew of ${t.crew.min} or more`);
      active = { id: 'BCDEMO', template: t.template, state: solo ? 'active' : 'reserved', startedAt: solo ? now() : undefined, expiresAt: solo ? now() + t.timeLimit * 60 : undefined, reserveUntil: now() + 600,
        acquired: 0, delivered: 0, vehicles: t.vehicles, model: o.model as string, reward: Math.round((o.rewardMin + o.rewardMax) / 2), tracked: t.tracked, trackerOff: false, label: t.label, badge: t.badge, description: t.description,
        difficulty: t.difficulty, repReward: t.repReward, timeLimit: t.timeLimit };
      return ok({ id: 'BCDEMO' }, solo ? 'Contract started: find the vehicle in the marked area.' : 'Contract reserved');
    }
    case 'startContract': {
      if (!active || active.state !== 'reserved') return err('INVALID_STATE', 'The contract cannot be started');
      const t = TEMPLATES.find((x) => x.template === active!.template)!;
      active.state = 'active'; active.startedAt = now(); active.expiresAt = now() + t.timeLimit * 60;
      return ok({ id: active.id }, 'Contract started');
    }
    case 'cancelContract': if (!active) return err('NOT_FOUND', 'You have no contract'); active = null; return ok(undefined, 'Contract dropped');
    case 'accessBegin': return ok(boostMinigame());
    case 'accessSubmit': {
      const answer = a[1] as number[];
      const right = Array.isArray(answer) && answer.length === seq.length && answer.every((g, i) => g === seq[i]);
      if (!right) { strikes++; if (strikes >= 3) return ok({ result: 'failed' }, 'The signal dropped'); return ok({ result: 'retry', stage: newStage() }); }
      stage++;
      if (stage > 2) {
        if (active) { active.acquired = Math.min(active.vehicles, active.acquired + 1); active.state = 'vehicle_acquired'; }
        return ok({ result: 'success' }, 'Vehicle unlocked');
      }
      return ok({ result: 'next', stage: newStage() });
    }
    case 'accessAbort': return ok();
    case 'deliver': {
      if (!active) return err('INVALID_STATE', 'Nothing to hand over yet');
      active.delivered++;
      if (active.delivered >= active.vehicles) { rep += active.repReward; completed++; earnings += active.reward; challengeDone = true; recent = [{ kind: 'complete', text: `Contract Completed: ${active.label}`, detail: `+$${active.reward} | +${active.repReward} Rep`, at: now() }, ...recent]; active = null; return ok({ payout: 0 }, 'Delivered.'); }
      return ok({ remaining: 1 }, 'Delivered. 1 more to go.');
    }
    case 'crewNearby': return ok([{ id: 14, name: 'Jamie Cole' }, { id: 22, name: 'Riley Park' }].filter((n) => !crew || !crew.members.some((m) => m.name === n.name)));
    case 'crewInvite': {
      const n = a[0] === 14 ? 'Jamie Cole' : 'Riley Park';
      crew = crew ?? { leader: true, members: [{ id: 'me', name: 'Alex Morgan', leader: true, online: true, me: true }], log: [] };
      crew.members.push({ id: `c${a[0]}`, name: n, leader: false, online: true, me: false });
      crew.log.unshift({ at: now(), text: `${n} joined` });
      return ok(undefined, `Invite sent to ${n}`);
    }
    case 'crewAnswer': invite = null; return ok(undefined, a[0] ? 'You joined the crew' : 'Declined');
    case 'crewLeave': crew = null; return ok(undefined, 'You left the crew');
    case 'crewKick': if (crew) { crew.members = crew.members.filter((m) => m.id !== a[0]); if (crew.members.length < 2) crew = null; } return ok(undefined, 'Member removed');
    case 'crewLead': return ok(undefined, 'Leadership transferred');
  }
  return undefined;
}

/** Test hooks for the preview toolbar and Playwright. */
export const boostDemo = {
  reset() { rep = 340; heat = 18; active = null; crew = null; invite = null; challengeDone = false; completed = 12; failed = 3; earnings = 68400; },
  hot() { heat = 82; },
  invite() { invite = { from: 'Casey Nguyen', seconds: 40 }; },
  open() { devEmit('boosting:open', boostState()); },
  openActive() { if (!active) boostApi('accept', ['offer-standard_recovery']); devEmit('boosting:open', boostState()); },
  openGame() { devEmit('boosting:minigame', boostMinigame()); },
  emptyState() { rep = 0; completed = 0; failed = 0; earnings = 0; heat = 0; recent = []; },
};
