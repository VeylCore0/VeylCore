import { useCallback, useEffect, useRef, useState } from 'react';
import { Icon } from '@veyl/ui';
import { api, newClientOp } from '../api';
import { AppHeader, usePhone } from '../App';
import { initials, timeAgo } from '../types';

interface Post { id: number; body: string; replyTo?: number | null; likes: number; replies: number; at: number; handle: string; display: string; liked: boolean; mine: boolean; canDelete: boolean }
interface Profile { handle: string; display: string; bio?: string | null }
interface Counts { posts: number; followers: number; following: number }
type View = { kind: 'feed' } | { kind: 'thread'; id: number } | { kind: 'user'; handle: string } | { kind: 'edit' };

const LIMIT = 280;

/** Renders post text with @handles as links. */
function Body({ text, onUser }: { text: string; onUser: (h: string) => void }) {
  const parts = text.split(/(@[A-Za-z0-9_]+)/g);
  return <p className="fl-body">{parts.map((p, i) => (p.startsWith('@') ? <button key={i} className="fl-mention" onClick={(e) => { e.stopPropagation(); onUser(p.slice(1)); }}>{p}</button> : p))}</p>;
}

function Avatar({ name, size = 'md' }: { name: string; size?: 'md' | 'lg' }) {
  let h = 0; for (const c of name) h = (h * 31 + c.charCodeAt(0)) % 360;
  return <span className={`fl-avatar ${size}`} style={{ background: `hsl(${h} 45% 42%)` }}>{initials(name)}</span>;
}

function PostCard({ p, onOpen, onUser, onLike, onDelete }: { p: Post; onOpen?: () => void; onUser: (h: string) => void; onLike: (p: Post) => void; onDelete: (p: Post) => void }) {
  return (
    <article className={`fl-post${onOpen ? ' clickable' : ''}`} onClick={onOpen}>
      <button className="fl-av-btn" onClick={(e) => { e.stopPropagation(); onUser(p.handle); }} aria-label={`@${p.handle}`}><Avatar name={p.display} /></button>
      <div className="fl-main">
        <div className="fl-meta"><strong>{p.display}</strong><span className="muted">@{p.handle} · {timeAgo(p.at)}</span></div>
        <Body text={p.body} onUser={onUser} />
        <div className="fl-actions">
          <span className="fl-act"><Icon name="chat" size="0.85rem" />{p.replies > 0 ? p.replies : ''}</span>
          <button className={`fl-act${p.liked ? ' liked' : ''}`} onClick={(e) => { e.stopPropagation(); onLike(p); }} aria-label={p.liked ? 'Unlike' : 'Like'}>
            <Icon name="heart" size="0.85rem" />{p.likes > 0 ? p.likes : ''}
          </button>
          {p.canDelete && <button className="fl-act danger" onClick={(e) => { e.stopPropagation(); onDelete(p); }} aria-label="Delete post"><Icon name="close" size="0.85rem" /></button>}
        </div>
      </div>
    </article>
  );
}

function Composer({ placeholder, onSend, autoFocus }: { placeholder: string; onSend: (text: string) => Promise<boolean>; autoFocus?: boolean }) {
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const left = LIMIT - text.length;
  const send = async () => {
    if (!text.trim() || busy || left < 0) return;
    setBusy(true);
    if (await onSend(text.trim())) setText('');
    setBusy(false);
  };
  return (
    <div className="fl-compose">
      <textarea className="ph-input" rows={2} maxLength={LIMIT + 20} placeholder={placeholder} value={text} autoFocus={autoFocus}
        onChange={(e) => setText(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); void send(); } }} />
      <div className="fl-compose-row">
        <span className={`fl-left${left < 20 ? ' warn' : ''}`}>{left}</span>
        <button className="ph-btn primary" disabled={busy || !text.trim() || left < 0} onClick={() => void send()}>{busy ? 'Posting…' : 'Post'}</button>
      </div>
    </div>
  );
}

