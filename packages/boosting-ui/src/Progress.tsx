import type { Ctx } from './ctx';
import { Bar, Badge, Ico, cx, heatVars, mmss, usd } from './ui';

export function Reputation({ c }: { c: Ctx }) {
  const { player, ranks } = c.s;
  return (
    <div className="bst-page">
      <div className="bst-page-head"><div><h2>Reputation and Ranks</h2><p>Finish contracts to earn reputation. Failing or abandoning them costs some.</p></div></div>
      <section className="bst-panel bst-rankhero">
        <span className="bst-crest"><Ico name="crown" size={34} /></span>
        <div className="bst-rankhero-main">
          <small>CURRENT RANK</small>
          <h3>{player.rank}</h3>
          <Bar value={player.progress} label="Progress to the next rank" />
          <div className="bst-rankhero-foot"><span>{player.rep.toLocaleString()} rep</span><span>{player.nextRank ? `${player.nextRep?.toLocaleString()} for ${player.nextRank}` : 'Highest rank'}</span></div>
        </div>
      </section>
      <ol className="bst-ladder">
        {ranks.map((r) => (
          <li key={r.id} className={cx(r.reached && 'reached', r.current && 'current')}>
            <span className="bst-ladder-dot">{r.reached ? <Ico name="check" size={14} /> : <Ico name="lock" size={13} />}</span>
            <div><strong>{r.label}</strong><em>{r.perk ?? 'Where everyone starts'}</em></div>
            <b>{r.rep.toLocaleString()} rep</b>
          </li>
        ))}
      </ol>
    </div>
  );
}

export function Heat({ c }: { c: Ctx }) {
  const h = c.s.heat;
  const idx = h.levels.findIndex((l) => l.id === h.level);
  return (
    <div className="bst-page">
      <div className="bst-page-head"><div><h2>Heat and Attention</h2><p>Heat is how much notice you draw. It rises when things go loud or wrong, and cools over time{h.decay ? ` (about ${h.decay} per minute)` : ''}.</p></div></div>
      <section className="bst-panel bst-heat-hero" style={heatVars(h.color)}>
        <span className="bst-flame"><Ico name="flame" size={44} /></span>
        <div className="bst-heat-main">
          <small>HEAT LEVEL</small>
          <h3>{h.label.toUpperCase()}</h3>
          <Bar value={h.value / h.max} color={h.color} label="Heat" />
          <div className="bst-rankhero-foot"><span>{h.value} / {h.max}</span><span>Pay x{h.rewardMult.toFixed(2)} on new contracts</span></div>
        </div>
      </section>
      <div className="bst-heat-levels">
        {h.levels.map((l, i) => (
          <div key={l.id} className={cx('bst-heat-level', i === idx && 'on')} style={heatVars(l.color)}>
            <b>{l.label}</b><span>up to {l.max}</span><em>Pay x{l.rewardMult.toFixed(2)}</em>
          </div>
        ))}
      </div>
      <div className="bst-note"><Ico name="signal" size={16} />{h.police ? 'A dispatch resource is connected: loud moments can send an alert to police.' : 'No dispatch resource is connected, so heat only affects your offers.'} High heat hides the easy contracts.</div>
    </div>
  );
}

export function Stats({ c }: { c: Ctx }) {
  const { stats, challenges } = c.s;
  const items: [string, string, string][] = [
    ['contracts', 'Contracts completed', stats.completed.toLocaleString()],
    ['alert', 'Contracts failed', stats.failed.toLocaleString()],
    ['money', 'Total earned', usd(stats.earnings)],
    ['clock', 'Best contract time', stats.best ? mmss(stats.best) : '--'],
    ['star', 'Reputation', stats.rep.toLocaleString()],
  ];
  return (
    <div className="bst-page">
      <div className="bst-page-head"><div><h2>Statistics</h2><p>Your lifetime numbers.</p></div></div>
      <div className="bst-stats">
        <section className="bst-panel bst-rate">
          <div className="bst-ring" style={{ '--p': `${Math.round(stats.rate * 100)}%` } as React.CSSProperties}><strong>{Math.round(stats.rate * 100)}%</strong></div>
          <span>Success rate</span>
        </section>
        <div className="bst-stat-grid">
          {items.map(([icon, label, value]) => <section key={label} className="bst-panel bst-stat"><Ico name={icon} size={20} /><strong>{value}</strong><span>{label}</span></section>)}
        </div>
      </div>
      <h4 className="bst-h"><i />CHALLENGES</h4>
      <div className="bst-challenges">
        {challenges.map((ch) => (
          <section key={ch.id} className="bst-panel bst-challenge">
            <div className="bst-challenge-top"><strong>{ch.label}</strong><Badge tone={ch.kind === 'daily' ? 'standard' : 'premium'}>{ch.kind === 'daily' ? 'DAILY' : 'WEEKLY'}</Badge></div>
            <Bar value={ch.progress / ch.goal} />
            <div className="bst-challenge-foot"><span>{ch.done ? 'Complete' : `${ch.progress.toLocaleString()} / ${ch.goal.toLocaleString()}`}</span><b>{usd(ch.reward)}</b></div>
          </section>
        ))}
      </div>
    </div>
  );
}
