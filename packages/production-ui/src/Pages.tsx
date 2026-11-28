import { useState } from 'react';
import type { Ctx } from './ctx';
import { BenchPanel } from './Bench';
import { Bar, Button, Chip, Empty, Ico, ago, cx, usd } from './ui';

export function Dashboard({ c }: { c: Ctx }) {
  const { s } = c;
  const rep = s.progress.reputation;
  const growing = s.plants.filter((p) => p.state === 'growing').length;
  const ready = s.plants.filter((p) => p.state === 'ready').length;
  const queued = s.workstations.reduce((n, b) => n + b.batches.length, 0);
  const owned = s.properties.properties.filter((p) => p.role === 'owner');
  return (
    <div className="pr-page">
      <div className="pr-page-head"><div><h2>Dashboard</h2><p>Welcome back, {s.player.name}.</p></div></div>
      <div className="pr-cards">
        <section className="pr-card hero">
          <span className="pr-crest"><Ico name="star" size={26} /></span>
          <div className="pr-grow"><small>REPUTATION</small><h3>{rep.name}</h3><Bar value={rep.next ? (rep.xp - rep.floor) / (rep.next - rep.floor) : 1} label="Reputation" /><em>{rep.xp.toLocaleString()} XP{rep.next ? ` · ${rep.next.toLocaleString()} for the next level` : ''}</em></div>
        </section>
        <section className="pr-card stat"><Ico name="leaf" /><strong>{growing}{ready > 0 && <i className="pr-ready"> +{ready} ready</i>}</strong><span>Plants growing</span></section>
        <section className="pr-card stat"><Ico name="gear" /><strong>{queued}</strong><span>Batches queued</span></section>
        <section className="pr-card stat"><Ico name="home" /><strong>{owned.length}</strong><span>Laboratories owned</span></section>
      </div>
      <div className="pr-twocol">
        <section className="pr-card">
          <h4 className="pr-h">BRANCHES</h4>
          {Object.entries(s.progress.branches).map(([id, b]) => (
            <div key={id} className="pr-branch">
              <span className="pr-branch-ico" style={{ background: b.color }}><Ico name={b.icon === 'leaf' ? 'leaf' : 'gear'} size={16} /></span>
              <div className="pr-grow"><strong>{b.label} · {b.levelName}</strong><Bar value={b.progress} color={b.color} label={`${b.label} progress`} /><em>Level {b.level} · {b.xp.toLocaleString()} XP</em></div>
            </div>
          ))}
          <p className="pr-note"><Ico name="info" size={14} />Field and supplier operations are not built yet, so they are not listed here.</p>
        </section>
        <section className="pr-card">
          <h4 className="pr-h">RECENT ACTIVITY</h4>
          {s.recent.length === 0 ? <p className="pr-mute">Nothing yet. Gather something or visit the supplier.</p> : (
            <ul className="pr-activity">{s.recent.map((r, i) => <li key={i}><Ico name={r.kind === 'harvest' ? 'leaf' : r.kind === 'purchase' ? 'bag' : r.kind === 'sale' ? 'money' : r.kind === 'raid' ? 'shield' : 'check'} size={15} /><span>{r.text}</span><time>{ago(r.at, s.serverTime)}</time></li>)}</ul>
          )}
        </section>
      </div>
    </div>
  );
}

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
          {s.plants.map((p) => (
            <article key={p.id} className={cx('pr-plant', p.state)}>
              <div className="pr-plant-top"><strong>{p.label}</strong><Chip tone={p.state === 'ready' ? 'ok' : p.state === 'dead' ? 'bad' : 'accent'}>{p.state === 'ready' ? 'Ready' : p.state === 'dead' ? 'Dead' : `${p.minutesLeft} min`}</Chip></div>
              <Bar value={p.growth} label="Growth" />
              <div className="pr-meters">
                <span title="Water"><Ico name="drop" size={13} /><Bar value={p.water / 100} color="#3f9bff" label="Water" /></span>
                <span title="Nutrients"><Ico name="leaf" size={13} /><Bar value={p.nutrient / 100} color="#7bd88f" label="Nutrients" /></span>
                <span title="Health"><Ico name="shield" size={13} /><Bar value={p.health / 100} color={p.health < 40 ? '#e0576a' : '#c58bff'} label="Health" /></span>
              </div>
              <div className="pr-plant-foot"><span className="pr-sub">{p.property ? 'In a laboratory' : 'Outdoors'}</span>{!p.property && <Button kind="ghost" onClick={() => c.waypoint(p.x, p.y)}><Ico name="pin" size={14} />GPS</Button>}</div>
            </article>
          ))}
        </div>
      ))}
      {tab === 'varieties' && (
        <ul className="pr-list">
          {s.varieties.map((v) => (
            <li key={v.key} className={v.locked ? 'locked' : ''}>
              <span className="pr-badge" style={{ background: v.rarity === 'Rare' ? '#c98a1d' : v.rarity === 'Uncommon' ? '#7b45d8' : '#2f5fe0' }}><Ico name="leaf" size={16} /></span>
              <span className="pr-list-main"><strong>{v.label}</strong><em>{v.rarity} · grows in {v.growMinutes} min · yields {v.yield[0]}–{v.yield[1]}</em></span>
              {v.locked ? <Chip tone="warn"><Ico name="lock" size={12} />Level {v.level}</Chip> : <Chip tone="ok">Unlocked</Chip>}
            </li>
          ))}
        </ul>
      )}
      {tab === 'gathering' && (
        <ul className="pr-list">
          {s.gathering.map((g) => (
            <li key={g.id} className={g.locked ? 'locked' : ''}>
              <span className="pr-badge" style={{ background: '#2d6b3a' }}><Ico name="pin" size={16} /></span>
              <span className="pr-list-main"><strong>{g.label}</strong><em>{g.locked ? `Needs level ${g.level}` : g.cooldown > 0 ? `Picked over: back in ${Math.ceil(g.cooldown / 60)} min` : 'Ready to gather'}</em></span>
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
  return (
    <div className="pr-page">
      <div className="pr-page-head"><div><h2>Progression</h2><p>Levels unlock varieties, recipes and laboratories.</p></div></div>
      {Object.entries(s.progress.branches).map(([id, b]) => (
        <section key={id} className="pr-card hero">
          <span className="pr-crest" style={{ borderColor: b.color }}><Ico name="leaf" size={26} /></span>
          <div className="pr-grow"><small>{b.label.toUpperCase()}</small><h3>Level {b.level} · {b.levelName}</h3><Bar value={b.progress} color={b.color} /><em>{b.xp.toLocaleString()} XP{b.nextXp ? ` · ${b.nextXp.toLocaleString()} for level ${b.level + 1}` : ' · top level'}</em></div>
        </section>
      ))}
      <ol className="pr-ladder">
        {s.levelNames.map((n, i) => {
          const lv = i + 1;
          const here = s.progress.branches.botanical?.level ?? 1;
          const unlocks = [...s.varieties.filter((v) => v.level === lv).map((v) => `${v.label} seeds`), ...s.properties.properties.filter((p) => p.level === lv).map((p) => p.label)];
          return (
            <li key={n} className={cx(lv <= here && 'reached', lv === here && 'current')}>
              <span className="pr-ladder-dot">{lv <= here ? <Ico name="check" size={13} /> : <Ico name="lock" size={12} />}</span>
              <div><strong>Level {lv} · {n}</strong><em>{unlocks.length ? `Unlocks: ${unlocks.join(', ')}` : lv === 1 ? 'Where everyone starts' : 'More recipes and standing'}</em></div>
            </li>
          );
        })}
      </ol>
    </div>
  );
}

const STAT_LABELS: Record<string, string> = {
  plants_planted: 'Plants planted', plants_harvested: 'Plants harvested', leaves_harvested: 'Leaves harvested', gathered: 'Times gathered', batches_completed: 'Batches finished',
  purchases: 'Purchases', sales: 'Sales', money_spent: 'Money spent', money_earned: 'Money earned',
};
export function Stats({ c }: { c: Ctx }) {
  const st = c.s.progress.stats;
  const keys = Object.keys(STAT_LABELS);
  return (
    <div className="pr-page">
      <div className="pr-page-head"><div><h2>Statistics</h2><p>Your lifetime activity.</p></div></div>
      <div className="pr-statgrid">
        {keys.map((k) => <section key={k} className="pr-card stat"><strong>{k.startsWith('money') ? usd(st[k] ?? 0) : (st[k] ?? 0).toLocaleString()}</strong><span>{STAT_LABELS[k]}</span></section>)}
      </div>
    </div>
  );
}