export function FlockApp() {
  const { route, toast } = usePhone();
  const [me, setMe] = useState<{ profile: Profile | null; counts: Counts | null } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [view, setView] = useState<View>(route.startsWith('p') && Number(route.slice(1)) ? { kind: 'thread', id: Number(route.slice(1)) } : { kind: 'feed' });

  const loadMe = useCallback(async () => {
    const r = await api<{ profile: Profile | null; counts: Counts | null }>('flockMe');
    if (r.ok && r.data) { setMe(r.data); setError(null); } else setError(r.message ?? 'Flock is unavailable');
  }, []);
  useEffect(() => { void loadMe(); }, [loadMe]);

  const like = async (p: Post, update: (fn: (p: Post) => Post) => void) => {
    const on = !p.liked;
    update((x) => ({ ...x, liked: on, likes: x.likes + (on ? 1 : -1) }));
    const r = await api<{ likes: number; liked: boolean }>('flockLike', p.id, on);
    if (r.ok && r.data) update((x) => ({ ...x, liked: r.data!.liked, likes: r.data!.likes }));
    else { update((x) => ({ ...x, liked: p.liked, likes: p.likes })); toast(r.message ?? 'Could not like', 'error'); }
  };
  const remove = async (p: Post) => {
    const r = await api('flockDelete', p.id);
    toast(r.message ?? (r.ok ? 'Deleted' : 'Failed'), r.ok ? 'ok' : 'error');
    return r.ok;
  };

  if (error) return <div className="ph-appview"><AppHeader title="Flock" /><div className="ph-empty">{error}<br /><button className="ph-link" onClick={() => void loadMe()}>Retry</button></div></div>;
  if (!me) return <div className="ph-appview"><AppHeader title="Flock" /><div className="ph-empty">Loading…</div></div>;
  if (!me.profile || view.kind === 'edit') return <Setup current={me.profile} onDone={() => { void loadMe(); setView({ kind: 'feed' }); }} onCancel={me.profile ? () => setView({ kind: 'feed' }) : undefined} />;

  const openUser = (h: string) => setView({ kind: 'user', handle: h.toLowerCase() });
  if (view.kind === 'thread') return <Thread id={view.id} onBack={() => setView({ kind: 'feed' })} onUser={openUser} like={like} remove={remove} />;
  if (view.kind === 'user') return <UserView handle={view.handle} onBack={() => setView({ kind: 'feed' })} onUser={openUser} onOpen={(id) => setView({ kind: 'thread', id })} like={like} remove={remove} onEdit={() => setView({ kind: 'edit' })} />;
  return <Feed me={me.profile} onOpen={(id) => setView({ kind: 'thread', id })} onUser={openUser} like={like} remove={remove} />;
}

type LikeFn = (p: Post, update: (fn: (p: Post) => Post) => void) => Promise<void>;

function usePostList() {
  const [items, setItems] = useState<Post[] | null>(null);
  const update = (id: number) => (fn: (p: Post) => Post) => setItems((list) => list?.map((x) => (x.id === id ? fn(x) : x)) ?? list);
  return { items, setItems, update };
}

