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
  botanical: { title: 'Weed', blurb: 'Grow, gather, trim and bag. Tend plants by walking up to them.', gather: 'Gathering', empty: 'Buy seeds and a planter at the supplier, then use the seeds from your inventory.' },
  field: { title: 'Coke & Mushrooms', blurb: 'Work the wild ground: search the field zones, grow coca and mushrooms and tend them away from town.', gather: 'Field zones', empty: 'Search a field zone for seeds, or buy them at the outfitter, then use them from your inventory.' },
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
  ['sales', 'Sales', 'money', '#5fd68c'], ['street_sales', 'Street sales', 'bag', '#f2b443'], ['runs_completed', 'Supply runs done', 'bag', '#c58bff'], ['searched', 'Searches', 'pin', '#5ab0ff'], ['money_spent', 'Money spent', 'money', '#e0576a'], ['money_earned', 'Money earned', 'money', '#5fd68c'],
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
  const [near, setNear] = useState<{ id: number; name: string }[] | null>(null);
  const sup = s.supplier;
  const run = sup.run;
  const left = Math.max(0, (run?.expiresAt ?? 0) - s.serverTime);
  return (
    <div className="pr-page">
      <div className="pr-page-head"><div><h2>Chemistry</h2><p>Take a run from a contact: collect a crate, deliver it before time runs out and get paid in supply kits.</p></div></div>
      {run && (
        <section className="pr-card pr-run">
          <h4 className="pr-h">CURRENT RUN</h4>
          <div className="pr-branch">
            <Tile icon="bag" color="#f2b443" />
            <div className="pr-grow"><strong>{run.state === 'active' ? `Collect the crate: ${run.pickup.label}` : `Deliver it: ${run.drop?.label ?? ''}`}</strong><em>About {Math.ceil(left / 60)} min left · pays up to {run.kits} kits</em></div>
            <Chip tone={run.state === 'active' ? 'accent' : 'ok'}>{run.state === 'active' ? 'Pickup' : 'Carrying'}</Chip>
          </div>
          {run.group && (
            <div className="pr-note"><Ico name="users" size={14} />Riding with {run.group.members.length ? run.group.members.map((m) => m.name).join(', ') : 'nobody yet'} (up to {run.group.max} people). Everyone at the drop is paid, with a bonus for each extra person.</div>
          )}
          {!run.member && run.group && run.group.members.length + 1 < run.group.max && (
            <div className="pr-card-foot">
              {near === null ? <Button kind="ghost" onClick={async () => { const r = await c.run('nearbyPlayers'); setNear(((r as { data?: { id: number; name: string }[] }).data) ?? []); }}><Ico name="users" size={14} />Invite someone nearby</Button>
                : near.length === 0 ? <span className="pr-sub">Nobody is close enough</span>
                : near.map((p) => <Button key={p.id} kind="ghost" onClick={() => { void c.run('groupInvite', p.id); setNear(null); }}>{p.name}</Button>)}
            </div>
          )}
          <div className="pr-card-foot">
            <Button kind="ghost" onClick={() => { const p = run.state === 'active' ? run.pickup : run.drop; if (p) c.waypoint(p.x, p.y); }}><Ico name="pin" size={14} />Set GPS</Button>
            <Button kind="ghost" onClick={() => void c.run('runCancel')}><Ico name="x" size={14} />{run.member ? 'Leave this run' : 'Drop this run'}</Button>
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

const TREND = { high: ['ok', 'Demand is high'], low: ['bad', 'Flooded'], steady: ['mute', 'Steady'] } as const;

export function Street({ c }: { c: Ctx }) {
  const st = c.s.street;
  const [tab, setTab] = useState<'market' | 'territories' | 'regulars'>('market');
  return (
    <div className="pr-page">
      <div className="pr-page-head"><div><h2>Street</h2><p>What things are worth, who runs which streets, and the people who deal with you again.</p></div></div>
      <div className="pr-tabs" role="tablist">
        {(['market', 'territories', 'regulars'] as const).map((t) => <button key={t} role="tab" aria-selected={tab === t} className={cx(tab === t && 'on')} onClick={() => setTab(t)}>{t === 'market' ? 'Market' : t === 'territories' ? 'Territories' : `Regulars (${st.regulars.length})`}</button>)}
      </div>
      {tab === 'market' && (
        <ul className="pr-list">
          {st.market.map((m) => (
            <li key={m.item}>
              <div className="pr-halo sm"><ItemImg item={m.item} size={40} /></div>
              <span className="pr-list-main"><strong>{m.label}</strong><em>{usd(m.price)} now (base {usd(m.base)}, ×{m.mult.toFixed(2)}){m.street ? ' · sells on the street too' : ''}</em></span>
              <Chip tone={TREND[m.trend][0]}>{TREND[m.trend][1]}</Chip>
            </li>
          ))}
        </ul>
      )}
      {tab === 'territories' && (
        <>
          <ul className="pr-list">
            {st.territories.map((t) => (
              <li key={t.id}>
                <Tile icon="pin" color={t.controlled ? '#5fd68c' : '#f2b443'} />
                <span className="pr-list-main"><strong>{t.label}</strong><em>Prices ×{t.price.toFixed(2)} · peds ×{t.accept.toFixed(2)} willing · heat {t.heat}% · {t.controller ? `held by ${t.controller}` : 'nobody holds it'} · your influence {t.influence}</em>
                  <Bar value={t.heat / 100} color={t.heat > 60 ? '#e0576a' : t.heat > 30 ? '#f2b443' : '#5fd68c'} label="Heat" /></span>
                {t.controlled && <Chip tone="ok">+{t.bonus}% prices</Chip>}
                <Button kind="ghost" onClick={() => c.waypoint(t.x, t.y)}><Ico name="pin" size={14} />GPS</Button>
              </li>
            ))}
          </ul>
          <p className="pr-note"><Ico name="info" size={14} />Street sales build heat (peds get cagey, police alerts get likelier) and influence. The crew with the most influence holds the area and gets a price bonus there.</p>
        </>
      )}
      {tab === 'regulars' && (st.regulars.length === 0 ? <Empty icon="users" title="No regulars yet" text="Sell on the street. Some peds will want to deal with you again." /> : (
        <ul className="pr-list">
          {st.regulars.map((r) => (
            <li key={r.id}>
              <Tile icon="users" color="#c58bff" />
              <span className="pr-list-main"><strong>{r.name}</strong><em>{r.territory} · {r.sales} sold · loyalty {r.loyalty} (+{r.bonus}% price) · buys more than strangers</em></span>
              {r.wait > 0 ? <Chip tone="mute">Back in {Math.ceil(r.wait / 60)} min</Chip> : <Button kind="primary" onClick={() => void c.run('regularCall', r.id)}>Call</Button>}
            </li>
          ))}
        </ul>
      ))}
      {st.meet && <p className="pr-note"><Ico name="pin" size={14} />A meeting is set. GPS points to it.</p>}
    </div>
  );
}

export function Crew({ c }: { c: Ctx }) {
  const cr = c.s.crew;
  const [name, setName] = useState('');
  const [near, setNear] = useState<{ id: number; name: string }[] | null>(null);
  if (!cr.enabled) return <div className="pr-page"><Empty icon="users" title="Crews are off" text="This server has crews switched off." /></div>;
  if (!cr.crew) {
    return (
      <div className="pr-page">
        <div className="pr-page-head"><div><h2>Crew</h2><p>Start a crew to share plants and benches, level up together and hold territory.</p></div></div>
        {cr.invite && (
          <section className="pr-card"><h4 className="pr-h">INVITE</h4>
            <p>{cr.invite.from} invited you to <b>{cr.invite.crew}</b>.</p>
            <div className="pr-card-foot"><Button onClick={() => void c.run('crewAnswer', false)}>Decline</Button><Button kind="primary" onClick={() => void c.run('crewAnswer', true)}>Join</Button></div>
          </section>
        )}
        <section className="pr-card"><h4 className="pr-h">START A CREW</h4>
          <input className="pr-input" value={name} maxLength={20} placeholder="Crew name (3 to 20 letters and numbers)" onChange={(e) => setName(e.target.value)} />
          <div className="pr-card-foot"><Button kind="primary" disabled={name.trim().length < 3} onClick={() => void c.run('crewCreate', name)}>Register for {usd(cr.createCost)}</Button></div>
        </section>
      </div>
    );
  }
  const k = cr.crew;
  return (
    <div className="pr-page">
      <section className="pr-banner slim">
        <div className="pr-banner-text"><small>CREW</small><h2>{k.name}</h2><Bar value={k.nextXp ? (k.xp - k.floor) / (k.nextXp - k.floor) : 1} /><em>Level {k.level} · {k.xp.toLocaleString()} XP{k.nextXp ? ` · ${(k.nextXp - k.xp).toLocaleString()} to go` : ''} · +{k.bonus}% on what members sell</em></div>
        <Ring value={k.nextXp ? (k.xp - k.floor) / (k.nextXp - k.floor) : 1} size={84} stroke={7}><b>{k.level}</b><i>LEVEL</i></Ring>
      </section>
      <section className="pr-card"><h4 className="pr-h">MEMBERS ({k.members.length}/{cr.max})</h4>
        <ul className="pr-list">
          {k.members.map((m) => (
            <li key={m.id}><Tile icon="users" color={m.leader ? '#f2b443' : '#4aa8ff'} /><span className="pr-list-main"><strong>{m.name}{m.me ? ' (you)' : ''}</strong><em>{m.leader ? 'Leader' : 'Member'}</em></span>
              {k.leader && !m.me && <Button kind="ghost" onClick={() => void c.run('crewKick', m.id)}>Remove</Button>}</li>
          ))}
        </ul>
        {k.leader && (
          <div className="pr-card-foot">
            {near === null ? <Button kind="ghost" onClick={async () => { const r = await c.run('nearbyPlayers'); setNear(((r as { data?: { id: number; name: string }[] }).data) ?? []); }}><Ico name="plus" size={14} />Invite someone nearby</Button>
              : near.length === 0 ? <span className="pr-sub">Nobody is close enough</span>
              : near.map((p) => <Button key={p.id} kind="ghost" onClick={() => { void c.run('crewInvite', p.id); setNear(null); }}>{p.name}</Button>)}
          </div>
        )}
      </section>
      <section className="pr-card"><h4 className="pr-h">SHARING</h4>
        <p className="pr-mute">When on, crew mates can water, feed, harvest and use each other's outdoor plants and benches. Laboratories have their own access.</p>
        {k.leader && <div className="pr-card-foot"><Button onClick={() => void c.run('crewShare', !k.share)}>{k.share ? 'Turn sharing off' : 'Turn sharing on'}</Button></div>}
        {!k.leader && <Chip tone={k.share ? 'ok' : 'mute'}>{k.share ? 'Sharing is on' : 'Sharing is off'}</Chip>}
      </section>
      <div className="pr-card-foot">
        <Button kind="ghost" onClick={() => void c.run('crewLeave')}>Leave the crew</Button>
        {k.leader && <Button kind="ghost" onClick={() => { if (window.confirm('Close the crew for everyone?')) void c.run('crewDisband'); }}>Close the crew</Button>}
      </div>
    </div>
  );
}
