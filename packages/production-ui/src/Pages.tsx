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
          <div className="pr-branch">
            <Ring value={bot?.progress ?? 0} size={52} stroke={5} color={bot?.color}><b className="sm">{bot?.level}</b></Ring>
            <div className="pr-grow"><strong>{bot?.label} · {bot?.levelName}</strong><em>{bot?.xp.toLocaleString()} XP{bot?.nextXp ? ` · ${bot.nextXp.toLocaleString()} for level ${(bot?.level ?? 1) + 1}` : ''}</em></div>
          </div>
          <p className="pr-note"><Ico name="info" size={14} />Field and supplier branches are not built yet, so they are not listed.</p>
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

export function Botanical({ c }: { c: Ctx }) {
  const { s } = c;
  const [tab, setTab] = useState<'plants' | 'varieties' | 'gathering'>('plants');
  return (
    <div className="pr-page">
      <div className="pr-page-head"><div><h2>Botanical</h2><p>Grow, gather and prepare. Tend plants by walking up to them.</p></div></div>
      <div className="pr-tabs" role="tablist">
        {(['plants', 'varieties', 'gathering'] as const).map((t) => <button key={t} role="tab" aria-selected={tab === t} className={cx(tab === t && 'on')} onClick={() => setTab(t)}>{t === 'plants' ? `Plants (${s.plants.length})` : t === 'varieties' ? 'Varieties' : 'Gathering'}</button>)}
      </div>
      {tab === 'plants' && (s.plants.length === 0 ? <Empty icon="leaf" title="No plants yet" text="Buy seeds and a planter at the supplier, then use the seeds from your inventory." /> : (
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
              <span className="pr-list-main"><strong>{g.label}</strong><em>{g.locked ? `Needs level ${g.level}` : g.cooldown > 0 ? `Picked over: back in ${Math.ceil(g.cooldown / 60)} min` : 'Ready to gather'}</em></span>
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
  const bot = s.progress.branches.botanical;
  return (
    <div className="pr-page">
      <div className="pr-page-head"><div><h2>Progression</h2><p>Levels unlock varieties, recipes and laboratories.</p></div></div>
      {Object.entries(s.progress.branches).map(([id, b]) => (
        <section key={id} className="pr-banner slim">
          <div className="pr-banner-text"><small>{b.label.toUpperCase()}</small><h2>Level {b.level} · {b.levelName}</h2><Bar value={b.progress} color={b.color} /><em>{b.xp.toLocaleString()} XP{b.nextXp ? ` · ${b.nextXp.toLocaleString()} for level ${b.level + 1}` : ' · top level'}</em></div>
          <Ring value={b.progress} size={84} stroke={7} color={b.color}><b>{b.level}</b><i>LEVEL</i></Ring>
        </section>
      ))}
      <ol className="pr-ladder">
        {s.levelNames.map((n, i) => {
          const lv = i + 1;
          const here = bot?.level ?? 1;
          const unlocks = [...s.varieties.filter((v) => v.level === lv).map((v) => `${v.label} seeds`), ...s.properties.properties.filter((p) => p.level === lv).map((p) => p.label)];
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