function Feed({ me, onOpen, onUser, like, remove }: { me: Profile; onOpen: (id: number) => void; onUser: (h: string) => void; like: LikeFn; remove: (p: Post) => Promise<boolean> }) {
  const { toast } = usePhone();
  const [mode, setMode] = useState<'all' | 'following'>('all');
  const { items, setItems, update } = usePostList();
  const [next, setNext] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [compose, setCompose] = useState(false);
  const load = useCallback(async (before?: number) => {
    const r = await api<{ items: Post[]; nextBefore: number | null }>('flockFeed', mode, before);
    if (!r.ok || !r.data) { setError(r.message ?? 'Could not load the feed'); return; }
    setError(null);
    setItems((cur) => (before ? [...(cur ?? []), ...r.data!.items] : r.data!.items));
    setNext(r.data.nextBefore);
  }, [mode, setItems]);
  useEffect(() => { setItems(null); void load(); }, [load, setItems]);

  const post = async (body: string) => {
    const r = await api<Post>('flockPost', { body, clientOp: newClientOp() });
    if (!r.ok || !r.data) { toast(r.message ?? 'Could not post', 'error'); return false; }
    setItems((cur) => [r.data!, ...(cur ?? [])]);
    setCompose(false);
    return true;
  };

  return (
    <div className="ph-appview fl">
      <AppHeader title={<span className="fl-title"><Icon name="bird" size="1rem" /> Flock</span>}
        right={<button className="ph-icon-btn" aria-label="My profile" onClick={() => onUser(me.handle)}><Icon name="user" size="1rem" /></button>} />
      <div className="ph-seg fl-seg"><button className={mode === 'all' ? 'on' : ''} onClick={() => setMode('all')}>Everyone</button><button className={mode === 'following' ? 'on' : ''} onClick={() => setMode('following')}>Following</button></div>
      <div className="ph-body fl-list">
        {compose && <Composer placeholder="What's happening in the city?" onSend={post} autoFocus />}
        {error && <div className="ph-empty">{error}<br /><button className="ph-link" onClick={() => void load()}>Retry</button></div>}
        {!error && items === null && <div className="ph-empty">Loading…</div>}
        {items?.length === 0 && <div className="ph-empty">{mode === 'following' ? 'Follow people to see their posts here.' : 'No posts yet. Be the first!'}</div>}
        {items?.map((p) => <PostCard key={p.id} p={p} onOpen={() => onOpen(p.id)} onUser={onUser} onLike={(x) => void like(x, update(x.id))}
          onDelete={(x) => void remove(x).then((ok) => ok && setItems((c) => c?.filter((y) => y.id !== x.id) ?? c))} />)}
        {next && <button className="ph-link fl-more" onClick={() => void load(next)}>Load more</button>}
      </div>
      {!compose && <button className="fl-fab" aria-label="New post" onClick={() => setCompose(true)}><Icon name="edit" size="1.2rem" /></button>}
    </div>
  );
}

function Thread({ id, onBack, onUser, like, remove }: { id: number; onBack: () => void; onUser: (h: string) => void; like: LikeFn; remove: (p: Post) => Promise<boolean> }) {
  const { toast } = usePhone();
  const [post, setPost] = useState<Post | null>(null);
  const { items: replies, setItems: setReplies, update } = usePostList();
  const [error, setError] = useState<string | null>(null);
  const load = useCallback(async () => {
    const r = await api<{ post: Post; replies: Post[] }>('flockThread', id);
    if (!r.ok || !r.data) { setError(r.message ?? 'Could not load'); return; }
    setPost(r.data.post); setReplies(r.data.replies); setError(null);
  }, [id, setReplies]);
  useEffect(() => { void load(); }, [load]);
  const reply = async (body: string) => {
    const r = await api<Post>('flockPost', { body, replyTo: id, clientOp: newClientOp() });
    if (!r.ok || !r.data) { toast(r.message ?? 'Could not reply', 'error'); return false; }
    setReplies((c) => [...(c ?? []), r.data!]);
    setPost((p) => (p ? { ...p, replies: p.replies + 1 } : p));
    return true;
  };
  return (
    <div className="ph-appview fl">
      <AppHeader title="Post" onBack={onBack} />
      <div className="ph-body fl-list">
        {error && <div className="ph-empty">{error}</div>}
        {post && <PostCard p={post} onUser={onUser} onLike={(x) => void like(x, (fn) => setPost((p) => (p ? fn(p) : p)))} onDelete={(x) => void remove(x).then((ok) => ok && onBack())} />}
        {post && <Composer placeholder={`Reply to @${post.handle}`} onSend={reply} />}
        {replies?.map((p) => <PostCard key={p.id} p={p} onUser={onUser} onLike={(x) => void like(x, update(x.id))}
          onDelete={(x) => void remove(x).then((ok) => { if (ok) { setReplies((c) => c?.filter((y) => y.id !== x.id) ?? c); setPost((q) => (q ? { ...q, replies: Math.max(0, q.replies - 1) } : q)); } })} />)}
      </div>
    </div>
  );
}

