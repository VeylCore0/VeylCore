import { useCallback, useEffect, useState } from 'react';
import { Icon, nui } from '@veyl/ui';
import { api } from '../api';
import { AppHeader, usePhone } from '../App';


interface Place { id?: number; label: string; category?: string; x: number; y: number }
interface Shared { id: number; from_name: string; x: number; y: number; live: number; expires: number }
interface MapsData { saved: Place[]; shared: Shared[]; places: Place[]; shareMinutes: number[] }

export function MapsApp() {
  const { toast } = usePhone();
  const [data, setData] = useState<MapsData | null>(null);
  const [tab, setTab] = useState<'places' | 'saved' | 'shared'>('places');
  const [sharing, setSharing] = useState(false);
  const [naming, setNaming] = useState<string | null>(null);
  const load = useCallback(async () => {
    const r = await api<MapsData>('mapsData');
    if (r.ok && r.data) setData(r.data); else toast(r.message ?? 'Could not load maps', 'error');
  }, [toast]);
  useEffect(() => { void load(); }, [load]);

  const gps = (p: { x: number; y: number }, label: string) => { void nui('waypoint', { x: p.x, y: p.y }); toast(`GPS set: ${label}`); };
  const save = async () => {
    if (naming === null) return;
    const r = await api('placeSave', naming);
    toast(r.message ?? (r.ok ? 'Saved' : 'Could not save'), r.ok ? undefined : 'error');
    if (r.ok) { setNaming(null); void load(); }
  };

  if (sharing && data) return <Share minutes={data.shareMinutes} onBack={() => setSharing(false)} />;
  const cats = data ? [...new Set(data.places.map((p) => p.category ?? 'Places'))] : [];
  return (
    <div className="ph-appview">
      <AppHeader title="Maps" right={<button className="ph-icon-btn" aria-label="Share my location" onClick={() => setSharing(true)}><Icon name="share" size="1rem" /></button>} />
      <div className="ph-body">
        <div className="ph-seg">
          {(['places', 'saved', 'shared'] as const).map((t) => (
            <button key={t} className={tab === t ? 'on' : ''} onClick={() => setTab(t)}>
              {t === 'places' ? 'Places' : t === 'saved' ? 'Saved' : `Shared${data?.shared.length ? ` (${data.shared.length})` : ''}`}
            </button>
          ))}
        </div>
        {!data && <div className="ph-empty">Loading…</div>}
        {data && tab === 'places' && cats.map((c) => (
          <div key={c}>
            <div className="ph-section">{c}</div>
            <ul className="ph-list">
              {data.places.filter((p) => (p.category ?? 'Places') === c).map((p) => (
                <li key={p.label}><button className="ph-row" onClick={() => gps(p, p.label)}><Icon name="pin" size="1rem" /><span className="ph-row-main"><strong>{p.label}</strong></span><span className="muted">GPS</span></button></li>
              ))}
            </ul>
          </div>
        ))}
        {data && tab === 'saved' && (
          <>
            {naming === null
              ? <button className="ph-btn wide" onClick={() => setNaming('')}><Icon name="plus" size="0.9rem" /> Save where I am</button>
              : <div className="ph-inline"><input autoFocus maxLength={40} placeholder="Name this place" value={naming} onChange={(e) => setNaming(e.target.value)} /><button className="ph-btn" onClick={() => void save()}>Save</button></div>}
            {data.saved.length === 0 && <div className="ph-empty">No saved places yet.</div>}
            <ul className="ph-list">
              {data.saved.map((p) => (
                <li key={p.id} className="ph-row-wrap">
                  <button className="ph-row" onClick={() => gps(p, p.label)}><Icon name="star" size="1rem" /><span className="ph-row-main"><strong>{p.label}</strong></span></button>
                  <button className="ph-icon-btn" aria-label={`Delete ${p.label}`} onClick={async () => { await api('placeDelete', p.id); void load(); }}><Icon name="close" size="0.9rem" /></button>
                </li>
              ))}
            </ul>
          </>
        )}
        {data && tab === 'shared' && (
          <>
            {data.shared.length === 0 && <div className="ph-empty">Nobody is sharing a location with you.</div>}
            <ul className="ph-list">
              {data.shared.map((s) => (
                <li key={s.id}><button className="ph-row" onClick={() => gps(s, s.from_name)}>
                  <Icon name="user" size="1rem" />
                  <span className="ph-row-main"><strong>{s.from_name}</strong><span className="muted">{s.live ? 'Live location' : 'Location'} · {Math.max(0, Math.round((s.expires - Date.now() / 1000) / 60))} min left</span></span>
                  <span className="muted">GPS</span>
                </button></li>
              ))}
            </ul>
            <button className="ph-link" onClick={() => void load()}>Refresh</button>
          </>
        )}
      </div>
    </div>
  );
}

function Share({ minutes, onBack }: { minutes: number[]; onBack: () => void }) {
  const { toast } = usePhone();
  const [number, setNumber] = useState('');
  const [mins, setMins] = useState(minutes[0] ?? 15);
  const [live, setLive] = useState(true);
  const send = async () => {
    const r = await api('shareLocation', number, mins, live);
    toast(r.message ?? (r.ok ? 'Shared' : 'Could not share'), r.ok ? undefined : 'error');
    if (r.ok) onBack();
  };
  return (
    <div className="ph-appview">
      <AppHeader title="Share location" onBack={onBack} />
      <div className="ph-body ph-form">
        <label>Phone number<input inputMode="numeric" maxLength={12} placeholder="555-0123" value={number} onChange={(e) => setNumber(e.target.value)} /></label>
        <div className="ph-seg">{minutes.map((m) => <button key={m} className={mins === m ? 'on' : ''} onClick={() => setMins(m)}>{m} min</button>)}</div>
        <label className="ph-check"><input type="checkbox" checked={live} onChange={(e) => setLive(e.target.checked)} /> Live (follows you)</label>
        <button className="ph-btn wide" disabled={number.replace(/\D/g, '').length < 7} onClick={() => void send()}>Share</button>
      </div>
    </div>
  );
}
