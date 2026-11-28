// Marketplace: classified listings. The seller's number is on every listing: message or call them. No money moves here.
import { useCallback, useEffect, useState } from 'react';
import { api } from '../api';
import { openApp, startCall } from '../controller';
import { Ico } from '../icons';
import { Avatar, Button, Empty, Header, Sheet, Spinner, TextInput, say } from '../ui';
import { Chip, Fab, ago, clientOp, usd } from './kit';

type Listing = { id: number; title: string; body: string; price: number; category: string; number: string; display: string; seller: string; at: number; expires: number; mine: boolean; canDelete: boolean };
type Page = { items: Listing[]; nextBefore?: number; categories: string[] };

const ICON: Record<string, string> = { vehicles: 'car', items: 'box', services: 'wrench', property: 'home', other: 'bag' };
const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

export function MarketApp() {
  const [cat, setCat] = useState<string>('all');
  const [items, setItems] = useState<Listing[] | null>(null);
  const [cats, setCats] = useState<string[]>([]);
  const [next, setNext] = useState<number | undefined>();
  const [failed, setFailed] = useState(false);
  const [open, setOpen] = useState<Listing | null>(null);
  const [post, setPost] = useState(false);

  const load = useCallback(async (category: string, before?: number) => {
    const r = await api<Page>('marketList', category, before);
    if (!r.ok || !r.data) { setFailed(true); return; }
    setFailed(false); setCats(r.data.categories); setNext(r.data.nextBefore);
    setItems((l) => (before ? [...(l ?? []), ...r.data!.items] : r.data!.items));
  }, []);
  useEffect(() => { setItems(null); void load(cat); }, [cat, load]);

  return (
    <div className="ph-app">
      <Header title="Marketplace" />
      <div className="ph-chiprow" role="tablist">
        {['all', ...cats, 'mine'].map((c) => <Chip key={c} active={cat === c} icon={ICON[c]} onClick={() => setCat(c)}>{c === 'mine' ? 'My listings' : cap(c)}</Chip>)}
      </div>
      <div className="ph-scroll ph-pad">
        {items === null && !failed && <Spinner />}
        {failed && items === null && <Empty icon="x" title="Could not load listings" action={<Button onClick={() => void load(cat)}>Try again</Button>} />}
        {items?.length === 0 && <Empty icon="bag" title={cat === 'mine' ? 'You have no listings' : 'Nothing here yet'} text="Be the first to post something." action={<Button kind="primary" onClick={() => setPost(true)}>Post a listing</Button>} />}
        <div className="ph-listings">
          {items?.map((l) => (
            <button key={l.id} className="ph-listing" onClick={() => setOpen(l)}>
              <span className="ph-listing-ico"><Ico name={ICON[l.category] ?? 'bag'} size={22} /></span>
              <span className="ph-listing-main"><strong>{l.title}</strong><em>{l.seller} · {ago(l.at)}</em>{l.body && <span>{l.body}</span>}</span>
              <span className="ph-listing-price">{l.price === 0 ? 'Free' : usd(l.price)}</span>
            </button>
          ))}
        </div>
        {next !== undefined && <button className="ph-more" onClick={() => void load(cat, next)}>Load more</button>}
      </div>
      <Fab label="Post a listing" onClick={() => setPost(true)} />
      {open && <Detail l={open} onClose={() => setOpen(null)} onRemoved={() => { setOpen(null); void load(cat); }} />}
      {post && <PostSheet cats={cats} onClose={() => setPost(false)} onPosted={() => { setPost(false); setCat('mine'); }} />}
    </div>
  );
}

function Detail({ l, onClose, onRemoved }: { l: Listing; onClose: () => void; onRemoved: () => void }) {
  const remove = async () => { if (say(await api('marketDelete', l.id))) onRemoved(); };
  return (
    <Sheet title={l.category ? cap(l.category) : 'Listing'} onClose={onClose}>
      <div className="ph-listdetail">
        <div className="ph-listdetail-price">{l.price === 0 ? 'Free' : usd(l.price)}</div>
        <h3>{l.title}</h3>
        {l.body && <p>{l.body}</p>}
        <div className="ph-seller"><Avatar name={l.seller} id={l.number} size={42} /><span><strong>{l.seller}</strong><em>{l.display} · posted {ago(l.at)} ago</em></span></div>
        {!l.mine && (
          <div className="ph-listdetail-actions">
            <Button kind="primary" onClick={() => { onClose(); openApp('messages', `to/${l.number}`); }}><Ico name="chat" size={16} /> Message</Button>
            <Button onClick={() => { onClose(); void startCall(l.number); }}><Ico name="phone" size={16} /> Call</Button>
          </div>
        )}
        {l.canDelete && <Button kind="danger" block onClick={remove}><Ico name="trash" size={16} /> {l.mine ? 'Remove my listing' : 'Remove (staff)'}</Button>}
      </div>
    </Sheet>
  );
}

function PostSheet({ cats, onClose, onPosted }: { cats: string[]; onClose: () => void; onPosted: () => void }) {
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [price, setPrice] = useState('');
  const [category, setCategory] = useState(cats[0] ?? 'other');
  const [busy, setBusy] = useState(false);
  const op = useState(clientOp)[0];
  const ok = title.trim().length > 0 && price !== '' && !busy;
  const submit = async () => {
    setBusy(true);
    const r = await api('marketPost', { title, body, price: Number(price), category, clientOp: op });
    setBusy(false);
    if (say(r)) onPosted();
  };
  return (
    <Sheet title="New listing" onClose={onClose}>
      <div className="ph-form">
        <label>Title<TextInput value={title} onChange={setTitle} placeholder="What are you selling?" maxLength={48} autoFocus /></label>
        <label>Price<span className="ph-emailrow"><em>$</em><TextInput value={price} onChange={(v) => setPrice(v.replace(/\D/g, '').slice(0, 8))} inputMode="numeric" placeholder="0 for free" /></span></label>
        <div className="ph-chiprow flush">{cats.map((c) => <Chip key={c} active={category === c} icon={ICON[c]} onClick={() => setCategory(c)}>{cap(c)}</Chip>)}</div>
        <label>Description<TextInput multiline value={body} onChange={setBody} placeholder="Condition, details, where to meet" maxLength={300} /></label>
        <Button kind="primary" block onClick={submit} disabled={!ok}>{busy ? 'Posting...' : 'Post listing'}</Button>
        <p className="ph-hint">Your phone number is shown so buyers can reach you. Listings last a week.</p>
      </div>
    </Sheet>
  );
}

