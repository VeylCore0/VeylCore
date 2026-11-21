import { useEffect, useMemo, useState } from 'react';
import { Icon, RadioCard, money, nui } from '@veyl/ui';
import { FloorPlan } from './FloorPlan';
import { api, newOp, type Catalog, type LeaseView, type UnitView } from '../types';

export function Leasing({ data, toast, onLeased }: { data: Catalog; toast: (k: 'ok' | 'error', t: string) => void; onLeased: (l: LeaseView) => void }) {
  const type = data.types[0];
  const floors = useMemo(() => [...new Set(data.units.map((u) => u.floor))].sort(), [data.units]);
  const [floor, setFloor] = useState(floors[0] ?? 1);
  const [unit, setUnit] = useState<UnitView | null>(null);
  const [method, setMethod] = useState<'bank' | 'cash'>(data.balances.bank >= (type?.initial ?? 0) ? 'bank' : 'cash');
  const [autopay, setAutopay] = useState(true);
  const [agreed, setAgreed] = useState(false);
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  const [op, setOp] = useState<string | null>(null); // kept for retries so a repeated click can never charge twice
  useEffect(() => {
    if (!confirm) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape' && !busy) setConfirm(false); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [confirm, busy]);

  if (data.myLease) {
    const l = data.myLease;
    return (
      <div className="apt-lease-done">
        <Icon name="home" size="2.4rem" />
        <h2>You live at Room {l.number}</h2>
        <p className="v-muted">{l.buildingLabel} · floor {l.floor}. Manage rent, keys and visitors from your home panel or the Apartments app.</p>
        <button className="v-btn primary" onClick={() => void nui('close')}>Close</button>
      </div>
    );
  }
  if (!type) return <div className="v-state">No apartments are offered here.</div>;

  const balance = data.balances[method];
  const short = balance < type.initial;
  const byWing = (f: number) => {
    const list = data.units.filter((u) => u.floor === f);
    const wings = [...new Set(list.map((u) => u.wing))];
    return wings.map((w) => ({ wing: w, units: list.filter((u) => u.wing === w) }));
  };

  const sign = async () => {
    if (!unit || busy) return;
    setBusy(true);
    const clientOp = op ?? newOp();
    setOp(clientOp);
    const res = await api<LeaseView>('lease', { unitId: unit.id, method, clientOp, autopay });
    setBusy(false);
    if (res.ok && res.data) { toast('ok', res.message ?? 'Lease signed'); onLeased(res.data); return; }
    if (res.code === 'PENDING') { toast('error', res.message ?? 'Payment is being confirmed. Try again in a moment.'); return; }
    setOp(null);
    setConfirm(false);
    toast('error', res.message ?? 'Could not sign the lease');
  };

  return (
    <div className="apt-leasing">
      <section className="apt-col apt-info v-panel">
        <div className="apt-eyebrow">{data.building.address}</div>
        <h2>{data.building.label}</h2>
        <div className="apt-type">
          <FloorPlan />
          <div>
            <div className="apt-type-name">{type.label}</div>
            <p className="v-muted">{type.description}</p>
          </div>
        </div>
        <ul className="apt-facts">
          <li><Icon name="money" size="1rem" /> {money(type.rent)} every {type.intervalDays} days</li>
          <li><Icon name="lock" size="1rem" /> {money(type.deposit)} deposit</li>
          <li><Icon name="box" size="1rem" /> {type.storage} storage slots</li>
          <li><Icon name="home" size="1rem" /> Up to {type.furnitureLimit} furniture pieces</li>
          {type.amenities.map((a) => <li key={a}><Icon name="check" size="1rem" /> {a}</li>)}
        </ul>
      </section>

      <section className="apt-col apt-units v-panel">
        <div className="apt-row-between">
          <h3>Choose a room</h3>
          <span className="v-muted">{type.available} of {data.units.length} available</span>
        </div>
        <div className="apt-floors" role="tablist">
          {floors.map((f) => <button key={f} role="tab" aria-selected={f === floor} className={`apt-chip${f === floor ? ' on' : ''}`} onClick={() => setFloor(f)}>Floor {f}</button>)}
        </div>
        {byWing(floor).map(({ wing, units }) => (
          <div key={wing} className="apt-wing">
            <div className="apt-wing-label">{wing} wing</div>
            <div className="apt-unit-grid">
              {units.map((u) => (
                <button key={u.id} disabled={!u.available} className={`apt-unit${unit?.id === u.id ? ' on' : ''}${u.available ? '' : ' taken'}`}
                  onClick={() => { setUnit(u); setOp(null); }} aria-label={`Room ${u.number}${u.available ? '' : ', taken'}`}>
                  <span className="apt-unit-no">{u.number}</span>
                  <span className="apt-unit-state">{u.available ? 'Available' : 'Taken'}</span>
                </button>
              ))}
            </div>
          </div>
        ))}
        {data.tour && unit && (
          <button className="v-btn apt-tour" onClick={() => void nui('tour', { unitId: unit.id })}><Icon name="eye" size="1rem" /> Tour Room {unit.number}</button>
        )}
      </section>

      <section className="apt-col apt-summary v-panel">
        <h3>{unit ? `Room ${unit.number}` : 'Your lease'}</h3>
        {!unit ? <p className="v-muted">Pick an available room to see the total.</p> : (
          <>
            <div className="apt-line"><span>First {type.intervalDays} days</span><span>{money(type.rent)}</span></div>
            <div className="apt-line"><span>Deposit (refundable)</span><span>{money(type.deposit)}</span></div>
            <div className="apt-line total"><span>Due today</span><span>{money(type.initial)}</span></div>
            <div className="apt-methods">
              <RadioCard label="Bank" active={method === 'bank'} onSelect={() => setMethod('bank')} disabled={busy} />
              <RadioCard label="Cash" active={method === 'cash'} onSelect={() => setMethod('cash')} disabled={busy} />
            </div>
            <div className={`v-muted apt-balance${short ? ' short' : ''}`}>{short ? 'Not enough money · ' : ''}Available: {money(balance)}</div>
            <label className="apt-check"><input type="checkbox" checked={autopay} onChange={(e) => setAutopay(e.target.checked)} /> Pay rent automatically from my bank</label>
            <details className="apt-terms" open>
              <summary>Lease terms</summary>
              <ul>{type.terms.map((t) => <li key={t}>{t}</li>)}</ul>
            </details>
            <label className="apt-check"><input type="checkbox" checked={agreed} onChange={(e) => setAgreed(e.target.checked)} /> I have read the terms</label>
            <button className="v-btn primary block" disabled={!agreed || short || busy || !data.canLease} onClick={() => setConfirm(true)}>
              {!data.canLease ? 'You already have a home' : `Sign lease · ${money(type.initial)}`}
            </button>
          </>
        )}
      </section>

      {confirm && unit && (
        <div className="v-dialog-backdrop" role="dialog" aria-modal="true" aria-label="Confirm lease">
          <div className="v-panel apt-confirm">
            <h3>Sign the lease for Room {unit.number}?</h3>
            <p>You pay <strong>{money(type.initial)}</strong> now from your {method === 'bank' ? 'bank account' : 'cash'}. Rent of <strong>{money(type.rent)}</strong> is due every {type.intervalDays} days{autopay ? ' and taken automatically' : ''}.</p>
            <div className="apt-row-end">
              <button className="v-btn" disabled={busy} onClick={() => setConfirm(false)}>Cancel</button>
              <button className="v-btn primary" disabled={busy} autoFocus onClick={() => void sign()}>{busy ? 'Processing…' : 'Sign & pay'}</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
