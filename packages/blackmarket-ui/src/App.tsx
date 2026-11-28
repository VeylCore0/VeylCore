import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { announceReady, nui, useNuiMessage, type NuiResponse } from '@veyl/ui';

interface Entry { item: string; label: string; description?: string; image?: string; price: number; category: string; stock: number; max: number; level: number; locked: boolean }
interface Category { id: string; label: string; icon: string }
interface View { id: string; label: string; categories: Category[]; items: Entry[]; cash: number; level: number | null; maxPerLine: number }

const api = <T,>(name: string, ...args: unknown[]) => nui<T>('api', { name, args }) as Promise<NuiResponse<T>>;
const usd = (n: number) => `$${Math.round(n).toLocaleString('en-US')}`;
const imageBase = () => (window as unknown as { __veylItemImages?: string }).__veylItemImages ?? 'nui://veyl_inventory/web/images';

const ICONS: Record<string, string[]> = {
  gun: ['M3 9h13l2 2h3v3h-4l-1 3h-4l-1-3H3z'],
  blade: ['M5 19L19 5', 'M14 5h5v5', 'M5 19l-1 1'],
  box: ['M21 8l-9-5-9 5 9 5 9-5z', 'M3 8v8l9 5 9-5V8', 'M12 13v8'],
  pill: ['M10.5 20.5a5 5 0 0 1-7-7l10-10a5 5 0 0 1 7 7z', 'M8.5 8.5l7 7'],
  flask: ['M9 3h6', 'M10 3v6l-5 9a2 2 0 0 0 2 3h10a2 2 0 0 0 2-3l-5-9V3', 'M7.5 14h9'],
  key: ['M21 2l-2 2m-7.6 7.6a5.5 5.5 0 1 1-7.8 7.8 5.5 5.5 0 0 1 7.8-7.8z', 'M15.5 7.5l3 3L22 7l-3-3'],
  chip: ['M7 7h10v10H7z', 'M9 3v4M15 3v4M9 17v4M15 17v4M3 9h4M3 15h4M17 9h4M17 15h4'],
  lock: ['M6 11V8a6 6 0 0 1 12 0v3', 'M5 11h14v10H5z'],
  all: ['M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z'],
  x: ['M18 6L6 18M6 6l12 12'],
  search: ['M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16z', 'M21 21l-4.3-4.3'],
  check: ['M20 6L9 17l-5-5'],
  alert: ['M12 3l10 18H2L12 3z', 'M12 10v5M12 18h.01'],
  money: ['M3 7h18v10H3z', 'M12 14a2 2 0 1 0 0-4 2 2 0 0 0 0 4z'],
};
function Ico({ name, size = 18 }: { name: string; size?: number }) {
  const d = ICONS[name] ?? ICONS.box;
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{d.map((p) => <path key={p} d={p} />)}</svg>;
}

function Img({ item, image, size }: { item: string; image?: string; size: number }) {
  const [bad, setBad] = useState(false);
  useEffect(() => setBad(false), [item]);
  if (bad) return <span className="bm-fb" style={{ width: size, height: size }}><Ico name="box" size={size * 0.5} /></span>;
  return <img src={`${imageBase()}/${image ?? item + ".png"}`} width={size} height={size} alt="" draggable={false} onError={() => setBad(true)} />;
}

