import { useState } from 'react';
import type { Ctx } from './ctx';
import type { Offer } from './types';
import { Badge, Button, CarImage, Empty, Ico, Modal, badgeTone, cx, mmss, useCountdown, usd } from './ui';
import { OfferCard } from './Dashboard';

const FILTERS = ['ALL', 'STANDARD', 'PREMIUM', 'HIGH RISK', 'TIMED', 'CREW', 'EVENT'] as const;

export function Contracts({ c }: { c: Ctx }) {
  const [filter, setFilter] = useState<(typeof FILTERS)[number]>('ALL');
  const [view, setView] = useState<Offer | null>(null);
  const left = useCountdown(c.s.offersAt + c.s.offersTTL, c.s.serverTime);
  const list = c.s.offers.filter((o) => filter === 'ALL' || o.badge === filter);
  return (
    <div className="bst-page">
      <div className="bst-page-head">
        <div><h2>Contracts</h2><p>New contracts are generated for your rank. The list changes in {mmss(left)}.</p></div>
        <Button onClick={() => void c.run('refreshOffers')} disabled={c.busy}><Ico name="refresh" size={16} />Refresh</Button>
      </div>
      <div className="bst-tabs" role="tablist">
        {FILTERS.map((f) => <button key={f} role="tab" aria-selected={filter === f} className={cx(filter === f && 'on')} onClick={() => setFilter(f)}>{f === 'ALL' ? 'All' : f.charAt(0) + f.slice(1).toLowerCase()}</button>)}
      </div>
      {list.length === 0 ? <Empty icon="contracts" title="No contracts in this category" text="Try another filter." /> : (
        <div className="bst-offers grid">{list.map((o) => <OfferCard key={o.id} o={o} onView={() => setView(o)} />)}</div>
      )}
      {view && <OfferModal c={c} o={view} onClose={() => setView(null)} />}
    </div>
  );
}

export function OfferModal({ c, o, onClose }: { c: Ctx; o: Offer; onClose: () => void }) {
  const crew = c.s.crew;
  const size = crew ? crew.members.length : 1;
  const isLeader = !crew || crew.leader;
  const problem = o.locked ?? (c.s.active ? 'Finish your current contract first'
    : !isLeader ? 'Only the crew leader can take contracts'
    : size > o.crew.max ? `This contract takes up to ${o.crew.max} people`
    : size < o.crew.min ? `This contract needs a crew of ${o.crew.min}+` : null);
  const accept = async () => {
    const r = await c.run('accept', o.id);
    if (r.ok) { onClose(); c.go('active'); }
  };
  return (
    <Modal title={o.label} onClose={onClose} wide>
      <div className="bst-offer-detail">
        <div className="bst-detail-car"><CarImage model={o.model} /><Badge tone={badgeTone(o.badge)}>{o.badge}</Badge></div>
        <div className="bst-detail-body">
          <p>{o.description}</p>
          <dl>
            <div><dt>Vehicle</dt><dd>{o.vehicles > 1 ? `${o.vehicles} vehicles` : o.vehicleLabel}</dd></div>
            <div><dt>Payout</dt><dd className="pay">{usd(o.rewardMin)} – {usd(o.rewardMax)}</dd></div>
            <div><dt>Reputation</dt><dd>+{o.repReward}</dd></div>
            <div><dt>Time limit</dt><dd>{o.timeLimit} min</dd></div>
            <div><dt>Requires</dt><dd>{o.minRank} · {o.minRep} rep</dd></div>
            <div><dt>Crew</dt><dd>{o.mode === 'solo' ? 'Solo only' : o.mode === 'group' ? `${o.crew.min}–${o.crew.max} people` : `Solo or up to ${o.crew.max}`}</dd></div>
            <div><dt>Difficulty</dt><dd><span className="bst-pips">{[1, 2, 3, 4, 5].map((i) => <i key={i} className={i <= o.difficulty ? 'on' : ''} />)}</span></dd></div>
            <div><dt>Tracker</dt><dd>{o.tracked ? 'Yes, disable it or it pings dispatch' : 'None'}</dd></div>
          </dl>
          {problem && <div className="bst-note warn"><Ico name="lock" size={16} />{problem}</div>}
          <div className="bst-modal-actions"><Button kind="ghost" onClick={onClose}>Close</Button><Button kind="primary" disabled={!!problem || c.busy} onClick={() => void accept()}>Accept contract</Button></div>
        </div>
      </div>
    </Modal>
  );
}
