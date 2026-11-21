import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { BrandHeader, CloseHint, Icon, RadioCard, SearchBox, StateView, Tabs, announceReady, money, newOpId, nui, useNuiMessage } from '@veyl/ui';
import { REASONS, type DealerOpen, type DealerVehicle, type GarageOpen, type GarageVehicle, type Method } from './types';

type Toast = { kind: 'error' | 'success'; text: string } | null;

function useToast() {
  const [toast, setToast] = useState<Toast>(null);
  const timer = useRef<number>();
  const say = useCallback((kind: 'error' | 'success', text: string) => {
    setToast({ kind, text });
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setToast(null), 3800);
  }, []);
  return { toast, say };
}

/** Escape closes (or blurs a focused input first). */
function useEscape(active: boolean, onEscape: () => void) {
  useEffect(() => {
    if (!active) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      if ((e.target as HTMLElement).tagName === 'INPUT') (e.target as HTMLElement).blur(); else onEscape();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [active, onEscape]);
}

export function App() {
  const [garage, setGarage] = useState<GarageOpen | null>(null);
  const [dealer, setDealer] = useState<DealerOpen | null>(null);
  useEffect(() => announceReady(), []);
  useNuiMessage<GarageOpen>('garage:open', (d) => { setDealer(null); setGarage(d); });
  useNuiMessage<DealerOpen>('dealer:open', (d) => { setGarage(null); setDealer(d); });
  useNuiMessage('garage:close', () => setGarage(null));
  useNuiMessage('dealer:close', () => setDealer(null));
  if (garage) return <GarageScreen data={garage} />;
  if (dealer) return <DealerScreen data={dealer} />;
  return null;
}

// ---------------------------------------------------------------------------
// Garage / impound
// ---------------------------------------------------------------------------
function Bar({ label, value, icon }: { label: string; value: number; icon: string }) {
  const tone = value < 25 ? 'danger' : value < 50 ? 'warn' : '';
  return (
    <div className={`vh-bar ${tone}`} title={`${label} ${value}%`}>
      <Icon name={icon} size="0.85rem" />
      <div className="track"><span style={{ width: `${Math.max(0, Math.min(100, value))}%` }} /></div>
      <span className="pct">{value}%</span>
    </div>
  );
}

function statusOf(v: GarageVehicle, impound: boolean): { text: string; tone: string } {
  if (v.state === 'impound') return { text: impound ? `Impounded · ${money(v.impoundFee)}` : 'At the impound lot', tone: 'danger' };
  if (v.state === 'out') return { text: 'Out on the road', tone: 'muted' };
  if (v.here) return { text: impound ? 'Paid · ready' : 'In this garage', tone: 'success' };
  return { text: `At ${v.garageLabel ?? v.garage ?? 'another garage'}`, tone: 'muted' };
}

function GarageScreen({ data }: { data: GarageOpen }) {
  const impound = data.kind === 'impound';
  const [tab, setTab] = useState<'here' | 'all'>('here');
  const [search, setSearch] = useState('');
  const [method, setMethod] = useState<Method>(data.methods[0] ?? 'cash');
  const [busy, setBusy] = useState<number | null>(null);
  const [retry, setRetry] = useState<{ id: number; op: string } | null>(null);
  const { toast, say } = useToast();
  const close = useCallback(() => { void nui('close'); }, []);
  useEscape(true, close);

  const here = data.vehicles.filter((v) => v.here);
  const list = useMemo(() => {
    const q = search.trim().toLowerCase();
    return (tab === 'here' ? here : data.vehicles).filter((v) => !q || `${v.name} ${v.brand ?? ''} ${v.plate}`.toLowerCase().includes(q));
  }, [tab, here, data.vehicles, search]);

  const takeOut = async (v: GarageVehicle) => {
    if (busy) return;
    setBusy(v.id);
    const op = retry?.id === v.id ? retry.op : newOpId(); // a retried release reuses its operation id: never charged twice
    const res = await nui('takeOut', { ownedId: v.id, method, opId: op });
    setBusy(null);
    if (res.ok) return; // Lua closes the screen and shows the result
    if (res.code === 'PENDING' || res.code === 'TIMEOUT') setRetry({ id: v.id, op }); else setRetry(null);
    say('error', res.message ?? res.code ?? 'Could not take the vehicle out');
  };

  const balance = data.balances[method];

  return (
    <div className="vh-root">
      <header className="vh-header">
        <BrandHeader section={impound ? 'Impound' : 'Garage'} />
        <CloseHint onClose={close} />
      </header>
      <main className="vh-garage v-panel">
        <div className="vh-title-row">
          <div>
            <div className="vh-title">{data.title.toUpperCase()}</div>
            <div className="v-muted">{impound ? 'Pay the release fee to get your vehicle back.' : 'Take a vehicle out, or park one with the target option nearby.'}</div>
          </div>
          <Icon name={impound ? 'lock' : 'garage'} size="2rem" />
        </div>
        <div className="vh-filters">
          <Tabs tabs={[{ id: 'here', label: `${impound ? 'Impounded' : 'In this garage'} (${here.length})` }, { id: 'all', label: `All my vehicles (${data.vehicles.length})` }]}
            value={tab} onChange={setTab} />
          <div className="vh-search"><SearchBox value={search} onChange={setSearch} placeholder="Search name or plate…" /></div>
        </div>
        <div className="vh-list v-scroll">
          {list.length === 0 && <StateView kind="empty" message={tab === 'here' ? (impound ? 'None of your vehicles are impounded.' : 'No vehicles parked here.') : 'You do not own any vehicles yet.'} />}
          {list.map((v) => {
            const st = statusOf(v, impound);
            const fee = impound && v.state === 'impound' ? v.impoundFee : 0;
            const short = fee > balance;
            return (
              <div key={v.id} className={`vh-row${v.here ? '' : ' away'}`}>
                <div className="vh-icon"><Icon name="car" size="1.6rem" /></div>
                <div className="vh-main">
                  <div className="vh-name">{v.name} {v.brand && <span className="v-muted">{v.brand}</span>}</div>
                  <div className="vh-meta">
                    <span className="vh-plate">{v.plate}</span>
                    <span className={`vh-status ${st.tone}`}>{st.text}</span>
                    {v.state === 'impound' && v.impoundReason && <span className="v-muted">{REASONS[v.impoundReason] ?? v.impoundReason}</span>}
                  </div>
                </div>
                <div className="vh-bars">
                  <Bar label="Fuel" value={v.fuel} icon="fuel" />
                  <Bar label="Engine" value={v.engine} icon="engine" />
                  <Bar label="Body" value={v.body} icon="car" />
                </div>
                <div className="vh-action">
                  {v.here ? (
                    <button className="v-btn primary" disabled={busy !== null || short} title={short ? 'Not enough money' : undefined} onClick={() => void takeOut(v)}>
                      {busy === v.id ? 'Working…' : fee > 0 ? `PAY ${money(fee)}` : impound ? 'RELEASE' : 'TAKE OUT'}
                    </button>
                  ) : <span className="v-muted vh-hint">{v.state === 'out' ? 'Park it first' : v.state === 'impound' ? 'Collect at the impound lot' : 'Collect at its garage'}</span>}
                </div>
              </div>
            );
          })}
        </div>
        {impound && here.some((v) => v.state === 'impound' && v.impoundFee > 0) && (
          <div className="vh-pay">
            <div className="vh-methods" role="radiogroup">
              {(['cash', 'bank'] as Method[]).map((m) => (
                <RadioCard key={m} label={m === 'cash' ? 'Cash' : 'Bank'} active={method === m} disabled={!data.methods.includes(m) || busy !== null} onSelect={() => setMethod(m)} />
              ))}
            </div>
            <span className="v-muted">Available: {money(balance)}</span>
          </div>
        )}
      </main>
      {toast && <div className={`v-toast-inline ${toast.kind}`} role="alert"><Icon name={toast.kind === 'error' ? 'alert' : 'check'} size="1rem" />{toast.text}</div>}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Dealership
// ---------------------------------------------------------------------------
function DealerScreen({ data }: { data: DealerOpen }) {
  const [category, setCategory] = useState('all');
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<DealerVehicle | null>(null);
  const [method, setMethod] = useState<Method>(data.methods.includes('bank') ? 'bank' : data.methods[0] ?? 'cash');
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  const [retryOp, setRetryOp] = useState<string | null>(null);
  const [catalog, setCatalog] = useState(data.vehicles);
  const { toast, say } = useToast();
  const close = useCallback(() => { if (confirm) setConfirm(false); else void nui('close'); }, [confirm]);
  useEscape(true, close);

  const cats = useMemo(() => [{ id: 'all', label: 'All' }, ...data.categories.filter((c) => catalog.some((v) => v.category === c.id))], [data.categories, catalog]);
  const list = useMemo(() => {
    const q = search.trim().toLowerCase();
    return catalog.filter((v) => (category === 'all' || v.category === category) && (!q || `${v.name} ${v.brand ?? ''}`.toLowerCase().includes(q)));
  }, [catalog, category, search]);
  const catLabel = (id: string) => data.categories.find((c) => c.id === id)?.label ?? id;
  const balance = data.balances[method];

  const buy = async () => {
    if (!selected || busy) return;
    setBusy(true);
    const opId = retryOp ?? newOpId();
    const res = await nui<{ price?: number }>('purchase', { model: selected.model, method, opId, expectedPrice: selected.price });
    setBusy(false);
    if (res.ok) return; // Lua closes the screen and announces delivery
    if (res.code === 'PENDING' || res.code === 'TIMEOUT') { setRetryOp(opId); say('error', res.message ?? 'Payment is being verified. Press Buy again.'); return; }
    setRetryOp(null);
    setConfirm(false);
    if (res.code === 'PRICE_CHANGED' && res.data?.price) {
      const price = res.data.price;
      setCatalog((c) => c.map((v) => (v.model === selected.model ? { ...v, price } : v)));
      setSelected({ ...selected, price });
    }
    say('error', res.message ?? res.code ?? 'Purchase failed');
  };

  return (
    <div className="vh-root">
      <header className="vh-header">
        <BrandHeader section="Dealership" />
        <CloseHint onClose={close} />
      </header>
      <main className="vh-dealer">
        <section className="vh-catalog v-panel">
          <div className="vh-title">{data.title.toUpperCase()}</div>
          <div className="v-muted">{data.subtitle}</div>
          <div className="vh-filters">
            <Tabs tabs={cats} value={category} onChange={setCategory} />
            <div className="vh-search"><SearchBox value={search} onChange={setSearch} placeholder="Search vehicles…" /></div>
          </div>
          <div className="vh-grid v-scroll">
            {list.length === 0 && <StateView kind="empty" message="No vehicles match." />}
            {list.map((v) => (
              <button key={v.model} className={`vh-card${selected?.model === v.model ? ' on' : ''}`} onClick={() => { setSelected(v); setRetryOp(null); }}>
                <div className="vh-card-icon"><Icon name={v.category === 'motorcycles' ? 'bolt' : 'car'} size="2.2rem" /></div>
                <div className="vh-card-name">{v.name}</div>
                <div className="v-muted vh-card-brand">{[v.brand, catLabel(v.category)].filter(Boolean).join(' · ')}</div>
                <div className="vh-card-price">{money(v.price)}</div>
              </button>
            ))}
          </div>
        </section>
        <aside className="vh-detail v-panel">
          {!selected ? (
            <div className="vh-detail-empty"><Icon name="tag" size="2rem" /><span className="v-muted">Choose a vehicle to see the price and buy it.</span></div>
          ) : (
            <>
              <div className="vh-title">{selected.name.toUpperCase()}</div>
              <div className="v-muted">{[selected.brand, catLabel(selected.category)].filter(Boolean).join(' · ')}</div>
              <div className="vh-detail-hero"><Icon name={selected.category === 'motorcycles' ? 'bolt' : 'car'} size="5rem" strokeWidth={1.1} /></div>
              <ul className="vh-facts">
                <li><Icon name="check" size="0.95rem" /> Registered to you with its own plate</li>
                <li><Icon name="check" size="0.95rem" /> Keys included</li>
                <li><Icon name="check" size="0.95rem" /> Delivered outside, or parked at your garage if the bay is busy</li>
              </ul>
              <div className="vh-total"><span>Price</span><span>{money(selected.price)}</span></div>
              <div className="vh-methods" role="radiogroup">
                {(['cash', 'bank'] as Method[]).map((m) => (
                  <RadioCard key={m} label={m === 'cash' ? 'Cash' : 'Bank'} active={method === m} disabled={!data.methods.includes(m) || busy} onSelect={() => setMethod(m)} />
                ))}
              </div>
              <div className={`v-muted vh-available${balance < selected.price ? ' short' : ''}`}>
                {balance < selected.price ? 'Not enough money · ' : ''}Available: {money(balance)}
              </div>
              <button className="v-btn primary block vh-buy" disabled={busy || balance < selected.price} onClick={() => setConfirm(true)}>BUY</button>
            </>
          )}
        </aside>
      </main>
      {confirm && selected && (
        <div className="v-dialog-backdrop" role="dialog" aria-modal="true" aria-label="Confirm purchase">
          <div className="v-panel vh-confirm">
            <div className="vh-title">CONFIRM PURCHASE</div>
            <p>Buy the <strong>{[selected.brand, selected.name].filter(Boolean).join(' ')}</strong> for <strong>{money(selected.price)}</strong> from your {method === 'bank' ? 'bank account' : 'cash'}?</p>
            <div className="vh-confirm-row">
              <button className="v-btn" disabled={busy} onClick={() => setConfirm(false)}>Cancel</button>
              <button className="v-btn primary" disabled={busy} autoFocus onClick={() => void buy()}>{busy ? 'Processing…' : `Pay ${money(selected.price)}`}</button>
            </div>
          </div>
        </div>
      )}
      {toast && <div className={`v-toast-inline ${toast.kind}`} role="alert"><Icon name={toast.kind === 'error' ? 'alert' : 'check'} size="1rem" />{toast.text}</div>}
    </div>
  );
}