export function App() {
  const [view, setView] = useState<View | null>(null);
  const [cat, setCat] = useState('all');
  const [query, setQuery] = useState('');
  const [sel, setSel] = useState<string | null>(null);
  const [qty, setQty] = useState(1);
  const [busy, setBusy] = useState(false);
  const [toast, setToast] = useState<{ ok: boolean; text: string } | null>(null);
  const timer = useRef<number>();
  useEffect(() => announceReady(), []);

  useNuiMessage<{ data: View }>('blackmarket:open', (d) => { setView(d.data); setCat('all'); setQuery(''); setSel(null); setQty(1); setToast(null); });
  useNuiMessage('blackmarket:close', () => setView(null));

  const close = useCallback(() => { void nui('close'); }, []);
  useEffect(() => {
    if (!view) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') close(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [view, close]);

  const say = (ok: boolean, text: string) => {
    setToast({ ok, text });
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setToast(null), 3200);
  };

  const refresh = useCallback(async () => {
    const r = await api<View>('view');
    if (r.ok && r.data) setView(r.data);
  }, []);

  const shown = useMemo(() => {
    if (!view) return [];
    const q = query.trim().toLowerCase();
    return view.items.filter((e) => (cat === 'all' || e.category === cat) && (!q || e.label.toLowerCase().includes(q)));
  }, [view, cat, query]);

  const entry = view?.items.find((e) => e.item === sel) ?? null;
  const maxQty = entry ? Math.max(1, Math.min(view?.maxPerLine ?? 50, entry.stock)) : 1;
  const total = entry ? entry.price * qty : 0;
  const can = !!entry && !entry.locked && entry.stock > 0 && total <= (view?.cash ?? 0) && !busy;

  const buy = async () => {
    if (!entry || !can) return;
    setBusy(true);
    const r = await api('buy', entry.item, qty);
    setBusy(false);
    say(r.ok, r.message ?? (r.ok ? 'Done' : 'That did not work'));
    await refresh();
    setQty(1);
  };

  if (!view) return null;
  const counts = (id: string) => (id === 'all' ? view.items.length : view.items.filter((e) => e.category === id).length);

  return (
    <div className="bm-root">
      <div className="bm-panel" role="application" aria-label="Black market">
        <nav className="bm-side" aria-label="Categories">
          <div className="bm-brand"><span className="bm-mark">V</span><div><b>{view.label}</b><i>NO QUESTIONS ASKED</i></div></div>
          {[{ id: 'all', label: 'Everything', icon: 'all' }, ...view.categories].map((c) => (
            <button key={c.id} className={`bm-cat${cat === c.id ? ' on' : ''}`} onClick={() => setCat(c.id)} aria-current={cat === c.id ? 'true' : undefined}>
              <Ico name={c.icon} size={17} />{c.label}<em>{counts(c.id)}</em>
            </button>
          ))}
          <div className="bm-wallet"><Ico name="money" size={18} /><div><small>CASH</small><b>{usd(view.cash)}</b></div></div>
        </nav>

        <main className="bm-main">
          <header className="bm-top">
            <label className="bm-search"><Ico name="search" size={16} /><input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search the stock" aria-label="Search" /></label>
            {view.level !== null && <span className="bm-rep" title="Your street reputation decides what he will sell you">Reputation {view.level}</span>}
            <button className="bm-close" onClick={close}><kbd>ESC</kbd>Close</button>
          </header>
          <div className="bm-grid" role="list">
            {shown.map((e) => (
              <button key={e.item} role="listitem" className={`bm-card${sel === e.item ? ' on' : ''}${e.locked ? ' locked' : ''}${e.stock <= 0 ? ' out' : ''}`} onClick={() => { setSel(e.item); setQty(1); }}>
                <Img item={e.item} image={e.image} size={64} />
                <b>{e.label}</b>
                <span className="bm-price">{usd(e.price)}</span>
                <small>{e.locked ? <><Ico name="lock" size={12} /> Needs rep {e.level}</> : e.stock <= 0 ? 'Sold out' : `${e.stock} in stock`}</small>
              </button>
            ))}
            {shown.length === 0 && <div className="bm-empty"><Ico name="search" size={26} /><strong>Nothing matches</strong><span>Try another category or search.</span></div>}
          </div>
        </main>

        <aside className="bm-detail" aria-label="Item">
          {entry ? (
            <>
              <div className="bm-hero"><Img item={entry.item} image={entry.image} size={120} /></div>
              <h2>{entry.label}</h2>
              <p>{entry.description ?? 'No questions asked.'}</p>
              <dl>
                <div><dt>Price</dt><dd>{usd(entry.price)}</dd></div>
                <div><dt>In stock</dt><dd>{entry.stock} / {entry.max}</dd></div>
                {entry.level > 0 && <div><dt>Reputation</dt><dd className={entry.locked ? 'bad' : ''}>{entry.level}</dd></div>}
              </dl>
              <div className="bm-qty" role="group" aria-label="Amount">
                <button onClick={() => setQty((q) => Math.max(1, q - 1))} aria-label="Less" disabled={qty <= 1}>−</button>
                <input type="number" min={1} max={maxQty} value={qty} onChange={(e) => setQty(Math.max(1, Math.min(maxQty, Math.floor(Number(e.target.value) || 1))))} aria-label="Quantity" />
                <button onClick={() => setQty((q) => Math.min(maxQty, q + 1))} aria-label="More" disabled={qty >= maxQty}>+</button>
                <button className="max" onClick={() => setQty(maxQty)}>Max</button>
              </div>
              <button className="bm-buy" disabled={!can} onClick={() => void buy()}>
                {entry.locked ? `Needs reputation ${entry.level}` : entry.stock <= 0 ? 'Sold out' : total > view.cash ? `Not enough cash (${usd(total)})` : busy ? 'Dealing…' : `Buy for ${usd(total)}`}
              </button>
            </>
          ) : (
            <div className="bm-empty tall"><Ico name="box" size={30} /><strong>Pick something</strong><span>Choose an item to see what it does and what it costs.</span></div>
          )}
        </aside>
        {toast && <div className={`bm-toast${toast.ok ? '' : ' err'}`} role="status"><Ico name={toast.ok ? 'check' : 'alert'} size={16} />{toast.text}</div>}
      </div>
    </div>
  );
}
