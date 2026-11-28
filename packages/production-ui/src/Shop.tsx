import { useState } from 'react';
import type { ShopView } from './types';
import { Bar, Button, Chip, Ico, ItemImg, usd } from './ui';

/** The supply shop (buy) and the buyer (sell). Prices, stock and quality values are the server's; this only asks. */
export function Shop({ view, mode, run }: { view: ShopView; mode: 'shop' | 'buyer'; run: (name: string, ...a: unknown[]) => Promise<{ ok: boolean }> }) {
  const [qty, setQty] = useState<Record<string, number>>({});
  const q = (k: string) => Math.max(1, qty[k] ?? 1);
  const set = (k: string, v: number) => setQty((s) => ({ ...s, [k]: Math.max(1, Math.min(99, v)) }));
  return (
    <div className="pr-page">
      <div className="pr-page-head"><div><h2>{mode === 'shop' ? 'Supply Shop' : 'Buyer'}</h2><p>{mode === 'shop' ? `Stock refills every ${view.restockMinutes} minutes.` : 'Pays cash. Better quality pays more.'}</p></div></div>
      {mode === 'shop' ? (
        <div className="pr-shopgrid">
          {view.items.map((i) => (
            <article key={i.item} className={i.locked || i.stock === 0 ? 'pr-shopitem locked' : 'pr-shopitem'}>
              <ItemImg item={i.item} size={56} />
              <strong>{i.label}</strong>
              <div className="pr-price">{usd(i.price)}</div>
              <Bar value={i.stock / i.max} label="Stock" />
              <span className="pr-sub">{i.stock} in stock</span>
              {i.locked ? <Chip tone="warn"><Ico name="lock" size={12} />Level {i.level}</Chip> : (
                <div className="pr-buyrow">
                  <button className="pr-step" onClick={() => set(i.item, q(i.item) - 1)} aria-label="Less">−</button>
                  <b>{q(i.item)}</b>
                  <button className="pr-step" onClick={() => set(i.item, q(i.item) + 1)} aria-label="More">+</button>
                  <Button kind="primary" disabled={i.stock === 0} onClick={() => void run('shopBuy', i.item, q(i.item))}>Buy</Button>
                </div>
              )}
            </article>
          ))}
        </div>
      ) : (
        <>
          <ul className="pr-sellist">
            {view.sell.map((s) => (
              <li key={s.item}>
                <ItemImg item={s.item} size={44} />
                <span className="pr-sell-main"><strong>{s.label}</strong><em>Base {usd(s.base)} each, × quality</em></span>
                <button className="pr-step" onClick={() => set(s.item, q(s.item) - 1)} aria-label="Less">−</button><b>{q(s.item)}</b><button className="pr-step" onClick={() => set(s.item, q(s.item) + 1)} aria-label="More">+</button>
                <Button kind="primary" onClick={() => void run('shopSell', s.item, q(s.item))}>Sell</Button>
              </li>
            ))}
          </ul>
          <h4 className="pr-h">QUALITY PAYS</h4>
          <div className="pr-tiers">{view.quality.map((t) => <span key={t.label}><b>{t.label}</b>×{t.mult.toFixed(1)}</span>)}</div>
        </>
      )}
    </div>
  );
}
