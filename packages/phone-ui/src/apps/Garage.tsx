// Garage: every vehicle you own with condition, where it is, a waypoint to it, and paid valet delivery for parked cars.
import { useState } from 'react';
import { api, post } from '../api';
import { Ico } from '../icons';
import { Button, Empty, Header, Sheet, cx, say, toast } from '../ui';
import { Chip, Loaded, Meter, useLoad, usd } from './kit';

type Vehicle = { id: number; model: string; plate: string; name: string; brand?: string; state: 'out' | 'garaged' | 'impound'; fuel: number; engine: number; body: number; impoundFee: number; place?: string };
type Data = { vehicles: Vehicle[]; valetFee?: number };

/** Pictures come from veyl_vehicles (one <model>.webp per model); an icon stands in when there is none. */
const imageBase = () => (window as unknown as { __veylVehicleImages?: string }).__veylVehicleImages ?? 'nui://veyl_vehicles/web/images';
function Pic({ model }: { model: string }) {
  const [failed, setFailed] = useState(false);
  return (
    <span className="ph-carpic">
      {!failed && /^[a-z0-9_]+$/i.test(model) ? <img src={`${imageBase()}/${model.toLowerCase()}.webp`} alt="" onError={() => setFailed(true)} draggable={false} /> : <Ico name="car" size={34} stroke={1.5} />}
    </span>
  );
}

const STATE = {
  out: { label: 'Out on the road', tone: 'ok' as const, icon: 'nav' },
  garaged: { label: 'Parked', tone: 'accent' as const, icon: 'home' },
  impound: { label: 'Impounded', tone: 'bad' as const, icon: 'lock' },
};

export function GarageApp() {
  const load = useLoad(() => api<Data>('garageList'));
  const [busy, setBusy] = useState<number | null>(null);
  const [valet, setValet] = useState<Vehicle | null>(null);

  const locate = async (v: Vehicle) => {
    setBusy(v.id);
    const r = await api<{ x: number; y: number; label: string }>('garageLocate', v.id);
    setBusy(null);
    if (!r.ok || !r.data) return void say(r);
    await post('waypoint', { x: r.data.x, y: r.data.y });
    toast(`Waypoint set: ${r.data.label}`);
  };
  const callValet = async (v: Vehicle) => {
    setBusy(v.id);
    const spot = await post<{ x: number; y: number; z: number; h: number }>('valetSpot');
    if (!spot.ok || !spot.data) { setBusy(null); return void say(spot); }
    const r = await api<{ x: number; y: number }>('garageValet', v.id, spot.data);
    setBusy(null);
    if (say(r)) { setValet(null); void load.reload(); if (r.data) void post('waypoint', r.data); }
  };

  return (
    <div className="ph-app">
      <Header title="Garage" right={load.data ? <Chip icon="car">{load.data.vehicles.length}</Chip> : undefined} />
      <div className="ph-scroll ph-pad">
        <Loaded {...load}>
          {(d) => d.vehicles.length === 0
            ? <Empty icon="car" title="No vehicles yet" text="Buy one at the dealership and it will show up here." />
            : d.vehicles.map((v) => {
              const st = STATE[v.state] ?? STATE.garaged;
              return (
                <article key={v.id} className={cx('ph-vcard', v.state)}>
                  <Pic model={v.model} />
                  <div className="ph-vcard-main">
                    <div className="ph-vcard-top"><strong>{v.name}</strong>{v.brand && <em>{v.brand}</em>}</div>
                    <div className="ph-vcard-meta"><span className="ph-plate">{v.plate}</span><Chip tone={st.tone} icon={st.icon}>{st.label}</Chip></div>
                    {v.place && <span className="ph-sub"><Ico name="pin" size={12} /> {v.place}</span>}
                    {v.state === 'impound' && v.impoundFee > 0 && <span className="ph-sub danger">Release fee {usd(v.impoundFee)}</span>}
                    <div className="ph-vcard-bars"><Meter icon="fuel" value={v.fuel} label="Fuel" /><Meter icon="engine" value={v.engine} label="Engine" /><Meter icon="shield" value={v.body} label="Body" /></div>
                  </div>
                  <div className="ph-vcard-actions">
                    <button onClick={() => void locate(v)} disabled={busy === v.id} aria-label={`Locate ${v.name}`}><Ico name="nav" size={16} /> Locate</button>
                    {v.state === 'garaged' && <button className="primary" onClick={() => setValet(v)} disabled={busy === v.id} aria-label={`Valet ${v.name}`}><Ico name="car" size={16} /> Valet</button>}
                  </div>
                </article>
              );
            })}
        </Loaded>
      </div>
      {valet && (
        <Sheet title="Valet service" onClose={() => setValet(null)}>
          <div className="ph-form">
            <Pic model={valet.model} />
            <p className="ph-hint center">A driver brings your <b>{valet.name}</b> to the road next to you.</p>
            <div className="ph-fee"><span>Fee, from your bank</span><strong>{usd(load.data?.valetFee ?? 0)}</strong></div>
            <Button kind="primary" block onClick={() => void callValet(valet)} disabled={busy === valet.id}>{busy === valet.id ? 'Calling...' : 'Bring it to me'}</Button>
          </div>
        </Sheet>
      )}
    </div>
  );
}
