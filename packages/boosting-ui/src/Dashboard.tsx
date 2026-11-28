import { useState } from 'react';
import type { Ctx } from './ctx';
import type { Offer } from './types';
import { Badge, Bar, Button, CarImage, Empty, Ico, ago, badgeTone, mmss, useCountdown, usd } from './ui';
import { OfferModal } from './Contracts';

const STATE_LABEL: Record<string, string> = {
  reserved: 'WAITING TO START', active: 'FIND THE VEHICLE', vehicle_acquired: 'VEHICLE ACQUIRED', delivery_started: 'DELIVERING',
};
const STATE_HINT: Record<string, string> = {
  reserved: 'Gather your crew, then start the contract.', active: 'Find the vehicle in the marked area and access it.',
  vehicle_acquired: 'Deliver the vehicle to the specified location.', delivery_started: 'Deliver the vehicle to the specified location.',
};

export function Dashboard({ c }: { c: Ctx }) {
  const { s } = c;
  const a = s.active;
  const left = useCountdown(a?.expiresAt, s.serverTime);
  const reserveLeft = useCountdown(a?.reserveUntil, s.serverTime);
  const [view, setView] = useState<Offer | null>(null);
  const offers = s.offers.filter((o) => !o.locked).slice(0, 3);
  const members = s.crew?.members ?? [];
  const daily = s.challenges.find((x) => x.kind === 'daily');

  return (
    <div className="bst-dash">
      <div className="bst-dash-main">
        <section className="bst-panel active-card">
          <h4 className="bst-h"><i />ACTIVE CONTRACT</h4>
          {a ? (
            <div className="bst-active-row">
              <CarImage model={a.vehicles[0]?.model} className="hero" />
              <div className="bst-active-info">
                <div className={`bst-state ${a.state}`}><Ico name={a.state === 'active' || a.state === 'reserved' ? 'clock' : 'check'} size={20} />{STATE_LABEL[a.state] ?? a.state}</div>
                <p>{STATE_HINT[a.state]}</p>
                <div className="bst-active-meta">
                  {a.drop && <span><Ico name="pin" size={15} />Delivery: {a.drop.label}</span>}
                  {a.vehicles.length > 1 && <span><Ico name="car" size={15} />{a.vehicles.filter((v) => v.status === 'delivered').length}/{a.vehicles.length} delivered</span>}
                </div>
                <div className="bst-active-time">
                  <span><Ico name="clock" size={15} />{a.state === 'reserved' ? 'Reserved' : 'Time Remaining'}</span>
                  <strong className={left < 120 && a.state !== 'reserved' ? 'low' : ''}>{mmss(a.state === 'reserved' ? reserveLeft : left)}</strong>
                </div>
              </div>
              <Button kind="primary" onClick={() => c.go('active')}><Ico name="route" size={16} />Track Contract</Button>
            </div>
          ) : (
            <Empty icon="contracts" title="No active contract" text="Pick one below to get started." />
          )}
        </section>

        <h4 className="bst-h"><i />AVAILABLE CONTRACTS</h4>
        <div className="bst-offers">
          {offers.length === 0 && <Empty icon="contracts" title="Nothing available right now" text="Check back soon, or refresh the list." />}
          {offers.map((o) => <OfferCard key={o.id} o={o} onView={() => setView(o)} />)}
        </div>
      </div>

      <aside className="bst-dash-side">
        <section className="bst-panel">
          <h4 className="bst-h"><Ico name="crew" size={16} />CREW STATUS</h4>
          {members.length > 0 ? (
            <div className="bst-crew-mini">
              <span className="bst-crest sm"><Ico name="crown" size={18} /></span>
              <div><strong>{members.find((m) => m.leader)?.name ?? 'Crew'}'s crew</strong><em>{members.filter((m) => m.online).length} Member{members.filter((m) => m.online).length === 1 ? '' : 's'} Online</em></div>
            </div>
          ) : <p className="bst-mute">You are running solo. Invite nearby players from the Crew page.</p>}
          <Button kind="ghost" onClick={() => c.go('crew')}>Manage crew</Button>
        </section>
        <section className="bst-panel">
          <h4 className="bst-h"><Ico name="clock" size={16} />RECENT ACTIVITY</h4>
          {s.recent.length === 0 && <p className="bst-mute">Nothing yet. Complete a contract to get started.</p>}
          <ul className="bst-activity">
            {s.recent.slice(0, 4).map((r, i) => (
              <li key={i} className={r.kind}>
                <Ico name={r.kind === 'complete' ? 'check' : r.kind === 'rank' ? 'star' : r.kind === 'fail' ? 'alert' : 'contracts'} size={16} />
                <span><strong>{r.text}</strong>{r.detail && <em>{r.detail}</em>}</span>
                <time>{ago(r.at, s.serverTime)}</time>
              </li>
            ))}
          </ul>
        </section>
        <section className="bst-panel">
          <h4 className="bst-h"><Ico name="flag" size={16} />DAILY CHALLENGE</h4>
          {daily ? (
            <div className="bst-challenge">
              <strong>{daily.label}</strong>
              <Bar value={daily.progress / daily.goal} />
              <div className="bst-challenge-foot"><span>{daily.done ? 'Complete' : `${daily.progress.toLocaleString()} / ${daily.goal.toLocaleString()}`}</span><b>{usd(daily.reward)}</b></div>
            </div>
          ) : <p className="bst-mute">No challenge today.</p>}
        </section>
      </aside>
      {view && <OfferModal c={c} o={view} onClose={() => setView(null)} />}
    </div>
  );
}

export function OfferCard({ o, onView }: { o: Offer; onView: () => void }) {
  return (
    <article className={`bst-offer ${o.locked ? 'locked' : ''}`}>
      <Badge tone={badgeTone(o.badge)}>{o.badge}</Badge>
      <CarImage model={o.model} />
      <h5>{o.label}</h5>
      <p>{o.description}</p>
      <div className="bst-offer-stats">
        <span className="pay"><Ico name="money" size={15} />{usd(o.rewardMin)} – {usd(o.rewardMax)}</span>
        <span><Ico name="clock" size={15} />{o.timeLimit} min</span>
        <span className={`risk r${Math.min(3, Math.ceil(o.risk * 4))}`}><Ico name="flame" size={15} />{o.risk >= 0.5 ? 'High' : o.risk >= 0.3 ? 'Medium' : 'Low'}</span>
      </div>
      <div className="bst-offer-foot">
        <span className="bst-mode"><Ico name={o.mode === 'solo' ? 'user' : 'crew'} size={15} />{o.mode === 'solo' ? 'Solo' : o.mode === 'group' ? 'Crew' : 'Solo / Crew'}</span>
        {o.locked ? <span className="bst-lock"><Ico name="lock" size={14} />{o.locked}</span> : <Button kind="primary" onClick={onView}>View</Button>}
      </div>
    </article>
  );
}
