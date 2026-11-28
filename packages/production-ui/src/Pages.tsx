import { useState } from 'react';
import type { Ctx } from './ctx';
import { BenchPanel } from './Bench';
import { Bar, Button, Chip, Empty, Ico, ItemImg, Ring, Tile, ago, cx, usd } from './ui';

const greeting = () => { const h = new Date().getHours(); return h < 5 ? 'Still up' : h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening'; };

export function Dashboard({ c }: { c: Ctx }) {
  const { s } = c;
  const rep = s.progress.reputation;
  const bot = s.progress.branches.botanical;
  const growing = s.plants.filter((p) => p.state === 'growing').length;
  const ready = s.plants.filter((p) => p.state === 'ready');
  const thirsty = s.plants.filter((p) => p.state === 'growing' && (p.water < 25 || p.nutrient < 25));
  const queued = s.workstations.reduce((n, b) => n + b.batches.length, 0);
  const now = s.serverTime;
  const done = s.workstations.reduce((n, b) => n + b.batches.filter((x) => x.endsAt <= now).length, 0);
  const owned = s.properties.properties.filter((p) => p.role === 'owner');
  const attention: { icon: string; color: string; text: string; go: () => void; label: string }[] = [
    ...ready.map((p) => ({ icon: 'leaf', color: '#5fd68c', text: `${p.label} is ready to harvest`, go: () => c.go('botanical'), label: 'View' })),
    ...thirsty.map((p) => ({ icon: 'drop', color: '#4aa8ff', text: `${p.label} needs ${p.water < 25 ? 'water' : 'feeding'}`, go: () => c.go('botanical'), label: 'View' })),
    ...(done > 0 ? [{ icon: 'gear', color: '#c58bff', text: `${done} batch${done > 1 ? 'es are' : ' is'} ready to collect`, go: () => c.go('production'), label: 'View' }] : []),
  ];
  return (
    <div className="pr-page">
      <section className="pr-banner">
        <div className="pr-banner-text">
          <small>{greeting().toUpperCase()}</small>
          <h2>{s.player.name}</h2>
          <p>{attention.length > 0 ? `${attention.length} thing${attention.length > 1 ? 's' : ''} need${attention.length > 1 ? '' : 's'} you.` : 'All quiet. Your plants and benches are on track.'}</p>
          <div className="pr-quick">
            <Button kind="primary" onClick={() => c.go('botanical')}><Ico name="leaf" size={16} />Botanical</Button>
            {s.branches.field?.enabled && <Button onClick={() => c.go('field')}><Ico name="pin" size={16} />Field</Button>}
            {s.branches.supplier?.enabled && <Button onClick={() => c.go('supplier')}><Ico name="bag" size={16} />Supplier</Button>}
            <Button onClick={() => c.go('production')}><Ico name="gear" size={16} />Production</Button>
            <Button onClick={() => c.go('properties')}><Ico name="home" size={16} />Properties</Button>
          </div>
        </div>
        <div className="pr-banner-rep">
          <Ring value={rep.next ? (rep.xp - rep.floor) / (rep.next - rep.floor) : 1} size={104} stroke={8}><b>{rep.level}</b><i>LEVEL</i></Ring>
          <strong>{rep.name}</strong>
          <em>{rep.xp.toLocaleString()} XP{rep.next ? ` · ${(rep.next - rep.xp).toLocaleString()} to go` : ''}</em>
        </div>
      </section>

      <div className="pr-tiles">
        <section className="pr-tilecard"><Tile icon="leaf" color="#5fd68c" /><div><strong>{growing}</strong><span>Plants growing</span></div>{ready.length > 0 && <Chip tone="ok">{ready.length} ready</Chip>}</section>
        <section className="pr-tilecard"><Tile icon="gear" color="#c58bff" /><div><strong>{queued}</strong><span>Batches queued</span></div>{done > 0 && <Chip tone="ok">{done} done</Chip>}</section>
        <section className="pr-tilecard"><Tile icon="home" color="#4aa8ff" /><div><strong>{owned.length}</strong><span>Laboratories</span></div></section>
      </div>

      <div className="pr-twocol">
        <section className="pr-card">
          <h4 className="pr-h">NEEDS ATTENTION</h4>
          {attention.length === 0 ? <div className="pr-allgood"><Ico name="check" size={18} />You are all caught up</div> : (
            <ul className="pr-attn">{attention.map((a, i) => <li key={i}><Tile icon={a.icon} color={a.color} size={34} /><span>{a.text}</span><Button kind="ghost" onClick={a.go}>{a.label}</Button></li>)}</ul>
          )}
          <h4 className="pr-h" style={{ marginTop: 6 }}>BRANCHES</h4>
          {Object.entries(s.progress.branches).map(([id, b]) => (
            <div key={id} className="pr-branch">
              <Ring value={b.progress} size={52} stroke={5} color={b.color}><b className="sm">{b.level}</b></Ring>
              <div className="pr-grow"><strong>{b.label} · {b.levelName}</strong><em>{b.xp.toLocaleString()} XP{b.nextXp ? ` · ${b.nextXp.toLocaleString()} for level ${b.level + 1}` : ''}</em></div>
            </div>
          ))}
          {s.exposure > 0 && <p className="pr-note warn"><Ico name="info" size={14} />Fumes exposure at {s.exposure}%. Step away from the bench to recover.</p>}
        </section>
        <section className="pr-card">
          <h4 className="pr-h">RECENT ACTIVITY</h4>
          {s.recent.length === 0 ? <p className="pr-mute">Nothing yet. Gather something or visit the supplier.</p> : (
            <ul className="pr-timeline">{s.recent.map((r, i) => <li key={i} className={r.kind}><i /><span>{r.text}</span><time>{ago(r.at, s.serverTime)}</time></li>)}</ul>
          )}
        </section>
      </div>
    </div>
  );
}

const STATE_TONE = { ready: 'ok', dead: 'bad', growing: 'accent' } as const;

const BRANCH_COPY: Record<string, { title: string; blurb: string; gather: string; empty: string }> = {
  botanical: { title: 'Botanical', blurb: 'Grow, gather and prepare. Tend plants by walking up to them.', gather: 'Gathering', empty: 'Buy seeds and a planter at the supplier, then use the seeds from your inventory.' },
  field: { title: 'Field Operations', blurb: 'Work the wild ground: search the field zones, plant what you find and tend it away from town.', gather: 'Field zones', empty: 'Search a field zone for seeds, or buy them at the outfitter, then use them from your inventory.' },
};

export function Botanical({ c, branch = 'botanical' }: { c: Ctx; branch?: 'botanical' | 'field' }) {
  const s0 = c.s;
  const copy = BRANCH_COPY[branch];
  const vs = s0.varieties.filter((v) => v.branch === branch);
  const s = { ...s0, varieties: vs, plants: s0.plants.filter((p) => vs.some((v) => v.key === p.variety)), gathering: s0.gathering.filter((g) => g.branch === branch) };
  const [tab, setTab] = useState<'plants' | 'varieties' | 'gathering'>('plants');
  return (
    <div className="pr-page">
      <div className="pr-page-head"><div><h2>{copy.title}</h2><p>{copy.blurb}</p></div></div>
      <div className="pr-tabs" role="tablist">
        {(['plants', 'varieties', 'gathering'] as const).map((t) => <button key={t} role="tab" aria-selected={tab === t} className={cx(tab === t && 'on')} onClick={() => setTab(t)}>{t === 'plants' ? `Plants (${s.plants.length})` : t === 'varieties' ? 'Varieties' : copy.gather}</button>)}
      </div>
      {tab === 'plants' && (s.plants.length === 0 ? <Empty icon="leaf" title="No plants yet" text={copy.empty} /> : (
        <div className="pr-plants">
          {s.plants.map((p) => {
            const v = s.varieties.find((x) => x.key === p.variety);
            return (
              <article key={p.id} className={cx('pr-plant', p.state)}>
                <div className="pr-plant-top">
                  <Ring value={p.growth} size={64} stroke={6} color={p.state === 'dead' ? '#e0576a' : p.state === 'ready' ? '#5fd68c' : '#7bd88f'}>{v ? <ItemImg item={v.seed} size={34} /> : <Ico name="leaf" />}</Ring>
                  <div className="pr-grow"><strong>{p.label}</strong><span className="pr-sub">{p.property ? 'In a laboratory' : 'Outdoors'} · {Math.round(p.growth * 100)}% grown</span></div>
                  <Chip tone={STATE_TONE[p.state]}>{p.state === 'ready' ? 'Ready' : p.state === 'dead' ? 'Dead' : `${p.minutesLeft} min`}</Chip>
                </div>
                <div className="pr-meters">
                  <label><Ico name="drop" size={13} />Water<Bar value={p.water / 100} color={p.water < 25 ? '#e0576a' : '#4aa8ff'} label="Water" /><b>{p.water}</b></label>
                  <label><Ico name="leaf" size={13} />Nutrients<Bar value={p.nutrient / 100} color={p.nutrient < 25 ? '#e0576a' : '#7bd88f'} label="Nutrients" /><b>{p.nutrient}</b></label>
                  <label><Ico name="shield" size={13} />Health<Bar value={p.health / 100} color={p.health < 40 ? '#e0576a' : '#c58bff'} label="Health" /><b>{p.health}</b></label>
                </div>
                {!p.property && <Button kind="ghost" onClick={() => c.waypoint(p.x, p.y)}><Ico name="pin" size={14} />Set GPS</Button>}
              </article>
            );
          })}
        </div>
      ))}
      {tab === 'varieties' && (
        <div className="pr-varieties">
          {s.varieties.map((v) => (
            <article key={v.key} className={cx('pr-variety', v.locked && 'locked', v.rarity.toLowerCase())}>
              <div className="pr-variety-art"><ItemImg item={v.seed} size={64} />{v.locked && <span className="pr-lockbadge"><Ico name="lock" size={16} />Level {v.level}</span>}</div>
              <strong>{v.label}</strong>
              <Chip tone={v.rarity === 'Rare' ? 'warn' : v.rarity === 'Uncommon' ? 'accent' : 'mute'}>{v.rarity}</Chip>
              <div className="pr-spec"><span><Ico name="clock" size={13} />{v.growMinutes} min</span><span><Ico name="leaf" size={13} />{v.yield[0]}–{v.yield[1]} yield</span></div>
            </article>
          ))}
        </div>
      )}
      {tab === 'gathering' && (
        <ul className="pr-list">
          {s.gathering.map((g) => (
            <li key={g.id} className={g.locked ? 'locked' : ''}>
              <Tile icon="pin" color="#7bd88f" />
              <span className="pr-list-main"><strong>{g.label}</strong><em>{g.locked ? `Needs level ${g.level}` : g.cooldown > 0 ? `Picked over: back in ${Math.ceil(g.cooldown / 60)} min` : g.points > 1 ? `${g.ready} of ${g.points} spots ready` : 'Ready to gather'}</em></span>
              {!g.locked && g.cooldown === 0 && <Chip tone="ok">Ready</Chip>}
              <Button kind="ghost" onClick={() => c.waypoint(g.x, g.y)}><Ico name="pin" size={14} />GPS</Button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

export function Production({ c }: { c: Ctx }) {
  const { s } = c;
  return (
    <div className="pr-page">
      <div className="pr-page-head"><div><h2>Production</h2><p>Your workstations and what they are making. Step up to a bench to start, collect or cancel.</p></div></div>
      {s.workstations.length === 0 ? <Empty icon="gear" title="No workstations" text="Buy a Prep Table at the supplier and set it up from your inventory." /> : s.workstations.map((b) => (
        <section key={b.id} className="pr-card"><BenchPanel bench={b} labels={s.itemLabels} act={false} />
          {!b.property && <div className="pr-card-foot"><Button kind="ghost" onClick={() => c.waypoint(b.x, b.y)}><Ico name="pin" size={14} />GPS to this bench</Button></div>}
        </section>
      ))}
    </div>
  );
}

export function Progression({ c }: { c: Ctx }) {
  const { s } = c;
  const [br, setBr] = useState('botanical');
  const bot = s.progress.branches[br] ?? s.progress.branches.botanical;
  return (
    <div className="pr-page">
      <div className="pr-page-head"><div><h2>Progression</h2><p>Levels unlock varieties, recipes and laboratories.</p></div></div>
      {Object.entries(s.progress.branches).map(([id, b]) => (
        <section key={id} className="pr-banner slim">
          <div className="pr-banner-text"><small>{b.label.toUpperCase()}</small><h2>Level {b.level} · {b.levelName}</h2><Bar value={b.progress} color={b.color} /><em>{b.xp.toLocaleString()} XP{b.nextXp ? ` · ${b.nextXp.toLocaleString()} for level ${b.level + 1}` : ' · top level'}</em></div>
          <Ring value={b.progress} size={84} stroke={7} color={b.color}><b>{b.level}</b><i>LEVEL</i></Ring>
        </section>
      ))}
      <div className="pr-tabs" role="tablist">{Object.entries(s.progress.branches).map(([id, b]) => <button key={id} role="tab" aria-selected={br === id} className={cx(br === id && 'on')} onClick={() => setBr(id)}>{b.label}</button>)}</div>
      <ol className="pr-ladder">
        {s.levelNames.map((n, i) => {
          const lv = i + 1;
          const here = bot?.level ?? 1;
          const unlocks = [...s.varieties.filter((v) => v.branch === br && v.level === lv).map((v) => `${v.label} seeds`), ...s.properties.properties.filter((p) => p.branch === br && p.level === lv).map((p) => p.label)];
          return (
            <li key={n} className={cx(lv <= here && 'reached', lv === here && 'current')}>
              <span className="pr-ladder-dot">{lv <= here ? <Ico name="check" size={13} /> : <Ico name="lock" size={12} />}</span>
              <div><strong>Level {lv} · {n}</strong><em>{unlocks.length ? `Unlocks: ${unlocks.join(', ')}` : lv === 1 ? 'Where everyone starts' : 'More recipes and standing'}</em></div>
              {lv === here && <Chip tone="accent">You are here</Chip>}
            </li>
          );
        })}
      </ol>
    </div>
  );
}

const STATS: [string, string, string, string][] = [
  ['plants_planted', 'Plants planted', 'leaf', '#7bd88f'], ['plants_harvested', 'Plants harvested', 'check', '#5fd68c'], ['leaves_harvested', 'Leaves harvested', 'leaf', '#4aa8ff'],
  ['gathered', 'Times gathered', 'pin', '#f2b443'], ['batches_completed', 'Batches finished', 'gear', '#c58bff'], ['purchases', 'Purchases', 'bag', '#ef7a3a'],
  ['sales', 'Sales', 'money', '#5fd68c'], ['money_spent', 'Money spent', 'money', '#e0576a'], ['money_earned', 'Money earned', 'money', '#5fd68c'],
];
export function Stats({ c }: { c: Ctx }) {
  const st = c.s.progress.stats;
  return (
    <div className="pr-page">
      <div className="pr-page-head"><div><h2>Statistics</h2><p>Your lifetime activity.</p></div></div>
      <div className="pr-statgrid">
        {STATS.map(([k, label, icon, color]) => (
          <section key={k} className="pr-card stat"><Tile icon={icon} color={color} /><strong>{k.startsWith('money') ? usd(st[k] ?? 0) : (st[k] ?? 0).toLocaleString()}</strong><span>{label}</span></section>
        ))}
      </div>
    </div>
  );
}

const hourText = (h: number[]) => (h[0] === 0 && h[1] === 24 ? 'any hour' : `${String(h[0]).padStart(2, '0')}:00 to ${String(h[1] % 24).padStart(2, '0')}:00`);

export function Supplier({ c }: { c: Ctx }) {
  const { s } = c;
  const sup = s.supplier;
  const run = sup.run;
  const left = Math.max(0, (run?.expiresAt ?? 0) - s.serverTime);
  return (
    <div className="pr-page">
      <div className="pr-page-head"><div><h2>Supplier Operations</h2><p>Take a run from a contact: collect a crate, deliver it before time runs out and get paid in supply kits.</p></div></div>
      {run && (
        <section className="pr-card pr-run">
          <h4 className="pr-h">CURRENT RUN</h4>
          <div className="pr-branch">
            <Tile icon="bag" color="#f2b443" />
            <div className="pr-grow"><strong>{run.state === 'active' ? `Collect the crate: ${run.pickup.label}` : `Deliver it: ${run.drop?.label ?? ''}`}</strong><em>About {Math.ceil(left / 60)} min left · pays up to {run.kits} kits</em></div>
            <Chip tone={run.state === 'active' ? 'accent' : 'ok'}>{run.state === 'active' ? 'Pickup' : 'Carrying'}</Chip>
          </div>
          <div className="pr-card-foot">
            <Button kind="ghost" onClick={() => { const p = run.state === 'active' ? run.pickup : run.drop; if (p) c.waypoint(p.x, p.y); }}><Ico name="pin" size={14} />Set GPS</Button>
            <Button kind="ghost" onClick={() => void c.run('runCancel')}><Ico name="x" size={14} />Drop this run</Button>
          </div>
        </section>
      )}
      <ul className="pr-list">
        {sup.suppliers.map((x) => (
          <li key={x.id} className={x.locked ? 'locked' : ''}>
            <Tile icon="bag" color="#f2b443" />
            <span className="pr-list-main"><strong>{x.label}</strong><em>{x.locked ? `Needs level ${x.level}` : `${usd(x.fee)} fee · ${hourText(x.hours)} · ${x.runsLeft} run${x.runsLeft === 1 ? '' : 's'} left today · ${x.minutes} min limit · ${x.kits[0]}-${x.kits[1]} kits`}</em></span>
            {!x.locked && !x.open && <Chip tone="mute">Closed</Chip>}
            {!x.locked && x.open && x.runsLeft > 0 && <Chip tone="ok">Open</Chip>}
            <Button kind="ghost" onClick={() => c.waypoint(x.x, x.y)}><Ico name="pin" size={14} />GPS</Button>
          </li>
        ))}
      </ul>
      <p className="pr-note"><Ico name="info" size={14} />Speak to the contact in person to start a run. Kits go into the chemistry recipes at a station.</p>
    </div>
  );
}
