import { useState } from 'react';
import type { Ctx } from './ctx';
import { Badge, Bar, Button, CarImage, Confirm, Empty, Ico, badgeTone, cx, mmss, useCountdown, usd } from './ui';

const STEPS = [
  { id: 'start', label: 'Start the contract', states: ['reserved'] },
  { id: 'find', label: 'Find the vehicle in the marked area', states: ['active'] },
  { id: 'access', label: 'Access the vehicle', states: ['active'] },
  { id: 'deliver', label: 'Drive it to the handoff point', states: ['vehicle_acquired', 'delivery_started'] },
  { id: 'hand', label: 'Hand it over', states: ['delivery_started'] },
];

export function Active({ c }: { c: Ctx }) {
  const a = c.s.active;
  const [confirm, setConfirm] = useState(false);
  const left = useCountdown(a?.expiresAt, c.s.serverTime);
  const reserveLeft = useCountdown(a?.reserveUntil, c.s.serverTime);
  if (!a) return <div className="bst-page"><div className="bst-page-head"><div><h2>Active Contract</h2></div></div><Empty icon="play" title="No active contract" text="Take one from the Contracts page." /></div>;

  const total = a.timeLimit * 60;
  const reached = a.state === 'reserved' ? 0 : a.state === 'active' ? (a.acquired > 0 ? 3 : 1) : a.state === 'vehicle_acquired' ? 3 : 4;
  const done = (i: number) => i < reached;
  const target = a.drop && a.state !== 'active' ? a.drop : a.area ? { label: 'Search area', x: a.area.x, y: a.area.y } : null;
  const delivered = a.vehicles.filter((v) => v.status === 'delivered').length;

  return (
    <div className="bst-page">
      <div className="bst-page-head">
        <div><h2>Active Contract</h2><p>{a.label}</p></div>
        <div className="bst-head-actions">
          {a.canStart && <Button kind="primary" disabled={c.busy || (a.needsCrew && a.members.length < 2)} onClick={() => void c.run('startContract')} title={a.needsCrew && a.members.length < 2 ? 'Needs a crew' : undefined}><Ico name="play" size={16} />Start contract</Button>}
          {target && <Button onClick={() => c.waypoint(target.x, target.y)}><Ico name="route" size={16} />Set GPS</Button>}
          {a.canCancel && a.leader && <Button kind="danger" onClick={() => setConfirm(true)}>Cancel contract</Button>}
        </div>
      </div>

      <div className="bst-active-grid">
        <section className="bst-panel">
          <div className="bst-active-hero">
            <CarImage model={a.vehicles[0]?.model} className="hero" />
            <div>
              <Badge tone={badgeTone(a.badge)}>{a.badge}</Badge>
              <h3>{a.vehicles.length > 1 ? `${a.vehicles.length} vehicles` : a.vehicles[0]?.label}</h3>
              <div className="bst-active-time big"><Ico name="clock" size={18} /><strong className={a.state !== 'reserved' && left < 120 ? 'low' : ''}>{mmss(a.state === 'reserved' ? reserveLeft : left)}</strong><span>{a.state === 'reserved' ? 'until the reservation ends' : 'remaining'}</span></div>
              {a.state !== 'reserved' && <Bar value={left / total} color={left < 120 ? 'var(--bst-bad)' : undefined} label="Time remaining" />}
            </div>
          </div>
          <h4 className="bst-h"><i />OBJECTIVES</h4>
          <ol className="bst-steps">
            {STEPS.map((st, i) => (
              <li key={st.id} className={cx(done(i) && 'done', reached === i && 'now')}>
                <span>{done(i) ? <Ico name="check" size={14} /> : i + 1}</span>{st.label}
              </li>
            ))}
          </ol>
          {a.tracked && <div className={cx('bst-note', a.trackerOff ? 'ok' : 'warn')}><Ico name="signal" size={16} />{a.trackerOff ? 'Tracker disabled.' : 'This vehicle has a tracker. Disable it from the vehicle (needs a hacking device), or it keeps pinging dispatch.'}</div>}
        </section>

        <aside className="bst-active-side">
          <section className="bst-panel">
            <h4 className="bst-h"><Ico name="car" size={16} />VEHICLES</h4>
            <ul className="bst-vlist">
              {a.vehicles.map((v) => (
                <li key={v.index}>
                  <CarImage model={v.model} className="thumb" />
                  <span><strong>{v.label}</strong><em>{v.status === 'waiting' ? 'Locked' : v.status === 'acquired' ? 'Acquired' : 'Delivered'}</em></span>
                  <Badge tone={v.status === 'delivered' ? 'ok' : v.status === 'acquired' ? 'premium' : 'mute'}>{v.status === 'waiting' ? 'Find' : v.status === 'acquired' ? 'Deliver' : 'Done'}</Badge>
                </li>
              ))}
            </ul>
            {a.vehicles.length > 1 && <Bar value={delivered / a.vehicles.length} label="Deliveries" />}
          </section>
          <section className="bst-panel">
            <h4 className="bst-h"><Ico name="pin" size={16} />DELIVERY</h4>
            {a.drop ? <p className="bst-dest"><strong>{a.drop.label}</strong><em>Park on the marker, step out and use the handoff prompt.</em></p> : <p className="bst-mute">The handoff point is revealed once you have a vehicle.</p>}
            <div className="bst-reward"><span>Estimated payout</span><strong>{usd(a.reward)}</strong><em>+{a.repReward} reputation</em></div>
          </section>
          <section className="bst-panel">
            <h4 className="bst-h"><Ico name="crew" size={16} />CREW</h4>
            <ul className="bst-members">{a.members.map((m) => <li key={m.id} className={m.online ? '' : 'off'}><Ico name={m.leader ? 'crown' : 'user'} size={15} />{m.name}{m.me ? ' (you)' : ''}<i className={m.online ? 'on' : ''} /></li>)}</ul>
          </section>
        </aside>
      </div>
      {confirm && (
        <Confirm danger title="Cancel this contract?" confirm="Cancel contract"
          text={a.acquired > 0 ? 'You already have the vehicle. Abandoning it costs reputation.' : 'Nothing has been lost yet, so this is free.'}
          onCancel={() => setConfirm(false)} onConfirm={() => { setConfirm(false); void c.run('cancelContract'); }} />
      )}
    </div>
  );
}
