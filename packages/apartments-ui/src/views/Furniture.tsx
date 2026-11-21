import { useMemo, useState } from 'react';
import { Icon, SearchBox, StateView, money, nui } from '@veyl/ui';
import { FloorPlan } from './FloorPlan';
import { api, type FurnitureCatalog, type Piece } from '../types';

type Say = (k: 'ok' | 'error', t: string) => void;

export function FurnitureView({ initial, toast }: { initial: FurnitureCatalog; toast: Say }) {
  const [data, setData] = useState(initial);
  const [cat, setCat] = useState('all');
  const [search, setSearch] = useState('');
  const [busy, setBusy] = useState(false);
  const missing = useMemo(() => new Set(data.missing), [data.missing]);
  const full = data.placed >= data.limit;
  const items = data.items.filter((i) => (cat === 'all' || i.category === cat) && (!search.trim() || i.label.toLowerCase().includes(search.trim().toLowerCase())));

  const refresh = async () => {
    const r = await api<FurnitureCatalog>('furnitureCatalog');
    if (r.ok && r.data) setData({ ...r.data, placedList: data.placedList, missing: data.missing });
  };
  const run = async (name: string, p: Piece) => {
    setBusy(true);
    const r = await api(name, p.id);
    setBusy(false);
    toast(r.ok ? 'ok' : 'error', r.message ?? (r.ok ? 'Done' : 'Failed'));
    if (r.ok) {
      setData((d) => ({ ...d, placedList: d.placedList.filter((x) => x.id !== p.id || name === 'furnitureStore'), placed: name === 'furnitureStore' ? d.placed - 1 : d.placed }));
      await refresh();
    }
  };

  if (!data.canEdit) return <StateView kind="restricted" message="You cannot change the furniture in this home." />;

  return (
    <div className="apt-furn">
      <aside className="apt-furn-side">
        <div className="apt-card">
          <div className="apt-card-title"><Icon name="home" size="1rem" /> This room</div>
          <FloorPlan compact pieces={data.placedList.map((p) => ({ x: p.x, y: p.y, label: p.label }))} />
          <div className={`apt-meter${full ? ' full' : ''}`}><i style={{ width: `${Math.min(100, (data.placed / Math.max(1, data.limit)) * 100)}%` }} /></div>
          <div className="v-muted small">{data.placed} of {data.limit} pieces placed · bank {money(data.balances.bank)}</div>
        </div>
        <div className="apt-card">
          <div className="apt-card-title"><Icon name="box" size="1rem" /> In storage</div>
          {data.stored.length === 0 && <p className="v-muted small">Stored pieces appear here.</p>}
          {data.stored.map((p) => (
            <div key={p.id} className="apt-piece">
              <span>{p.label}</span>
              <button className="v-btn" disabled={busy || full} onClick={() => void nui('startPlacement', { id: p.id, model: p.model })}>Place</button>
              {p.mine && <button className="v-btn" disabled={busy} onClick={() => void run('furnitureSell', p)}>Sell {money(Math.floor(p.price * data.sellRate))}</button>}
            </div>
          ))}
        </div>
        <div className="apt-card">
          <div className="apt-card-title"><Icon name="edit" size="1rem" /> Placed</div>
          {data.placedList.length === 0 && <p className="v-muted small">Nothing placed yet.</p>}
          {data.placedList.map((p) => (
            <div key={p.id} className="apt-piece">
              <span>{p.label}</span>
              <button className="v-btn" disabled={busy} onClick={() => void nui('startPlacement', { move: p.id })}>Move</button>
              <button className="v-btn" disabled={busy} onClick={() => void run('furnitureStore', p)}>Store</button>
            </div>
          ))}
        </div>
      </aside>
      <section className="apt-furn-main">
        <div className="apt-furn-filters">
          <div className="apt-chips">
            <button className={`apt-chip${cat === 'all' ? ' on' : ''}`} onClick={() => setCat('all')}>All</button>
            {data.categories.map((c) => <button key={c.id} className={`apt-chip${cat === c.id ? ' on' : ''}`} onClick={() => setCat(c.id)}>{c.label}</button>)}
          </div>
          <SearchBox value={search} onChange={setSearch} placeholder="Search furniture…" />
        </div>
        <div className="apt-catalog v-scroll">
          {items.length === 0 && <StateView kind="empty" message="Nothing matches." />}
          {items.map((i) => {
            const unavailable = missing.has(i.key);
            const tooExpensive = data.balances.bank < i.price;
            return (
              <div key={i.key} className={`apt-item${unavailable ? ' off' : ''}`}>
                <div className="apt-item-icon"><Icon name={({ seating: 'home', beds: 'moon', tables: 'box', storage: 'box', lighting: 'sun', kitchen: 'drop', electronics: 'bolt', decor: 'leaf' } as Record<string, string>)[i.category] ?? 'box'} size="1.6rem" /></div>
                <div className="apt-item-name">{i.label}</div>
                <div className="apt-item-price">{money(i.price)}</div>
                <button className="v-btn primary" disabled={unavailable || full || tooExpensive}
                  title={unavailable ? 'Not available on this game version' : full ? 'Furniture limit reached' : tooExpensive ? 'Not enough money in your bank' : 'Preview and place; you pay only when you confirm'}
                  onClick={() => void nui('startPlacement', { item: i.key })}>{unavailable ? 'Unavailable' : full ? 'Limit reached' : 'Preview & place'}</button>
              </div>
            );
          })}
        </div>
        <div className="apt-hint v-muted small">You only pay when you confirm a valid spot. Pieces you buy are yours: they move with you if you leave.</div>
      </section>
    </div>
  );
}
