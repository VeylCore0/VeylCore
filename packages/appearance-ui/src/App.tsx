import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { BrandHeader, CloseHint, Icon, RadioCard, SearchBox, StateView, Tabs, announceReady, money, newOpId, nui, useNuiMessage } from '@veyl/ui';
import { EyesEditor, FeaturesEditor, HeritageEditor, SlotEditor } from './editors';
import { FOCUS_LABELS, GROUP_LABELS, MODE_SECTION, sameSlot, type AppearanceOpen, type Category, type Focus, type Group, type Outfit, type Slot } from './types';

const OUTFITS = '__outfits';
type Method = 'cash' | 'bank';

export function App() {
  const [data, setData] = useState<AppearanceOpen | null>(null);
  const [active, setActive] = useState<string>('');
  const [search, setSearch] = useState('');
  const [focus, setFocus] = useState<Focus>('full');
  const [method, setMethod] = useState<Method>('cash');
  const [busy, setBusy] = useState(false);
  const [retryOp, setRetryOp] = useState<string | null>(null);
  const [confirmLeave, setConfirmLeave] = useState(false);
  const [outfitName, setOutfitName] = useState('');
  const [toast, setToast] = useState<{ kind: 'error' | 'success'; text: string } | null>(null);
  const toastTimer = useRef<number>();

  useEffect(() => announceReady(), []);

  const say = useCallback((kind: 'error' | 'success', text: string) => {
    setToast({ kind, text });
    window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => setToast(null), 3500);
  }, []);

  const load = useCallback((d: AppearanceOpen, keepActive = false) => {
    setData(d);
    if (!keepActive) { setActive(d.mode === 'clothing' && d.store?.outfits?.length ? OUTFITS : d.categories[0]?.key ?? ''); setSearch(''); setFocus('full'); }
    if (d.store) setMethod((m) => (d.store!.methods.includes(m) ? m : d.store!.methods[0] ?? 'cash'));
  }, []);

  useNuiMessage<AppearanceOpen>('appearance:open', (d) => { setConfirmLeave(false); setBusy(false); setRetryOp(null); load(d); });
  useNuiMessage('appearance:close', () => setData(null));

  const cats = data?.categories ?? [];
  const byKey = useMemo(() => Object.fromEntries(cats.map((c) => [c.key, c])), [cats]);
  const isStore = !!data?.store;

  // Changes since the editor opened (or since the last payment), with the preview price of each.
  const changes = useMemo(() => {
    if (!data) return [];
    return cats.filter((c) => !sameSlot(data.values[c.key], data.original[c.key])).map((c) => {
      const free = (data.store?.outfits ?? []).some((o) => sameSlot(o.slots[c.key], data.values[c.key]));
      return { cat: c, price: isStore ? (free ? 0 : data.store!.prices[c.key] ?? 0) : 0, free };
    });
  }, [data, cats, isStore]);
  const total = changes.reduce((s, c) => s + c.price, 0);
  const changed = useMemo(() => new Set(changes.map((c) => c.cat.key)), [changes]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return q ? cats.filter((c) => c.label.toLowerCase().includes(q) || GROUP_LABELS[c.group].toLowerCase().includes(q)) : cats;
  }, [cats, search]);

  const groups = useMemo(() => {
    const out: { group: Group; items: Category[] }[] = [];
    for (const c of filtered) {
      const g = out.find((x) => x.group === c.group);
      if (g) g.items.push(c); else out.push({ group: c.group, items: [c] });
    }
    return out;
  }, [filtered]);

  const setCamera = useCallback((f: Focus) => { setFocus(f); void nui('camera', { focus: f }); }, []);

  const select = useCallback((key: string) => {
    setActive(key);
    const c = byKey[key];
    if (c) setCamera(c.camera);
  }, [byKey, setCamera]);

  const change = useCallback(async (key: string, value: Slot) => {
    setData((d) => (d ? { ...d, values: { ...d.values, [key]: value } } : d)); // instant feedback; Lua returns the clamped value
    const res = await nui<{ value: Slot; textures?: number }>('change', { key, value });
    if (!res.ok || !res.data) return;
    const { value: v, textures } = res.data;
    setData((d) => d && {
      ...d, values: { ...d.values, [key]: v },
      categories: textures === undefined ? d.categories : d.categories.map((c) => (c.key === key ? { ...c, textures } : c)),
    });
  }, []);

  const reset = (key: string) => { if (data) void change(key, data.original[key]); };
  const resetAll = () => changes.forEach((c) => reset(c.cat.key));

  const rotate = (delta: number) => void nui('rotate', { delta });

  const close = useCallback(() => {
    if (!data?.allowCancel) return;
    if (changes.length > 0 && !confirmLeave) { setConfirmLeave(true); return; }
    void nui('close');
  }, [data, changes.length, confirmLeave]);

  const pay = useCallback(async () => {
    if (!data?.store || busy || changes.length === 0) return;
    setBusy(true);
    const opId = retryOp ?? newOpId(); // a retried payment reuses its operation id, so it can never charge twice
    const res = await nui<AppearanceOpen | { total: number }>('checkout', { opId, method, expectedTotal: total });
    setBusy(false);
    if (res.ok && res.data && 'categories' in res.data) {
      setRetryOp(null);
      load(res.data, true);
      say('success', res.message ?? 'Saved');
      return;
    }
    if (res.code === 'TIMEOUT' || res.code === 'PENDING') { setRetryOp(opId); say('error', res.message ?? 'Payment is being verified. Press Pay again to check.'); return; }
    setRetryOp(null);
    say('error', res.message ?? res.code ?? 'Payment failed');
  }, [data, busy, changes.length, retryOp, method, total, load, say]);

  const finish = useCallback(async () => {
    if (busy) return;
    setBusy(true);
    const res = await nui('finish');
    setBusy(false);
    if (!res.ok) say('error', res.message ?? res.code ?? 'Could not save');
  }, [busy, say]);

  const outfitAction = useCallback(async (action: 'wearOutfit' | 'deleteOutfit' | 'saveOutfit', payload: Record<string, unknown>) => {
    if (busy) return;
    setBusy(true);
    const res = await nui<unknown>(action, payload);
    setBusy(false);
    if (!res.ok) { say('error', res.message ?? res.code ?? 'Failed'); return; }
    if (action === 'wearOutfit') { load(res.data as AppearanceOpen, true); say('success', 'Outfit on. Pay to keep it (saved pieces are free).'); return; }
    setData((d) => (d && d.store ? { ...d, store: { ...d.store, outfits: res.data as Outfit[] } } : d));
    if (action === 'saveOutfit') setOutfitName('');
    if (res.message) say('success', res.message);
  }, [busy, load, say]);

  // Keyboard: arrows change style / category, Q/E rotate, Esc closes (with a confirm when there are unpaid changes).
  useEffect(() => {
    if (!data) return;
    const onKey = (e: KeyboardEvent) => {
      const typing = (e.target as HTMLElement).tagName === 'INPUT' && (e.target as HTMLInputElement).type !== 'range';
      if (e.key === 'Escape') { if (typing) (e.target as HTMLElement).blur(); else if (confirmLeave) setConfirmLeave(false); else close(); return; }
      if (typing) return;
      const key = e.key.toLowerCase();
      if (key === 'q') rotate(-15);
      else if (key === 'e') rotate(15);
      else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        const list = filtered.map((c) => c.key);
        const i = list.indexOf(active);
        const next = list[(i + (e.key === 'ArrowDown' ? 1 : -1) + list.length) % list.length];
        if (next) { e.preventDefault(); select(next); }
      } else if ((e.key === 'ArrowLeft' || e.key === 'ArrowRight') && (e.target as HTMLElement).tagName !== 'INPUT') {
        const c = byKey[active];
        if (!c || !['component', 'prop', 'overlay'].includes(c.kind)) return;
        const v = data.values[active] ?? {};
        const min = c.kind === 'component' ? 0 : -1, max = c.max ?? 0;
        let d = (v.d ?? 0) + (e.key === 'ArrowRight' ? 1 : -1);
        if (d > max) d = min; if (d < min) d = max;
        e.preventDefault();
        void change(active, { ...v, d, t: 0 });
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [data, filtered, active, byKey, select, change, close, confirmLeave]);

  if (!data) return null;
  const cat = byKey[active];
  const store = data.store;
  const balance = store ? store.balances[method] : 0;
  const outfits = store?.outfits ?? null;

  return (
    <div className="ap-root">
      <header className="ap-header">
        <BrandHeader section={MODE_SECTION[data.mode]} />
        {data.allowCancel && <CloseHint onClose={close} />}
      </header>

      <div className="ap-left">
        <nav className="ap-rail v-panel" aria-label="Categories">
          <div className="ap-title">{data.title.toUpperCase()}</div>
          <div className="v-muted ap-sub">{data.subtitle}</div>
          {data.mode === 'create' && (
            <div className="ap-sex">
              <Tabs tabs={[{ id: 'm', label: 'Male' }, { id: 'f', label: 'Female' }]} value={data.sex}
                onChange={async (sex) => { const res = await nui<AppearanceOpen>('sex', { sex }); if (res.ok && res.data) load(res.data); }} />
            </div>
          )}
          <SearchBox value={search} onChange={setSearch} placeholder="Find a category…" />
          <div className="ap-cats v-scroll">
            {outfits !== null && !search && (
              <button className={`ap-cat${active === OUTFITS ? ' active' : ''}`} onClick={() => { setActive(OUTFITS); setCamera('full'); }}>
                <Icon name="hanger" size="1.05rem" /><span>Saved outfits</span><span className="ap-count">{outfits.length}</span>
              </button>
            )}
            {groups.length === 0 && <div className="v-muted ap-empty">No category matches “{search}”.</div>}
            {groups.map((g) => (
              <div key={g.group}>
                <div className="ap-group-title">{GROUP_LABELS[g.group]}</div>
                {g.items.map((c) => (
                  <button key={c.key} className={`ap-cat${active === c.key ? ' active' : ''}`} onClick={() => select(c.key)}>
                    <Icon name={c.icon} size="1.05rem" /><span>{c.label}</span>
                    {changed.has(c.key) && <span className="ap-dot" title="Changed" />}
                  </button>
                ))}
              </div>
            ))}
          </div>
        </nav>

        <section className="ap-editor v-panel" aria-live="polite">
          {active === OUTFITS && outfits !== null ? (
            <>
              <div className="ap-editor-head"><div className="ap-title">SAVED OUTFITS</div></div>
              <div className="ap-editor-body v-scroll">
                <p className="v-muted ap-help">Wear an outfit to try it on. Pieces from your saved outfits are free; pay to keep the look.</p>
                {outfits.length === 0 && <StateView kind="empty" message="No saved outfits yet." />}
                {outfits.map((o) => (
                  <div key={o.id} className="ap-outfit">
                    <Icon name="hanger" size="1.1rem" /><span className="name">{o.name}</span>
                    <button className="v-btn" disabled={busy} onClick={() => void outfitAction('wearOutfit', { id: o.id })}>Wear</button>
                    <button className="v-btn link" disabled={busy} aria-label={`Delete ${o.name}`} onClick={() => void outfitAction('deleteOutfit', { id: o.id })}><Icon name="close" size="0.95rem" /></button>
                  </div>
                ))}
                <div className="ap-outfit-save">
                  <div className="ap-group-title">Save what you're wearing</div>
                  <input className="v-input" placeholder="Outfit name" maxLength={32} value={outfitName} onChange={(e) => setOutfitName(e.target.value)} />
                  <button className="v-btn primary block" disabled={busy || !outfitName.trim() || changes.length > 0}
                    onClick={() => void outfitAction('saveOutfit', { name: outfitName.trim() })}>Save outfit</button>
                  {changes.length > 0 && <div className="v-muted ap-help">Pay for your changes first, then save them as an outfit.</div>}
                </div>
              </div>
            </>
          ) : cat ? (
            <>
              <div className="ap-editor-head">
                <Icon name={cat.icon} size="1.3rem" />
                <div className="ap-title">{cat.label.toUpperCase()}</div>
                {isStore && <span className="ap-price">{money(store!.prices[cat.key] ?? 0)}</span>}
                <button className="v-btn link ap-reset" disabled={!changed.has(cat.key)} onClick={() => reset(cat.key)}><Icon name="reset" size="0.95rem" /> Reset</button>
              </div>
              <div className="v-scroll ap-editor-scroll">
                {cat.kind === 'heritage' ? <HeritageEditor value={data.values[cat.key] ?? {}} onChange={(v) => void change(cat.key, v)} />
                  : cat.kind === 'features' ? <FeaturesEditor value={data.values[cat.key] ?? {}} onChange={(v) => void change(cat.key, v)} />
                  : cat.kind === 'eyes' ? <EyesEditor value={data.values[cat.key] ?? {}} onChange={(v) => void change(cat.key, v)} />
                  : <SlotEditor cat={cat} value={data.values[cat.key] ?? {}} palettes={data.palettes} onChange={(v) => void change(cat.key, v)} />}
              </div>
              <div className="ap-keys v-muted"><span><kbd>←</kbd><kbd>→</kbd> style</span><span><kbd>↑</kbd><kbd>↓</kbd> category</span><span><kbd>Q</kbd><kbd>E</kbd> turn</span></div>
            </>
          ) : <StateView kind="empty" />}
        </section>
      </div>

      <div className="ap-camera" role="toolbar" aria-label="Camera">
        <button className="v-btn" aria-label="Turn left" onClick={() => rotate(-30)}><Icon name="rotate_left" size="1.1rem" /></button>
        {FOCUS_LABELS.map((f) => (
          <button key={f.id} className={`v-btn${focus === f.id ? ' on' : ''}`} onClick={() => setCamera(f.id)}>{f.label}</button>
        ))}
        <button className="v-btn" aria-label="Turn right" onClick={() => rotate(30)}><Icon name="rotate_right" size="1.1rem" /></button>
      </div>

      <aside className="ap-summary v-panel">
        <div className="ap-title">{isStore ? 'YOUR CHANGES' : 'SUMMARY'}</div>
        <div className="ap-changes v-scroll">
          {changes.length === 0 && <div className="v-muted ap-help">{isStore ? 'Nothing changed yet. Pick a category on the left.' : 'No changes yet.'}</div>}
          {changes.map((c) => (
            <div key={c.cat.key} className="ap-change">
              <Icon name={c.cat.icon} size="1rem" /><button className="v-btn link ap-change-name" onClick={() => select(c.cat.key)}>{c.cat.label}</button>
              {isStore && <span className={c.free ? 'ap-free' : ''}>{c.free ? 'Owned' : money(c.price)}</span>}
              <button className="v-btn link" aria-label={`Undo ${c.cat.label}`} onClick={() => reset(c.cat.key)}><Icon name="reset" size="0.9rem" /></button>
            </div>
          ))}
        </div>
        {changes.length > 1 && <button className="v-btn link block" onClick={resetAll}>Undo all changes</button>}
        {isStore ? (
          <>
            <div className="ap-total"><span>Total</span><span>{money(total)}</span></div>
            <div className="ap-methods" role="radiogroup">
              {(['cash', 'bank'] as Method[]).map((m) => (
                <RadioCard key={m} label={m === 'cash' ? 'Cash' : 'Bank'} active={method === m} disabled={!store!.methods.includes(m) || busy} onSelect={() => setMethod(m)} />
              ))}
            </div>
            <div className={`v-muted ap-available${balance < total ? ' short' : ''}`}>{balance < total ? 'Not enough money · ' : ''}Available: {money(balance)}</div>
            <button className="v-btn primary block ap-pay" disabled={busy || changes.length === 0 || balance < total} onClick={() => void pay()}>
              {busy ? 'Processing…' : total > 0 ? `PAY ${money(total)} & SAVE` : 'SAVE LOOK'}
            </button>
          </>
        ) : (
          <button className="v-btn primary block ap-pay" disabled={busy} onClick={() => void finish()}>
            {busy ? 'Saving…' : data.mode === 'create' ? 'FINISH CHARACTER' : 'SAVE'}
          </button>
        )}
      </aside>

      {confirmLeave && (
        <div className="v-dialog-backdrop" role="dialog" aria-modal="true" aria-label="Leave without paying">
          <div className="v-panel ap-confirm">
            <div className="ap-title">LEAVE WITHOUT {isStore ? 'PAYING' : 'SAVING'}?</div>
            <p className="v-muted">Your {changes.length} change{changes.length === 1 ? '' : 's'} will be undone.</p>
            <div className="ap-confirm-row">
              <button className="v-btn" autoFocus onClick={() => setConfirmLeave(false)}>Keep shopping</button>
              <button className="v-btn primary" onClick={() => void nui('close')}>Leave</button>
            </div>
          </div>
        </div>
      )}
      {toast && <div className={`v-toast-inline ${toast.kind}`} role="alert"><Icon name={toast.kind === 'error' ? 'alert' : 'check'} size="1rem" />{toast.text}</div>}
    </div>
  );
}
