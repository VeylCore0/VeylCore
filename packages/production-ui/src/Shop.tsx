import { useState } from 'react';
import type { ShopView } from './types';
import { Bar, Button, Chip, Ico, ItemImg, usd } from './ui';

/** The supply shop (buy) and the buyer (sell). Prices, stock and quality values are the server's; this only asks. */
export function Shop({ view, mode, run }: { view: ShopView; mode: 'shop' | 'buyer'; run: (name: string, ...a: unknown[]) => Promise<{ ok: boolean }> }) {
  const [qty, setQty] = useState<Record<string, number>>({});
  const q = (k: string) => Math.max(1, qty[k] ?? 1);
  const set = (k: string, v: number) => setQty((s) => ({ ...s, [k]: Math.max(1, Math.min(99, v)) }));
  const Stepper = ({ k }: { k: string }) => (
    <span className="pr-stepper"><button className="pr-step" onClick={() => set(k, q(k) - 1)} aria-label="Less">−</button><b>{q(k)}</b><button className="pr-step" onClick={() => set(k, q(k) + 1)} aria-label="More">+</button></span>
  );
  return (
    <div className="pr-page">
      <div className="pr-page-head"><div><h2>{mode === 'shop' ? (view.label ?? 'Supply Shop') : 'Buyer'}</h2><p>{mode === 'shop' ? (view.unlimited ? 'Always in stock.' : `Stock refills every ${view.restockMinutes} minutes.`) : 'Pays cash. Better quality pays more.'}</p></div></div>
      {mode === 'shop' ? (
        <div className="pr-shopgrid">
          {view.items.map((i) => {
            const out = !view.unlimited && i.stock === 0;
            const low = !view.unlimited && i.stock > 0 && i.stock / i.max < 0.25;
            return (
              <article key={i.item} className={i.locked || out ? 'pr-shopitem locked' : 'pr-shopitem'}>
                <div className="pr-halo"><ItemImg item={i.item} size={64} /></div>
                <strong>{i.label}</strong>
                <div className="pr-price">{usd(i.price)}</div>
                {!view.unlimited && <Bar value={i.stock / i.max} color={i.stock === 0 ? '#e0576a' : low ? '#f2b443' : undefined} label="Stock" />}
                <span className={low || out ? 'pr-sub warn' : 'pr-sub'}>{view.unlimited ? 'In stock' : i.stock === 0 ? 'Sold out' : low ? `Only ${i.stock} left` : `${i.stock} in stock`}</span>
                {i.locked ? <Chip tone="warn"><Ico name="lock" size={12} />Level {i.level}</Chip> : (
                  <div className="pr-buyrow"><Stepper k={i.item} /><Button kind="primary" disabled={out} onClick={() => void run('shopBuy', view.id, i.item, q(i.item))}>Buy</Button></div>
                )}
              </article>
            );
          })}
        </div>
      ) : (
        <>
          <ul className="pr-sellist">
            {view.sell.map((s) => (
              <li key={s.item}>
                <div className="pr-halo sm"><ItemImg item={s.item} size={44} /></div>
                <span className="pr-sell-main"><strong>{s.label}</strong><em>{usd(s.price ?? s.base)} each now{s.trend && s.trend !== 'steady' ? (s.trend === 'high' ? ', demand is high' : ', market is flooded') : ''}, × quality</em></span>
                <Stepper k={s.item} />
                <Button kind="primary" onClick={() => void run('shopSell', s.item, q(s.item))}>Sell</Button>
              </li>
            ))}
          </ul>
          <h4 className="pr-h">QUALITY PAYS</h4>
          <div className="pr-tiers">{view.quality.map((t, i) => <span key={t.label} style={{ ['--tier' as string]: ['#9aa6a1', '#4aa8ff', '#5fd68c', '#c58bff', '#f2b443'][i] }}><i />{t.label}<b>×{t.mult.toFixed(1)}</b></span>)}</div>
        </>
      )}
    </div>
  );
}
