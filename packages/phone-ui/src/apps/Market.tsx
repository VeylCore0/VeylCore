import { useCallback, useEffect, useState } from 'react';
import { Icon } from '@veyl/ui';
import { api, newClientOp } from '../api';
import { AppHeader, usePhone } from '../App';
import { timeAgo } from '../types';

interface Listing { id: number; title: string; body: string; price: number; category: string; number: string; display: string; seller?: string; at: number; expires: number; mine: boolean; canDelete: boolean }
type View = { kind: 'list' } | { kind: 'detail'; item: Listing } | { kind: 'new' };
const LABEL: Record<string, string> = { all: 'All', vehicles: 'Vehicles', items: 'Items', services: 'Services', property: 'Property', other: 'Other', mine: 'My listings' };
const CAT_ICON: Record<string, string> = { vehicles: 'car', items: 'box', services: 'wrench', property: 'home', other: 'tag' };
const price = (n: number) => (n === 0 ? 'Free' : `$${n.toLocaleString('en-US')}`);

export function MarketApp() {
  const { toast, go, startCall } = usePhone();
  const [cat, setCat] = useState('all');
  const [cats, setCats] = useState<string[]>(['vehicles', 'items', 'services', 'property', 'other']);
  const [items, setItems] = useState<Listing[] | null>(null);
  const [next, setNext] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [view, setView] = useState<View>({ kind: 'list' });
  const load = useCallback(async (before?: number) => {
    const r = await api<{ items: Listing[]; nextBefore: number | null; categories: string[] }>('marketList', cat, before);
    if (!r.ok || !r.data) { setError(r.message ?? 'Could not load listings'); return; }
    setError(null); setCats(r.data.categories);
    setItems((c) => (before ? [...(c ?? []), ...r.data!.items] : r.data!.items)); setNext(r.data.nextBefore);
  }, [cat]);
  useEffect(() => { setItems(null); void load(); }, [load]);

  if (view.kind === 'new') return <NewListing cats={cats} onBack={() => setView({ kind: 'list' })} onPosted={(l) => { setItems((c) => [l, ...(c ?? [])]); setView({ kind: 'detail', item: l }); }} />;
  if (view.kind === 'detail') {
    const l = view.item;
    const remove = async () => {
      const r = await api('marketDelete', l.id);
      toast(r.message ?? (r.ok ? 'Removed' : 'Failed'), r.ok ? 'ok' : 'error');
      if (r.ok) { setItems((c) => c?.filter((x) => x.id !== l.id) ?? c); setView({ kind: 'list' }); }
    };
    return (
      <div className="ph-appview">
        <AppHeader title={LABEL[l.category] ?? 'Listing'} onBack={() => setView({ kind: 'list' })} />
        <div className="ph-body">
          <div className="mk-hero"><Icon name={CAT_ICON[l.category] ?? 'tag'} size="2.4rem" /></div>
          <div className="mk-title">{l.title}</div>
          <div className="mk-price">{price(l.price)}</div>
          {l.body && <p className="mk-body">{l.body}</p>}
          <div className="mk-seller"><span className="muted">Seller</span><strong>{l.seller ?? 'Resident'}</strong><span className="muted">{l.display} · {timeAgo(l.at)}</span></div>
          {!l.mine && (
            <div className="mk-contact">
              <button className="ph-btn primary" onClick={() => go('messages', `n${l.number}`)}><Icon name="chat" size="0.9rem" /> Message</button>
              <button className="ph-btn" onClick={() => void startCall(l.number)}><Icon name="call" size="0.9rem" /> Call</button>
            </div>
          )}
          {l.canDelete && <button className="ph-btn danger block" onClick={() => void remove()}>{l.mine ? 'Remove my listing' : 'Remove listing (staff)'}</button>}
          <div className="ph-help">Meet up to trade. Payments are not handled by the app, so be careful.</div>
        </div>
      </div>
    );
  }

  return (
    <div className="ph-appview">
      <AppHeader title="Marketplace" right={<button className="ph-icon-btn" aria-label="New listing" onClick={() => setView({ kind: 'new' })}><Icon name="plus" size="1.1rem" /></button>} />
      <div className="ph-chips mk-chips">{['all', ...cats, 'mine'].map((c) => <button key={c} className={`ph-chip${cat === c ? ' on' : ''}`} onClick={() => setCat(c)}>{LABEL[c] ?? c}</button>)}</div>
      <div className="ph-body">
        {error && <div className="ph-empty">{error}<br /><button className="ph-link" onClick={() => void load()}>Retry</button></div>}
        {!error && items === null && <div className="ph-empty">Loading…</div>}
        {items?.length === 0 && <div className="ph-empty">{cat === 'mine' ? 'You have no active listings.' : 'Nothing listed here yet.'}<br /><button className="ph-link" onClick={() => setView({ kind: 'new' })}>Post a listing</button></div>}
        <div className="mk-grid">
          {items?.map((l) => (
            <button key={l.id} className="mk-card" onClick={() => setView({ kind: 'detail', item: l })}>
              <span className="mk-card-icon"><Icon name={CAT_ICON[l.category] ?? 'tag'} size="1.3rem" /></span>
              <span className="mk-card-title">{l.title}</span>
              <span className="mk-card-price">{price(l.price)}</span>
              <span className="muted mk-card-meta">{timeAgo(l.at)}{l.mine ? ' · yours' : ''}</span>
            </button>
          ))}
        </div>
        {next && <button className="ph-link fl-more" onClick={() => void load(next)}>Load more</button>}
      </div>
    </div>
  );
}

function NewListing({ cats, onBack, onPosted }: { cats: string[]; onBack: () => void; onPosted: (l: Listing) => void }) {
  const { toast } = usePhone();
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [amount, setAmount] = useState('');
  const [category, setCategory] = useState(cats[0] ?? 'items');
  const [busy, setBusy] = useState(false);
  const [op] = useState(newClientOp);
  const post = async () => {
    setBusy(true);
    const r = await api<Listing>('marketPost', { title, body, price: Number(amount || 0), category, clientOp: op });
    setBusy(false);
    if (!r.ok || !r.data) { toast(r.message ?? 'Could not post', 'error'); return; }
    toast(r.message ?? 'Posted'); onPosted(r.data);
  };
  return (
    <div className="ph-appview">
      <AppHeader title="New listing" onBack={onBack} />
      <div className="ph-body">
        <label className="ph-field">Title<input className="ph-input" autoFocus maxLength={48} value={title} onChange={(e) => setTitle(e.target.value)} placeholder="What are you selling?" /></label>
        <label className="ph-field">Price<div className="bk-amount"><span>$</span><input className="ph-input" inputMode="numeric" value={amount} onChange={(e) => setAmount(e.target.value.replace(/\D/g, '').slice(0, 8))} placeholder="0 = free" /></div></label>
        <div className="ph-field">Category<div className="ph-chips">{cats.map((c) => <button key={c} className={`ph-chip${category === c ? ' on' : ''}`} onClick={() => setCategory(c)}>{LABEL[c] ?? c}</button>)}</div></div>
        <label className="ph-field">Description<textarea className="ph-input" rows={4} maxLength={300} value={body} onChange={(e) => setBody(e.target.value)} placeholder="Condition, where to meet, etc." /></label>
        <div className="ph-help">Your phone number is shown so buyers can contact you. Listings last 7 days.</div>
        <button className="ph-btn primary block" disabled={!title.trim() || busy} onClick={() => void post()}>{busy ? 'Posting…' : 'Post listing'}</button>
      </div>
    </div>
  );
}
