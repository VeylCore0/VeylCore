import { useEffect, useMemo, useState } from 'react';
import type { Category, Def } from './types';

export interface ShopProduct { index: number; item: string; label: string; price: number; category: string; image?: string; stock?: number | null }
export interface ShopInfo {
  shopId: string; title: string; subtitle?: string; categories: Category[]; products: ShopProduct[]; methods: ('cash' | 'bank')[];
  balances: { cash: number; bank: number }; maxPerLine: number; imagePath?: string;
}

const money = (n: number) => '$' + Math.round(n).toLocaleString('en-US');

/** A shop shown in the storage column. The server decides prices, stock, licences and money; this lists them and asks to buy. */
export function ShopPanel(props: { shop: ShopInfo; defs: Record<string, Def>; imagePath: string; busy: boolean; onBuy: (p: ShopProduct, count: number, method: 'cash' | 'bank') => void; matches: (label: string) => boolean }) {
  const { shop } = props;
  const [cat, setCat] = useState('all');
  const [sel, setSel] = useState<number | null>(null);
  const [count, setCount] = useState(1);
  const [method, setMethod] = useState<'cash' | 'bank'>(shop.methods[0] ?? 'cash');
  useEffect(() => { setSel(null); setCount(1); setCat('all'); setMethod(shop.methods[0] ?? 'cash'); }, [shop.shopId]);
  const list = useMemo(() => shop.products.filter((p) => cat === 'all' || p.category === cat), [shop.products, cat]);
  const chosen = shop.products.find((p) => p.index === sel);
  const max = Math.max(1, Math.min(shop.maxPerLine || 20, chosen?.stock ?? 99));
  const total = chosen ? chosen.price * count : 0;
  const can = chosen && total <= shop.balances[method] && (chosen.stock == null || chosen.stock >= count);
  const cats = [{ id: 'all', label: 'All' }, ...shop.categories];
  return (
    <section className="ipanel side-panel shop-panel" aria-label={shop.title}>
      <header className="ipanel-head">
        <span className="idiamond"><svg viewBox="0 0 24 24"><path d="M5 8h14l-1.2 11H6.2zM9 8V6a3 3 0 0 1 6 0v2" /></svg></span>
        <div><h3>{shop.title}</h3><p>{shop.subtitle || 'Buy something'}</p></div>
        <div className="shop-bal"><span>Cash <b>{money(shop.balances.cash)}</b></span><span>Bank <b>{money(shop.balances.bank)}</b></span></div>
      </header>
      {shop.categories.length > 0 && (
        <div className="ichips">{cats.map((c) => <button key={c.id} className={`ichip${cat === c.id ? ' on' : ''}`} onClick={() => setCat(c.id)}>{c.label}</button>)}</div>
      )}
      <div className="grid-scroll tall">
        <div className="grid" style={{ ['--cols' as string]: 4 }}>
          {list.map((p) => (
            <div key={p.index} className={`slot filled product${sel === p.index ? ' sel' : ''}${props.matches(p.label) ? '' : ' dim'}${p.stock === 0 ? ' sold' : ''}`}
              title={p.label} onClick={() => { setSel(p.index); setCount(1); }} onDoubleClick={() => p.stock !== 0 && props.onBuy(p, 1, method)}>
              <span className="slot-count price">{money(p.price)}</span>
              <img className="slot-img" draggable={false} src={`${props.imagePath}/${p.image ?? p.item + '.png'}`} alt={p.label} onError={(e) => { (e.target as HTMLImageElement).style.visibility = 'hidden'; }} />
              <span className="product-name">{p.label}</span>
            </div>
          ))}
        </div>
      </div>
      <div className="buybar">
        {chosen ? (
          <>
            <div className="buy-name"><strong>{chosen.label}</strong><em>{money(chosen.price)} each</em></div>
            <div className="stepper"><button onClick={() => setCount((c) => Math.max(1, c - 1))} aria-label="Less">−</button><b>{count}</b><button onClick={() => setCount((c) => Math.min(max, c + 1))} aria-label="More">+</button></div>
            {shop.methods.length > 1 && (
              <div className="methods">{shop.methods.map((m) => <button key={m} className={`ichip${method === m ? ' on' : ''}`} onClick={() => setMethod(m)}>{m === 'cash' ? 'Cash' : 'Bank'}</button>)}</div>
            )}
            <button className="buy-btn" disabled={!can || props.busy} onClick={() => props.onBuy(chosen, count, method)}>{can ? `Buy ${money(total)}` : total > shop.balances[method] ? `Need ${money(total - shop.balances[method])} more` : 'Out of stock'}</button>
          </>
        ) : <span className="buy-hint">Pick something to buy. Double-click buys one.</span>}
      </div>
    </section>
  );
}
