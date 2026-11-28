import { useState } from 'react';
import type { Ctx } from './ctx';
import type { Tier } from './types';
import { Badge, CarImage, Ico, cx, usd } from './ui';

export function Vehicles({ c }: { c: Ctx }) {
  const [tier, setTier] = useState<'all' | Tier>('all');
  const list = c.s.catalogue.filter((v) => tier === 'all' || v.tier === tier);
  const unlocked = c.s.catalogue.filter((v) => v.unlocked).length;
  return (
    <div className="bst-page">
      <div className="bst-page-head"><div><h2>Vehicle Catalogue</h2><p>{unlocked} of {c.s.catalogue.length} vehicles unlocked. Reputation unlocks more.</p></div></div>
      <div className="bst-tabs" role="tablist">
        {(['all', 'standard', 'premium', 'luxury'] as const).map((t) => (
          <button key={t} role="tab" aria-selected={tier === t} className={cx(tier === t && 'on')} onClick={() => setTier(t)}>{t === 'all' ? 'All' : c.s.tiers[t].label}</button>
        ))}
      </div>
      <div className="bst-vgrid">
        {list.map((v) => (
          <article key={v.model} className={cx('bst-vcard', !v.unlocked && 'locked')}>
            <div className="bst-vcard-img"><CarImage model={v.model} />{!v.unlocked && <span className="bst-vlock"><Ico name="lock" size={20} /><b>{v.minRep} rep</b></span>}</div>
            <div className="bst-vcard-body">
              <strong>{v.label}</strong>
              <div className="bst-vcard-tags"><Badge tone={v.tier === 'luxury' ? 'event' : v.tier === 'premium' ? 'premium' : 'standard'}>{c.s.tiers[v.tier].label}</Badge><span className="bst-pips">{[1, 2, 3, 4, 5].map((i) => <i key={i} className={i <= v.difficulty ? 'on' : ''} />)}</span></div>
              <div className="bst-vcard-foot"><span className="pay">from {usd(v.baseReward * 0.9)}</span><span className="bst-mute">{v.solo && v.group ? 'Solo / Crew' : v.group ? 'Crew only' : 'Solo'}</span></div>
            </div>
          </article>
        ))}
      </div>
    </div>
  );
}
