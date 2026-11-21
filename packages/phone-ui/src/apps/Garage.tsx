import { useCallback, useEffect, useState } from 'react';
import { Icon, nui } from '@veyl/ui';
import { api } from '../api';
import { AppHeader, usePhone } from '../App';

interface Vehicle { id: number; model: string; plate: string; name: string; brand?: string; state: 'out' | 'garaged' | 'impound'; fuel: number; engine: number; body: number; impoundFee: number; place?: string }

/** Picture from veyl_vehicles (one <model>.webp per model); falls back to an icon. */
const imageBase = () => (window as unknown as { __veylVehicleImages?: string }).__veylVehicleImages ?? 'nui://veyl_vehicles/web/images';
function Pic({ model }: { model: string }) {
  const [failed, setFailed] = useState(false);
  return <span className="gr-pic">{!failed && /^[a-z0-9_]+$/i.test(model) ? <img src={`${imageBase()}/${model.toLowerCase()}.webp`} alt="" onError={() => setFailed(true)} /> : <Icon name="car" size="1.6rem" />}</span>;
}
const STATE: Record<Vehicle['state'], { label: string; tone: string }> = {
  out: { label: 'Out on the road', tone: 'ok' }, garaged: { label: 'Parked', tone: '' }, impound: { label: 'Impounded', tone: 'bad' },
};
function Meter({ icon, value }: { icon: string; value: number }) {
  return <span className={`gr-meter${value < 25 ? ' bad' : value < 50 ? ' warn' : ''}`}><Icon name={icon} size="0.75rem" /><i><b style={{ width: `${Math.max(0, Math.min(100, value))}%` }} /></i></span>;
}

export function GarageApp() {
  const { toast } = usePhone();
  const [items, setItems] = useState<Vehicle[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<number | null>(null);
  const load = useCallback(async () => {
    const r = await api<{ vehicles: Vehicle[] }>('garageList');
    if (r.ok && r.data) { setItems(r.data.vehicles); setError(null); } else setError(r.message ?? 'Could not load your vehicles');
  }, []);
  useEffect(() => { void load(); }, [load]);
  const locate = async (v: Vehicle) => {
    setBusy(v.id);
    const r = await api<{ x: number; y: number; label: string }>('garageLocate', v.id);
    setBusy(null);
    if (!r.ok || !r.data) { toast(r.message ?? 'Location unavailable', 'error'); return; }
    await nui('waypoint', { x: r.data.x, y: r.data.y });
    toast(`Waypoint set: ${r.data.label}`);
  };
  return (
    <div className="ph-appview">
      <AppHeader title="Garage" right={<button className="ph-icon-btn" aria-label="Refresh" onClick={() => void load()}><Icon name="rotate_left" size="1rem" /></button>} />
      <div className="ph-body">
        {error && <div className="ph-empty">{error}<br /><button className="ph-link" onClick={() => void load()}>Retry</button></div>}
        {!error && items === null && <div className="ph-empty">Loading…</div>}
        {items?.length === 0 && <div className="ph-empty">You do not own any vehicles yet. Visit Premium Deluxe Motorsport.</div>}
        {items?.map((v) => (
          <div key={v.id} className="gr-card">
            <Pic model={v.model} />
            <div className="gr-info">
              <div className="gr-name">{v.name} {v.brand && <span className="muted">{v.brand}</span>}</div>
              <div className="gr-line"><span className="gr-plate">{v.plate}</span><span className={`gr-state ${STATE[v.state]?.tone ?? ''}`}>{STATE[v.state]?.label ?? v.state}</span></div>
              <div className="muted gr-place">{v.state === 'out' ? 'Live location available' : v.place ?? 'Unknown location'}{v.state === 'impound' && v.impoundFee > 0 ? ` · $${v.impoundFee} fee` : ''}</div>
              <div className="gr-meters"><Meter icon="fuel" value={v.fuel} /><Meter icon="engine" value={v.engine} /><Meter icon="car" value={v.body} /></div>
            </div>
            <button className="ph-icon-btn gr-go" disabled={busy !== null} aria-label={`Set waypoint to ${v.name}`} onClick={() => void locate(v)}><Icon name="pin" size="1.1rem" /></button>
          </div>
        ))}
        {items && items.length > 0 && <div className="ph-help">Take vehicles out and park them at a garage. Tap the pin to set a waypoint.</div>}
      </div>
    </div>
  );
}
