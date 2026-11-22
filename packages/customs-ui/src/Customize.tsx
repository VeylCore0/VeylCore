import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Icon, nui, useNuiMessage } from '@veyl/ui';
import { api, hexToRgb, hsvToRgb, money, rgbToHex, rgbToHsv, same, type Neon, type Opt, type Paint, type RGB, type Totals, type Value } from './lib';
import type { Toast } from './App';

export interface CustomizeData {
  session: string; mode: 'self' | 'quote'; orderId?: number; model: string; vehicleLabel: string; plate: string; bike: boolean; lighting: boolean;
  shop: { id: string; label: string; sub?: string; laborRate: number; taxRate: number };
  categories: { id: string; label: string }[]; options: Opt[]; current: Record<string, Value | undefined>; preload?: Record<string, Value>;
  finishes: { id: string; label: string; index: number }[]; presets: { name: string; primary: string; secondary: string }[]; swatches: string[]; maxSwatches: number;
}
type Cart = Record<string, Value>;
const CAM: Record<string, string> = { performance: 'engine', bodywork: 'front34', wheels: 'wheel', paint: 'side34', lighting: 'front', details: 'rear34' };

export function Customize({ d, say, close }: { d: CustomizeData; say: Toast; close: () => void }) {
  const [cat, setCat] = useState(d.categories[0]?.id ?? 'bodywork');
  const [group, setGroup] = useState<string | null>(null);
  const [cart, setCart] = useState<Cart>(d.preload ?? {});
  const [totals, setTotals] = useState<Totals | null>(null);
  const [rowPrices, setRowPrices] = useState<Record<string, number>>({});
  const [wheels, setWheels] = useState<Opt['values'] | null>(null);
  const [drawer, setDrawer] = useState<null | 'review' | 'builds'>(null);
  const [confirmClose, setConfirmClose] = useState(false);
  const [photo, setPhoto] = useState(false);
  const [light, setLight] = useState<string | null>(null);
  const S = d.session;

  const opts = useMemo(() => d.options.map((o) => (o.key === 'mod:23' && wheels ? { ...o, values: wheels } : o)), [d.options, wheels]);
  const catOpts = opts.filter((o) => o.cat === cat);
  const value = (key: string) => (key in cart ? cart[key] : d.current[key]);

  // Server prices the cart (debounced). The page never computes a price itself.
  const priceTimer = useRef<number>();
  const reprice = useCallback((c: Cart) => {
    window.clearTimeout(priceTimer.current);
    priceTimer.current = window.setTimeout(async () => {
      if (!Object.keys(c).length) { setTotals({ lines: [], subtotal: 0, labor: 0, tax: 0, total: 0 }); return; }
      const r = await api<Totals>('price', S, c);
      if (r.ok && r.data) setTotals(r.data); else say(r.message ?? 'Could not price the build', true);
    }, 180);
  }, [S, say]);
  useEffect(() => { reprice(cart); }, [cart, reprice]);

  const preview = useCallback(async (key: string, v: Value | null) => {
    const r = await nui<{ cart: Cart; extra?: { wheels?: Opt['values'] } }>('preview', { session: S, key, value: v, remove: v === null });
    if (!r.ok || !r.data) return say(r.message ?? 'Not available', true);
    setCart(r.data.cart ?? {});
    if (r.data.extra?.wheels) setWheels(r.data.extra.wheels);
  }, [S, say]);
  const temp = useCallback((key: string, v: Value) => { void nui('preview', { session: S, key, value: v, temp: true }); }, [S]);

  // Row prices for the open group.
  useEffect(() => {
    const o = opts.find((x) => x.key === group);
    if (!o) return;
    const items = o.values ? o.values.map((v) => ({ key: o.key, value: v.value })) : o.toggle ? [{ key: o.key, value: true }, { key: o.key, value: false }] : [];
    if (!items.length) return;
    void api<number[]>('rowPrices', S, items).then((r) => {
      if (!r.ok || !r.data) return;
      const next: Record<string, number> = {};
      items.forEach((it, i) => { next[`${it.key}|${JSON.stringify(it.value)}`] = r.data![i]; });
      setRowPrices((p) => ({ ...p, ...next }));
    });
  }, [group, opts, S]);

  const camera = (payload: Record<string, unknown>) => { void nui('camera', { session: S, ...payload }); };
  const pickCat = (c: string) => { setCat(c); setGroup(null); camera({ frame: CAM[c] ?? 'front34' }); if (c !== 'paint' && light) { setLight(null); void nui('lighting', { session: S, mode: null }); } };
  const openGroup = (o: Opt) => { setGroup(o.key); if (o.camera) camera({ frame: o.camera }); };

  // Keyboard: Escape (with an unsaved-changes prompt), hold Space to compare with the original.
  const comparing = useRef(false);
  useEffect(() => {
    const down = (e: KeyboardEvent) => {
      if ((e.target as HTMLElement).tagName === 'INPUT') return;
      if (e.code === 'Space' && !comparing.current) { comparing.current = true; e.preventDefault(); void nui('compare', { session: S, on: true }); }
      if (e.key === 'Escape') {
        e.preventDefault();
        if (confirmClose) setConfirmClose(false);
        else if (drawer) setDrawer(null);
        else if (group) setGroup(null);
        else if (Object.keys(cart).length) setConfirmClose(true);
        else close();
      }
    };
    const up = (e: KeyboardEvent) => { if (e.code === 'Space' && comparing.current) { comparing.current = false; void nui('compare', { session: S, on: false }); } };
    window.addEventListener('keydown', down); window.addEventListener('keyup', up);
    return () => { window.removeEventListener('keydown', down); window.removeEventListener('keyup', up); };
  }, [S, cart, drawer, group, confirmClose, close]);

  useNuiMessage<{ on: boolean }>('customs:photo', (m) => setPhoto(m.on));

  // Camera: drag the empty viewport to rotate, wheel to zoom.
  const drag = useRef<{ x: number; y: number } | null>(null);
  const onDown = (e: React.PointerEvent) => { drag.current = { x: e.clientX, y: e.clientY }; (e.target as HTMLElement).setPointerCapture(e.pointerId); };
  const onMove = (e: React.PointerEvent) => {
    if (!drag.current) return;
    const dx = e.clientX - drag.current.x, dy = e.clientY - drag.current.y;
    if (Math.abs(dx) + Math.abs(dy) < 2) return;
    drag.current = { x: e.clientX, y: e.clientY };
    camera({ dx, dy });
  };

  const total = totals?.total ?? 0;
  const changedIn = (c: string) => Object.keys(cart).some((k) => opts.find((o) => o.key === k)?.cat === c);
  const catLabel = d.categories.find((c) => c.id === cat)?.label ?? '';
  const g = opts.find((o) => o.key === group);

  return (
    <div className={`cz${photo ? ' photo' : ''}`}>
      <header className="topbar">
        <div className="wordmark"><b>VEYL</b><i>/</i><span>CUSTOMS</span></div>
        <nav className="tabs" aria-label="Categories">
          {d.categories.map((c) => (
            <button key={c.id} className={`tab${cat === c.id ? ' on' : ''}`} aria-current={cat === c.id} onClick={() => pickCat(c.id)}>
              {c.label}{changedIn(c.id) ? ' •' : ''}
            </button>
          ))}
        </nav>
        <button className="iconbtn" aria-label="Close" onClick={() => (Object.keys(cart).length ? setConfirmClose(true) : close())}><Icon name="close" size="1.1em" /></button>
      </header>

      <div className="middle">
        <div style={{ position: 'absolute', inset: 0, pointerEvents: 'auto', cursor: 'grab' }} onPointerDown={onDown} onPointerMove={onMove}
          onPointerUp={() => { drag.current = null; }} onWheel={(e) => camera({ zoom: e.deltaY })} aria-hidden />
        {cat === 'paint' && (
          <div className="lighting" role="group" aria-label="Lighting preview">
            {d.lighting ? (['studio', 'daylight', 'sunset', 'night'] as const).map((m) => (
              <button key={m} className={light === m ? 'on' : ''} onClick={() => { const next = light === m ? null : m; setLight(next); void nui('lighting', { session: S, mode: next }); }}>
                {m[0].toUpperCase() + m.slice(1)}
              </button>
            )) : <span className="off">Lighting preview needs veyl_world (time/weather)</span>}
          </div>
        )}

        <aside className="side" aria-label="Options">
          <div className="crumbs">{d.vehicleLabel || d.model}<i>/</i>{catLabel}{d.mode === 'quote' ? ` · Quote${d.orderId ? ` #${d.orderId}` : ''}` : ''}</div>
          {cat === 'paint' ? (
            <PaintStudio d={d} value={value} cart={cart} temp={temp} commit={preview} say={say} session={S} />
          ) : g ? (
            <>
              <button className="back" onClick={() => setGroup(null)}><Icon name="back" size="0.9em" /> {catLabel}</button>
              <h2>{g.label}</h2>
              <div className="scroll">
                <OptionEditor o={g} current={value(g.key)} original={d.current[g.key]} prices={rowPrices} set={(v) => void preview(g.key, v)} />
              </div>
              {g.key in cart && <button className="btn ghost small" style={{ marginTop: 12 }} onClick={() => void preview(g.key, null)}>Undo this change</button>}
            </>
          ) : (
            <>
              <h2>{catLabel}</h2>
              <div className="scroll">
                {catOpts.length === 0 && <div className="empty">Nothing in this category fits this vehicle.</div>}
                {catOpts.map((o) => (
                  <button key={o.key} className="group" onClick={() => openGroup(o)}>
                    <span>{o.label}{o.key in cart && <span className="changed">Changed</span>}</span>
                    <small>{describe(o, value(o.key))}</small>
                  </button>
                ))}
              </div>
            </>
          )}
        </aside>

        {drawer === 'review' && <Review d={d} cart={cart} totals={totals} remove={(k) => void preview(k, null)} undoAll={async () => { const r = await nui<{ cart: Cart }>('resetCart', { session: S }); if (r.ok) setCart({}); }}
          done={() => setDrawer(null)} say={say} close={close} onPaid={() => setCart({})} />}
        {drawer === 'builds' && <Builds d={d} cart={cart} say={say} done={() => setDrawer(null)} load={async (c) => { const r = await nui<{ cart: Cart }>('loadCart', { session: S, cart: c }); if (r.ok && r.data) { setCart(r.data.cart); say('Build loaded into the preview. Prices are from this shop.'); } }} />}
      </div>

      <footer className="bottombar">
        <span className="hint"><Icon name="mouse" size="1.2em" /> Drag to rotate</span>
        <span className="sep" />
        <span className="hint">Scroll to zoom</span>
        <span className="sep" />
        <span className="hint"><kbd>SPACE</kbd> Hold to compare</span>
        <span className="spacer" />
        <button className="btn ghost small" onClick={() => camera({ reset: true })}>Reset view</button>
        <button className="btn ghost small" onClick={() => void nui('photo', { session: S })}><Icon name="camera" size="1em" /> Photo</button>
        <button className="btn ghost small" onClick={() => setDrawer(drawer === 'builds' ? null : 'builds')}>Saved builds</button>
        <span className="sep" />
        <span className="total">Build total <b>{money(total)}</b></span>
        <button className="btn primary" disabled={!Object.keys(cart).length} onClick={() => setDrawer('review')}>Review build <Icon name="chevron" size="1em" /></button>
      </footer>

      {confirmClose && (
        <div className="modal-back"><div className="modal" role="alertdialog" aria-label="Discard changes">
          <h3 style={{ margin: 0 }}>Discard this build?</h3>
          <p>Nothing has been paid. The vehicle stays exactly as it was.</p>
          <div className="actions"><button className="btn primary" onClick={close}>Discard and leave</button><button className="btn ghost" onClick={() => setConfirmClose(false)}>Keep editing</button></div>
        </div></div>
      )}
    </div>
  );
}

function describe(o: Opt, v: Value | undefined): string {
  if (v === undefined || v === null) return '';
  if (o.values) return o.values.find((x) => x.value === v)?.label ?? (v === -1 ? 'Stock' : `Option ${(v as number) + 1}`);
  if (o.toggle || typeof v === 'boolean') return v ? 'On' : 'Off';
  if (o.kind === 'rgb') return rgbToHex(v as RGB);
  if (o.kind === 'neon') { const n = v as Neon; const on = (['l', 'r', 'f', 'b'] as const).filter((s) => n[s]); return on.length ? `${on.length} sides` : 'Off'; }
  if (typeof v === 'number') return `Colour ${v}`;
  return '';
}

function OptionEditor({ o, current, original, prices, set }: { o: Opt; current: Value | undefined; original: Value | undefined; prices: Record<string, number>; set: (v: Value) => void }) {
  const price = (v: Value) => { const p = prices[`${o.key}|${JSON.stringify(v)}`]; return p === undefined ? '' : p < 0 ? 'n/a' : money(p); };
  const row = (v: Value, label: string) => {
    const sel = same(current, v);
    return (
      <button key={JSON.stringify(v)} className={`row${sel ? ' sel' : ''}`} aria-pressed={sel} onClick={() => set(v)}>
        <span className="dot" /><span className="lbl">{label}</span>
        {same(original, v) && <span className="tag">Current</span>}
        <span className="price">{same(original, v) ? '' : price(v)}</span>
      </button>
    );
  };
  if (o.values) return <>{o.values.map((v) => row(v.value, v.label))}</>;
  if (o.toggle || o.kind === 'toggle' || o.kind === 'extra') return <>{row(true, 'On')}{row(false, 'Off')}</>;
  if (o.kind === 'rgb') return <RgbEditor value={(current as RGB) ?? { r: 255, g: 255, b: 255 }} set={set} />;
  if (o.kind === 'neon') {
    const n = (current as Neon) ?? { l: false, r: false, f: false, b: false };
    return (
      <div className="neon">
        {(['l', 'r', 'f', 'b'] as const).map((s) => (
          <button key={s} className={`row${n[s] ? ' sel' : ''}`} aria-pressed={n[s]} onClick={() => set({ ...n, [s]: !n[s] })}>
            <span className="dot" /><span className="lbl">{{ l: 'Left', r: 'Right', f: 'Front', b: 'Back' }[s]}</span><span className="price">{n[s] ? 'On' : 'Off'}</span>
          </button>
        ))}
      </div>
    );
  }
  const n = typeof current === 'number' ? current : 0;
  return (
    <div>
      <div className="stepper">
        <button className="btn small" aria-label="Previous colour" onClick={() => set(Math.max(0, n - 1))}>−</button>
        <input type="range" min={0} max={160} value={n} onChange={(e) => set(Number(e.target.value))} aria-label={o.label} />
        <button className="btn small" aria-label="Next colour" onClick={() => set(Math.min(160, n + 1))}>+</button>
      </div>
      <p className="note">Colour {n} of GTA's paint palette. The vehicle shows it live.</p>
    </div>
  );
}

function RgbEditor({ value, set }: { value: RGB; set: (v: RGB) => void }) {
  const [hex, setHex] = useState(rgbToHex(value));
  useEffect(() => setHex(rgbToHex(value)), [value]);
  const ok = !!hexToRgb(hex);
  return (
    <div>
      <div className="field"><label>HEX</label><input className={`input${ok ? '' : ' bad'}`} value={hex} maxLength={7} onChange={(e) => { setHex(e.target.value); const c = hexToRgb(e.target.value); if (c) set(c); }} /></div>
      <div className="swatches">{['#FFFFFF', '#A5F3D0', '#F3A6C8', '#7AA7FF', '#F2C66D', '#EF4444', '#A855F7', '#22D3EE'].map((h) => (
        <button key={h} className={`sw${same(hexToRgb(h), value) ? ' on' : ''}`} style={{ background: h }} aria-label={h} onClick={() => set(hexToRgb(h)!)} />
      ))}</div>
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------------------------
// Paint Studio: picker changes are a temporary preview; "Add to build" puts the paint package in the cart.
// ---------------------------------------------------------------------------------------------------------------------
function PaintStudio({ d, value, cart, temp, commit, say, session }: { d: CustomizeData; value: (k: string) => Value | undefined; cart: Cart;
  temp: (k: string, v: Value) => void; commit: (k: string, v: Value | null) => Promise<void> | void; say: Toast; session: string }) {
  const [tab, setTab] = useState<'primary' | 'secondary' | 'pearl'>('primary');
  const start = (k: 'paint:primary' | 'paint:secondary'): Paint => (value(k) as Paint) ?? { index: d.finishes[0].index, rgb: null };
  const [draft, setDraft] = useState<{ primary: Paint; secondary: Paint; pearl: number }>({ primary: start('paint:primary'), secondary: start('paint:secondary'), pearl: (value('pearl') as number) ?? 0 });
  const [swatches, setSwatches] = useState<string[]>(d.swatches ?? []);
  const [price, setPrice] = useState(0);
  const cur: Paint = tab === 'pearl' ? draft.primary : draft[tab];
  const rgb = cur.rgb ?? { r: 200, g: 200, b: 200 };
  const [hsv, setHsv] = useState(rgbToHsv(rgb));
  const [hex, setHex] = useState(rgbToHex(rgb));
  useEffect(() => { setHsv(rgbToHsv(draft[tab === 'pearl' ? 'primary' : tab].rgb ?? { r: 200, g: 200, b: 200 })); setHex(rgbToHex(draft[tab === 'pearl' ? 'primary' : tab].rgb ?? { r: 200, g: 200, b: 200 })); }, [tab]); // eslint-disable-line

  const changes = (): [string, Value][] => {
    const out: [string, Value][] = [];
    if (!same(draft.primary, value('paint:primary'))) out.push(['paint:primary', draft.primary]);
    if (!same(draft.secondary, value('paint:secondary'))) out.push(['paint:secondary', draft.secondary]);
    if (draft.pearl !== (value('pearl') ?? 0)) out.push(['pearl', draft.pearl]);
    return out;
  };
  // Price of the paint package (server).
  useEffect(() => {
    const ch = changes();
    if (!ch.length) { setPrice(0); return; }
    void api<number[]>('rowPrices', session, ch.map(([key, v]) => ({ key, value: v }))).then((r) => { if (r.ok && r.data) setPrice(r.data.reduce((a, b) => a + Math.max(0, b), 0)); });
  }, [draft]); // eslint-disable-line

  const setPaint = (p: Paint) => {
    if (tab === 'pearl') return;
    const next = { ...draft, [tab]: p };
    setDraft(next);
    temp(`paint:${tab}`, p);
  };
  const setRgb = (c: RGB) => { setHex(rgbToHex(c)); setPaint({ index: cur.index, rgb: c }); };

  const svRef = useRef<HTMLDivElement>(null);
  const svDrag = (e: React.PointerEvent) => {
    const el = svRef.current; if (!el || (e.type === 'pointermove' && e.buttons !== 1)) return;
    if (e.type === 'pointerdown') el.setPointerCapture(e.pointerId);
    const b = el.getBoundingClientRect();
    const s = Math.max(0, Math.min(1, (e.clientX - b.left) / b.width)), v = Math.max(0, Math.min(1, 1 - (e.clientY - b.top) / b.height));
    const next = { ...hsv, s, v }; setHsv(next); setRgb(hsvToRgb(next.h, s, v));
  };
  const hueDrag = (e: React.PointerEvent<HTMLDivElement>) => {
    if (e.type === 'pointermove' && e.buttons !== 1) return;
    if (e.type === 'pointerdown') e.currentTarget.setPointerCapture(e.pointerId);
    const b = e.currentTarget.getBoundingClientRect();
    const h = Math.max(0, Math.min(359.9, ((e.clientX - b.left) / b.width) * 360));
    const next = { ...hsv, h }; setHsv(next); setRgb(hsvToRgb(h, next.s, next.v));
  };
  const saveSwatches = async (list: string[]) => {
    const r = await api<string[]>('swatches', list);
    if (r.ok && r.data) setSwatches(r.data); else say(r.message ?? 'Could not save', true);
  };
  const add = async () => {
    const ch = changes();
    if (!ch.length) return say('Nothing changed');
    for (const [k, v] of ch) await commit(k, v);
    say('Paint added to the build');
  };
  const finish = d.finishes.find((f) => f.index === cur.index);

  return (
    <>
      <h2>Paint Studio</h2>
      <div className="scroll">
        <div className="seg" role="tablist">
          {(['primary', 'secondary', 'pearl'] as const).map((t) => <button key={t} role="tab" aria-selected={tab === t} className={tab === t ? 'on' : ''} onClick={() => setTab(t)}>{t === 'pearl' ? 'Pearl' : t[0].toUpperCase() + t.slice(1)}</button>)}
        </div>
        {tab === 'pearl' ? (
          <>
            <div className="stepper">
              <button className="btn small" onClick={() => { const p = Math.max(0, draft.pearl - 1); setDraft({ ...draft, pearl: p }); temp('pearl', p); }}>−</button>
              <input type="range" min={0} max={160} value={draft.pearl} aria-label="Pearlescent colour" onChange={(e) => { const p = Number(e.target.value); setDraft({ ...draft, pearl: p }); temp('pearl', p); }} />
              <button className="btn small" onClick={() => { const p = Math.min(160, draft.pearl + 1); setDraft({ ...draft, pearl: p }); temp('pearl', p); }}>+</button>
            </div>
            <p className="note">Pearlescent colour {draft.pearl} (GTA palette). It only shows over a <b>Metallic</b> primary finish.</p>
          </>
        ) : (
          <>
            <div ref={svRef} className="sv" onPointerDown={svDrag} onPointerMove={svDrag}
              style={{ background: `linear-gradient(to top, #000, transparent), linear-gradient(to right, #fff, hsl(${hsv.h}, 100%, 50%))` }} aria-label="Saturation and brightness">
              <span className="knob" style={{ left: `${hsv.s * 100}%`, top: `${(1 - hsv.v) * 100}%`, background: rgbToHex(rgb) }} />
            </div>
            <div className="hue" onPointerDown={hueDrag} onPointerMove={hueDrag} aria-label="Hue"><span className="knob" style={{ left: `${(hsv.h / 360) * 100}%` }} /></div>
            <div className="field"><label>HEX</label>
              <input className={`input${hexToRgb(hex) ? '' : ' bad'}`} value={hex} maxLength={7} onChange={(e) => { setHex(e.target.value); const c = hexToRgb(e.target.value); if (c) { setHsv(rgbToHsv(c)); setPaint({ index: cur.index, rgb: c }); } }} />
            </div>
            <div className="field"><label>RGB</label>
              <div className="rgb">{(['r', 'g', 'b'] as const).map((ch) => (
                <input key={ch} className="input" inputMode="numeric" aria-label={ch.toUpperCase()} value={rgb[ch]}
                  onChange={(e) => { const n = Math.max(0, Math.min(255, Math.floor(Number(e.target.value) || 0))); const c = { ...rgb, [ch]: n }; setHsv(rgbToHsv(c)); setRgb(c); }} />
              ))}</div>
            </div>
            <div className="sub">Finish</div>
            <div className="chips">{d.finishes.map((f) => <button key={f.id} className={`chip${cur.index === f.index ? ' on' : ''}`} onClick={() => setPaint({ index: f.index, rgb: cur.rgb })}>{f.label}</button>)}</div>
            {!finish && <p className="note">Current finish: GTA paint {cur.index}.</p>}
            <div className="sub">Saved swatches</div>
            <div className="swatches">
              {swatches.map((h) => (
                <button key={h} className={`sw${hex.toUpperCase() === h ? ' on' : ''}`} style={{ background: h }} aria-label={`Use ${h}`}
                  onClick={() => { const c = hexToRgb(h)!; setHsv(rgbToHsv(c)); setRgb(c); }} onContextMenu={(e) => { e.preventDefault(); void saveSwatches(swatches.filter((x) => x !== h)); }}>
                  {hex.toUpperCase() === h ? <Icon name="check" size="0.9em" /> : null}
                </button>
              ))}
            </div>
            <button className="back" style={{ marginTop: 10 }} disabled={swatches.length >= d.maxSwatches || !hexToRgb(hex)} onClick={() => void saveSwatches([...swatches.filter((x) => x !== hex.toUpperCase()), hex.toUpperCase()])}>
              <Icon name="plus" size="0.9em" /> Save colour {swatches.length >= d.maxSwatches ? '(full: right-click one to remove)' : ''}
            </button>
            <div className="sub">Presets</div>
            {d.presets.map((p) => (
              <button key={p.name} className="preset" onClick={() => {
                const a = hexToRgb(p.primary)!, b = hexToRgb(p.secondary)!;
                const next = { ...draft, primary: { index: draft.primary.index, rgb: a }, secondary: { index: draft.secondary.index, rgb: b } };
                setDraft(next); temp('paint:primary', next.primary); temp('paint:secondary', next.secondary);
                if (tab !== 'secondary') { setHsv(rgbToHsv(a)); setHex(p.primary); } else { setHsv(rgbToHsv(b)); setHex(p.secondary); }
              }}><i style={{ background: p.primary }} /><i style={{ background: p.secondary }} />{p.name}</button>
            ))}
          </>
        )}
      </div>
      <div className="actions" style={{ alignItems: 'center' }}>
        <span className="total">Paint <b>{money(price)}</b></span>
        <span className="spacer" />
        {('paint:primary' in cart || 'paint:secondary' in cart || 'pearl' in cart) && <button className="btn ghost small" onClick={async () => { for (const k of ['paint:primary', 'paint:secondary', 'pearl']) if (k in cart) await commit(k, null); setDraft({ primary: (d.current['paint:primary'] as Paint) ?? draft.primary, secondary: (d.current['paint:secondary'] as Paint) ?? draft.secondary, pearl: (d.current.pearl as number) ?? 0 }); }}>Undo paint</button>}
        <button className="btn primary" onClick={() => void add()}><Icon name="cart" size="1em" /> Add to build</button>
      </div>
    </>
  );
}

// ---------------------------------------------------------------------------------------------------------------------
// Review: server-priced lines, then quote + payment (self-service) or save the quote (mechanic)
// ---------------------------------------------------------------------------------------------------------------------
function Review({ d, cart, totals, remove, undoAll, done, say, close, onPaid }: { d: CustomizeData; cart: Cart; totals: Totals | null; remove: (k: string) => void;
  undoAll: () => void; done: () => void; say: Toast; close: () => void; onPaid: () => void }) {
  const [quote, setQuote] = useState<(Totals & { version: number; expiresIn: number; methods: string[] }) | null>(null);
  const [method, setMethod] = useState('bank');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  useEffect(() => setQuote(null), [cart]);
  const t = quote ?? totals;
  const getQuote = async () => {
    setBusy(true);
    const r = await api<Totals & { version: number; expiresIn: number; methods: string[] }>('quote', d.session, cart);
    setBusy(false);
    if (r.ok && r.data) { setQuote(r.data); setMethod(r.data.methods[0] ?? 'bank'); } else say(r.message ?? 'Could not quote', true);
  };
  const pay = async () => {
    if (!quote) return;
    setBusy(true);
    const r = await api('checkout', d.session, quote.version, method);
    setBusy(false);
    say(r.message ?? (r.ok ? 'Paid' : 'Payment failed'), !r.ok);
    if (r.ok) { onPaid(); setQuote(null); done(); }
    else if (r.code === 'STALE' || r.code === 'EXPIRED') setQuote(null);
  };
  const saveQuote = async () => {
    setBusy(true);
    const r = await api<{ orderId: number }>('saveOrder', d.session, cart, note);
    setBusy(false);
    say(r.message ?? (r.ok ? 'Saved' : 'Failed'), !r.ok);
    if (r.ok) close();
  };
  return (
    <aside className="drawer" aria-label="Review build">
      <h3>Review build</h3>
      <div className="scroll">
        {(t?.lines ?? []).map((l) => (
          <div className="line" key={l.key}><span>{l.label}</span><b>{money(l.price)}</b>
            {!quote && <button className="x" aria-label={`Remove ${l.label}`} onClick={() => l.key && remove(l.key)}><Icon name="close" size="0.9em" /></button>}</div>
        ))}
        {!t?.lines.length && <div className="empty">No changes yet.</div>}
      </div>
      {t && t.lines.length > 0 && <>
        <div className="sum"><span>Parts</span><span>{money(t.subtotal)}</span></div>
        {t.labor > 0 && <div className="sum"><span>Labour ({Math.round(d.shop.laborRate * 100)}%)</span><span>{money(t.labor)}</span></div>}
        {t.tax > 0 && <div className="sum"><span>Tax ({Math.round(d.shop.taxRate * 100)}%)</span><span>{money(t.tax)}</span></div>}
        <div className="sum big"><span>Total</span><span>{money(t.total)}</span></div>
      </>}
      {d.mode === 'self' ? (
        quote ? (
          <>
            <p className="note">Quote v{quote.version}, valid for {Math.round(quote.expiresIn / 60)} minutes. Nothing is installed until it is paid.</p>
            <div className="chips">{quote.methods.map((m) => <button key={m} className={`chip${method === m ? ' on' : ''}`} onClick={() => setMethod(m)}>{m === 'bank' ? 'Card' : 'Cash'}</button>)}</div>
            <div className="actions"><button className="btn primary" disabled={busy} onClick={() => void pay()}>Pay {money(quote.total)}</button><button className="btn ghost" onClick={() => setQuote(null)}>Back</button></div>
          </>
        ) : (
          <div className="actions">
            <button className="btn primary" disabled={busy || !t?.lines.length} onClick={() => void getQuote()}>Get final quote</button>
            <button className="btn ghost" onClick={undoAll}>Undo all</button>
            <button className="btn ghost" onClick={done}>Keep editing</button>
          </div>
        )
      ) : (
        <>
          <div className="field" style={{ marginTop: 12 }}><input className="input" placeholder="Note for the customer (optional)" maxLength={200} value={note} onChange={(e) => setNote(e.target.value)} /></div>
          <div className="actions">
            <button className="btn primary" disabled={busy || !t?.lines.length} onClick={() => void saveQuote()}>{d.orderId ? 'Save new quote version' : 'Save quote'}</button>
            <button className="btn ghost" onClick={undoAll}>Undo all</button>
          </div>
          <p className="note">Saving makes a draft. Send it from the workshop dashboard; the customer approves that exact version.</p>
        </>
      )}
    </aside>
  );
}

// ---------------------------------------------------------------------------------------------------------------------
// Saved builds (per character; loading only previews and re-prices: it never grants anything)
// ---------------------------------------------------------------------------------------------------------------------
interface Build { id: number; name: string; model: string; code: string; compatible: boolean; data: Cart }
function Builds({ d, cart, say, done, load }: { d: CustomizeData; cart: Cart; say: Toast; done: () => void; load: (c: Cart) => void }) {
  const [list, setList] = useState<Build[] | null>(null);
  const [name, setName] = useState('');
  const [code, setCode] = useState('');
  const refresh = useCallback(async () => { const r = await api<Build[]>('builds', d.model); if (r.ok && r.data) setList(r.data); }, [d.model]);
  useEffect(() => { void refresh(); }, [refresh]);
  const run = async (name: string, ...args: unknown[]) => { const r = await api(name, ...args); say(r.message ?? (r.ok ? 'Done' : 'Failed'), !r.ok); if (r.ok) void refresh(); };
  return (
    <aside className="drawer" aria-label="Saved builds">
      <h3>Saved builds</h3>
      <div className="field"><input className="input" placeholder="Name this build" maxLength={40} value={name} onChange={(e) => setName(e.target.value)} />
        <button className="btn small" disabled={!name.trim() || !Object.keys(cart).length} onClick={() => { void run('buildSave', name.trim(), d.model, cart); setName(''); }}>Save</button></div>
      <div className="field"><input className="input" placeholder="Share code" maxLength={8} value={code} onChange={(e) => setCode(e.target.value.toUpperCase())} />
        <button className="btn small" disabled={code.length !== 8} onClick={() => { void run('buildImport', code); setCode(''); }}>Import</button></div>
      <div className="scroll">
        {list?.length === 0 && <div className="empty">No saved builds.</div>}
        {list?.map((b) => (
          <div className="line" key={b.id} style={{ flexWrap: 'wrap' }}>
            <span><b>{b.name}</b><br /><small style={{ color: 'var(--muted)' }}>{b.model} · {Object.keys(b.data).length} changes · code {b.code}</small></span>
            <button className="btn small" disabled={!b.compatible} title={b.compatible ? '' : 'Made for another model'} onClick={() => load(b.data)}>{b.compatible ? 'Load' : 'Other model'}</button>
            <button className="btn ghost small" onClick={() => void run('buildDuplicate', b.id)}>Copy</button>
            <button className="btn ghost small danger" onClick={() => void run('buildDelete', b.id)}>Delete</button>
          </div>
        ))}
      </div>
      <div className="actions"><button className="btn ghost" onClick={done}>Close</button></div>
      <p className="note">A share code holds the model and options only, never your name or vehicle. Loading a build previews it here; you pay this shop's prices.</p>
    </aside>
  );
}
