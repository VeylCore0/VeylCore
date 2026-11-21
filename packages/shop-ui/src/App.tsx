import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  BrandHeader, CloseHint, Icon, ItemImage, RadioCard, SearchBox, StateView, Stepper, Tabs, announceReady, isBrowserDev, money, newOpId, nui, t,
  useNuiMessage, type CheckoutResult, type ShopOpen, type ShopProduct,
} from '@veyl/ui';

type Method = 'cash' | 'bank';
type Status = { kind: 'loading' } | { kind: 'error' | 'restricted'; message: string } | { kind: 'ready' };

export function App() {
  const [open, setOpen] = useState(false);
  const [shop, setShop] = useState<ShopOpen | null>(null);
  const [status, setStatus] = useState<Status>({ kind: 'loading' });
  const [category, setCategory] = useState('all');
  const [search, setSearch] = useState('');
  const [basket, setBasket] = useState<Record<number, number>>({});
  const [method, setMethod] = useState<Method>('cash');
  const [paying, setPaying] = useState(false);
  const [retryOp, setRetryOp] = useState<string | null>(null);
  const [toast, setToast] = useState<{ kind: 'error' | 'success'; text: string } | null>(null);
  const toastTimer = useRef<number>();

  useEffect(() => announceReady(), []);

  const say = useCallback((kind: 'error' | 'success', text: string) => {
    setToast({ kind, text });
    window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => setToast(null), 3500);
  }, []);

  useNuiMessage<ShopOpen | null>('shop:open', (d) => {
    setOpen(true); setBasket({}); setCategory('all'); setSearch(''); setPaying(false); setRetryOp(null);
    if (!d) { setShop(null); setStatus({ kind: 'loading' }); return; }
    setShop(d); setMethod(d.methods[0] ?? 'cash'); setStatus({ kind: 'ready' });
  });
  useNuiMessage<{ message: string; restricted?: boolean }>('shop:error', (d) => setStatus({ kind: d.restricted ? 'restricted' : 'error', message: d.message }));
  useNuiMessage('shop:close', () => setOpen(false));
  // Preview-only: seed a basket for visual review. Ignored inside FiveM.
  useNuiMessage<Record<number, number>>('shop:demoBasket', (b) => { if (isBrowserDev()) setBasket(b); });

  const close = useCallback(() => { void nui('close'); }, []);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        if ((e.target as HTMLElement).tagName === 'INPUT') (e.target as HTMLElement).blur(); else close();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, close]);

  const products = useMemo(() => {
    if (!shop) return [];
    const q = search.trim().toLowerCase();
    return shop.products.filter((p) => (category === 'all' || p.category === category) && (!q || p.label.toLowerCase().includes(q)));
  }, [shop, category, search]);

  const lines = useMemo(() => {
    if (!shop) return [];
    return Object.entries(basket)
      .map(([idx, count]) => ({ product: shop.products.find((p) => p.index === Number(idx)), count }))
      .filter((l): l is { product: ShopProduct; count: number } => !!l.product && l.count > 0);
  }, [shop, basket]);

  // Preview total only: the server recomputes the charge from its own prices.
  const total = lines.reduce((sum, l) => sum + l.product.price * l.count, 0);
  const balance = shop ? shop.balances[method] : 0;
  const maxFor = (p: ShopProduct) => Math.min(shop?.maxPerLine ?? 20, p.stock ?? Infinity);

  const add = (p: ShopProduct) => setBasket((b) => ({ ...b, [p.index]: Math.min(maxFor(p), (b[p.index] ?? 0) + 1) }));
  const setCount = (p: ShopProduct, n: number) => setBasket((b) => {
    const next = { ...b };
    if (n <= 0) delete next[p.index]; else next[p.index] = Math.min(maxFor(p), n);
    return next;
  });

  const pay = useCallback(async () => {
    if (!shop || paying || lines.length === 0) return;
    setPaying(true);
    const opId = retryOp ?? newOpId(); // a retried checkout reuses its operation id, so it can never charge twice
    const res = await nui<CheckoutResult & { catalog?: ShopOpen }>('checkout', {
      opId, shopId: shop.shopId, method, expectedTotal: total,
      lines: lines.map((l) => ({ index: l.product.index, count: l.count })),
    });
    setPaying(false);
    if (res.ok && res.data) {
      setRetryOp(null);
      setBasket({});
      setShop((s) => (s ? { ...s, balances: res.data!.balances } : s));
      say('success', res.message ?? `Paid ${money(res.data.total)}`);
      return;
    }
    if (res.code === 'TIMEOUT' || res.code === 'PENDING') { setRetryOp(opId); say('error', res.message ?? 'Payment is being verified. Press Pay again to check.'); return; }
    setRetryOp(null);
    if (res.data && (res.data as { catalog?: ShopOpen }).catalog) {
      const fresh = (res.data as { catalog: ShopOpen }).catalog;
      setShop(fresh); // prices or stock changed while the screen was open
    }
    say('error', res.message ?? res.code ?? 'Payment failed');
  }, [shop, paying, lines, method, total, retryOp, say]);

  if (!open) return null;

  return (
    <div className="shop-root">
      <header className="shop-header">
        <BrandHeader section={t('shop.section')} />
        <CloseHint onClose={close} />
      </header>
      {status.kind !== 'ready' || !shop ? (
        <div className="shop-state v-panel">
          {status.kind === 'loading' ? <StateView kind="loading" /> : <StateView kind={status.kind === 'restricted' ? 'restricted' : 'error'} message={(status as { message: string }).message} />}
        </div>
      ) : (
        <main className="shop-main">
          <section className="shop-catalog v-panel">
            <div className="shop-title">{shop.title.toUpperCase()}</div>
            <div className="v-muted shop-sub">{shop.subtitle}</div>
            <div className="shop-filters">
              <Tabs tabs={[{ id: 'all', label: 'All' }, ...shop.categories]} value={category} onChange={setCategory} />
              <div className="shop-search"><SearchBox value={search} onChange={setSearch} placeholder={t('shop.searchProducts')} /></div>
            </div>
            <div className="shop-grid v-scroll">
              {products.length === 0 && <StateView kind="empty" />}
              {products.map((p) => {
                const out = p.stock !== null && p.stock <= 0;
                const inBasket = basket[p.index] ?? 0;
                return (
                  <div key={p.index} className={`shop-card${out ? ' out' : ''}`}>
                    <div className="shop-card-img"><ItemImage src={p.image ? `${shop.imagePath}/${p.image}` : undefined} alt={p.label} size="70%" /></div>
                    <div className="shop-card-name">{p.label}</div>
                    <div className="shop-card-price">{money(p.price)}{p.stock !== null && <span className="v-muted"> · {out ? t('shop.outOfStock') : `${p.stock} left`}</span>}</div>
                    <button className="v-btn block shop-add" disabled={out || inBasket >= maxFor(p)} onClick={() => add(p)}>
                      <Icon name="plus" size="0.9rem" /> {t('shop.add')}
                    </button>
                  </div>
                );
              })}
            </div>
          </section>

          <aside className="shop-basket v-panel">
            <div className="shop-title">{t('shop.basket').toUpperCase()}</div>
            <div className="basket-lines v-scroll">
              {lines.length === 0 && <div className="v-muted basket-empty">{t('shop.basketEmpty')}</div>}
              {lines.map((l) => (
                <div key={l.product.index} className="basket-line">
                  <div className="basket-thumb"><ItemImage src={l.product.image ? `${shop.imagePath}/${l.product.image}` : undefined} alt={l.product.label} size="80%" /></div>
                  <div className="basket-name">{l.product.label}</div>
                  <Stepper value={l.count} min={0} max={maxFor(l.product)} onChange={(n) => setCount(l.product, n)} disabled={paying} />
                  <div className="basket-total">{money(l.product.price * l.count)}</div>
                </div>
              ))}
            </div>
            <div className="basket-sum"><span>{t('shop.total')}</span><span>{money(total)}</span></div>
            <div className="basket-methods" role="radiogroup">
              {(['cash', 'bank'] as Method[]).map((m) => (
                <RadioCard key={m} label={t(`shop.${m}`)} active={method === m} disabled={!shop.methods.includes(m) || paying} onSelect={() => setMethod(m)} />
              ))}
            </div>
            <div className={`v-muted basket-available${balance < total ? ' short' : ''}`}>
              {balance < total ? t('shop.insufficient') + ' · ' : ''}{t('shop.available', { amount: money(balance) })}
            </div>
            <button className="v-btn primary block basket-pay" disabled={paying || lines.length === 0 || balance < total} onClick={() => void pay()}>
              {paying ? t('shop.processing') : t('shop.pay', { amount: money(total) }).toUpperCase()}
            </button>
            <button className="v-btn link block" disabled={paying || lines.length === 0} onClick={() => setBasket({})}>{t('shop.clear')}</button>
          </aside>
        </main>
      )}
      {toast && <div className={`v-toast-inline ${toast.kind}`} role="alert"><Icon name={toast.kind === 'error' ? 'alert' : 'check'} size="1rem" />{toast.text}</div>}
    </div>
  );
}