function UserView({ handle, onBack, onUser, onOpen, like, remove, onEdit }: { handle: string; onBack: () => void; onUser: (h: string) => void; onOpen: (id: number) => void; like: LikeFn; remove: (p: Post) => Promise<boolean>; onEdit: () => void }) {
  const { toast } = usePhone();
  const [data, setData] = useState<{ profile: Profile; counts: Counts; me: boolean; following: boolean } | null>(null);
  const { items, setItems, update } = usePostList();
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    setData(null); setItems(null);
    void api<{ profile: Profile; counts: Counts; me: boolean; following: boolean; items: Post[] }>('flockUser', handle).then((r) => {
      if (!r.ok || !r.data) { setError(r.message ?? 'Could not load'); return; }
      setData(r.data); setItems(r.data.items); setError(null);
    });
  }, [handle, setItems]);
  const follow = async () => {
    if (!data) return;
    const r = await api<{ following: boolean; counts: Counts }>('flockFollow', handle, !data.following);
    if (r.ok && r.data) setData({ ...data, following: r.data.following, counts: r.data.counts }); else toast(r.message ?? 'Failed', 'error');
  };
  return (
    <div className="ph-appview fl">
      <AppHeader title={`@${handle}`} onBack={onBack} />
      <div className="ph-body fl-list">
        {error && <div className="ph-empty">{error}</div>}
        {data && (
          <div className="fl-profile">
            <Avatar name={data.profile.display} size="lg" />
            <div className="fl-pname">{data.profile.display}</div>
            <div className="muted">@{data.profile.handle}</div>
            {data.profile.bio && <p className="fl-bio">{data.profile.bio}</p>}
            <div className="fl-counts"><span><strong>{data.counts.posts}</strong> posts</span><span><strong>{data.counts.followers}</strong> followers</span><span><strong>{data.counts.following}</strong> following</span></div>
            {data.me ? <button className="ph-btn" onClick={onEdit}>Edit profile</button>
              : <button className={`ph-btn${data.following ? '' : ' primary'}`} onClick={() => void follow()}>{data.following ? 'Following' : 'Follow'}</button>}
          </div>
        )}
        {items?.length === 0 && <div className="ph-empty">No posts yet.</div>}
        {items?.map((p) => <PostCard key={p.id} p={p} onOpen={() => onOpen(p.id)} onUser={onUser} onLike={(x) => void like(x, update(x.id))}
          onDelete={(x) => void remove(x).then((ok) => ok && setItems((c) => c?.filter((y) => y.id !== x.id) ?? c))} />)}
      </div>
    </div>
  );
}

function Setup({ current, onDone, onCancel }: { current: Profile | null; onDone: () => void; onCancel?: () => void }) {
  const { session, toast } = usePhone();
  const [handle, setHandle] = useState(current?.handle ?? session.name.toLowerCase().replace(/[^a-z0-9_]/g, '').slice(0, 15));
  const [display, setDisplay] = useState(current?.display ?? session.name);
  const [bio, setBio] = useState(current?.bio ?? '');
  const [busy, setBusy] = useState(false);
  const ref = useRef<HTMLInputElement>(null);
  useEffect(() => ref.current?.focus(), []);
  const valid = /^[A-Za-z0-9_]{3,15}$/.test(handle);
  const save = async () => {
    setBusy(true);
    const r = await api('flockSetup', handle, display, bio);
    setBusy(false);
    if (!r.ok) { toast(r.message ?? 'Could not save', 'error'); return; }
    onDone();
  };
  return (
    <div className="ph-appview fl">
      <AppHeader title={current ? 'Edit profile' : 'Join Flock'} onBack={onCancel} />
      <div className="ph-body fl-setup">
        {!current && <div className="fl-welcome"><Icon name="bird" size="2.4rem" /><p>Pick a handle so people can find and mention you.</p></div>}
        <label className="ph-field">Handle<div className="fl-handle"><span>@</span><input ref={ref} className="ph-input" value={handle} maxLength={15} onChange={(e) => setHandle(e.target.value.replace(/[^A-Za-z0-9_]/g, ''))} /></div></label>
        {!valid && <div className="ph-help">3-15 letters, numbers or _</div>}
        <label className="ph-field">Display name<input className="ph-input" value={display} maxLength={32} onChange={(e) => setDisplay(e.target.value)} /></label>
        <label className="ph-field">Bio<textarea className="ph-input" rows={3} value={bio} maxLength={120} onChange={(e) => setBio(e.target.value)} placeholder="Optional" /></label>
        <button className="ph-btn primary block" disabled={!valid || busy} onClick={() => void save()}>{busy ? 'Saving…' : current ? 'Save' : 'Join'}</button>
      </div>
    </div>
  );
}
