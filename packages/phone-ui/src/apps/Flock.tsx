// Flock: short public posts. One @handle per character; posts, replies, likes, follows and @mentions.
import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import { api } from '../api';
import { Ico } from '../icons';
import { useBack, useRouteOnce } from '../nav';
import { Avatar, Button, Empty, Header, Segmented, Sheet, Spinner, TextInput, cx, say } from '../ui';
import { ago, clientOp } from './kit';

type Post = { id: number; body: string; replyTo: number | null; likes: number; replies: number; at: number; handle: string; display: string; liked: boolean; mine: boolean; canDelete: boolean };
type Profile = { handle: string; display: string; bio?: string | null };
type Counts = { posts: number; followers: number; following: number };
type View = { k: 'feed' } | { k: 'thread'; id: number } | { k: 'user'; handle: string };

const LIMIT = 280;

export function FlockApp({ route }: { route?: string }) {
  const [me, setMe] = useState<{ profile: Profile | null; counts?: Counts } | null>(null);
  const [view, setView] = useState<View>({ k: 'feed' });
  const load = useCallback(async () => { const r = await api<{ profile: Profile | null; counts?: Counts }>('flockMe'); if (r.ok && r.data) setMe(r.data); }, []);
  useEffect(() => { void load(); }, [load]);
  useRouteOnce(route, (r) => { const m = /^p(\d+)$/.exec(r); if (m) setView({ k: 'thread', id: Number(m[1]) }); });
  useBack(view.k !== 'feed', () => { setView({ k: 'feed' }); return true; });

  if (!me) return <div className="ph-app"><Header title="Flock" /><Spinner /></div>;
  if (!me.profile) return <Setup onDone={(p) => setMe({ profile: p })} />;
  if (view.k === 'thread') return <Thread id={view.id} me={me.profile} onBack={() => setView({ k: 'feed' })} onUser={(h) => setView({ k: 'user', handle: h })} />;
  if (view.k === 'user') return <UserPage handle={view.handle} onBack={() => setView({ k: 'feed' })} onOpen={(id) => setView({ k: 'thread', id })} onUser={(h) => setView({ k: 'user', handle: h })} />;
  return <Feed me={me.profile} counts={me.counts} onOpen={(id) => setView({ k: 'thread', id })} onUser={(h) => setView({ k: 'user', handle: h })} onEditProfile={() => setMe({ ...me, profile: null })} />;
}

// ---------------------------------------------------------------------------
function Setup({ onDone }: { onDone: (p: Profile) => void }) {
  const [handle, setHandle] = useState('');
  const [display, setDisplay] = useState('');
  const [bio, setBio] = useState('');
  const [busy, setBusy] = useState(false);
  const ok = /^[a-z0-9_]{3,15}$/i.test(handle) && !busy;
  const save = async () => {
    setBusy(true);
    const r = await api<Profile>('flockSetup', handle, display, bio);
    setBusy(false);
    if (say(r) && r.data) onDone(r.data);
  };
  return (
    <div className="ph-app">
      <Header title="Flock" />
      <div className="ph-scroll ph-pad">
        <div className="ph-flockhero"><span><Ico name="bird" size={34} /></span><h2>Join the conversation</h2><p>Pick a handle. Everyone in the city can see your posts.</p></div>
        <div className="ph-form">
          <label>Handle<span className="ph-emailrow"><em>@</em><TextInput value={handle} onChange={(v) => setHandle(v.replace(/[^a-zA-Z0-9_]/g, '').slice(0, 15))} placeholder="yourname" autoFocus /></span></label>
          <label>Display name<TextInput value={display} onChange={setDisplay} placeholder="Your name" maxLength={32} /></label>
          <label>Bio (optional)<TextInput multiline value={bio} onChange={setBio} placeholder="A line about you" maxLength={120} /></label>
          <Button kind="primary" block onClick={save} disabled={!ok}>Create profile</Button>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
function Mentions({ text, onUser }: { text: string; onUser: (h: string) => void }) {
  const parts: ReactNode[] = [];
  text.split(/(@[A-Za-z0-9_]+)/g).forEach((p, i) => {
    if (/^@[A-Za-z0-9_]+$/.test(p)) parts.push(<button key={i} className="ph-mention" onClick={(e) => { e.stopPropagation(); onUser(p.slice(1).toLowerCase()); }}>{p}</button>);
    else if (p) parts.push(<span key={i}>{p}</span>);
  });
  return <>{parts}</>;
}

function PostCard({ p, onOpen, onUser, onChange, onRemove, detail }: { p: Post; onOpen?: () => void; onUser: (h: string) => void; onChange: (p: Post) => void; onRemove: (p: Post) => void; detail?: boolean }) {
  const like = async (e: React.MouseEvent) => {
    e.stopPropagation();
    const r = await api<{ likes: number; liked: boolean }>('flockLike', p.id, !p.liked);
    if (r.ok && r.data) onChange({ ...p, likes: r.data.likes, liked: r.data.liked }); else say(r);
  };
  return (
    <article className={cx('ph-post', detail && 'detail')} onClick={onOpen} role={onOpen ? 'button' : undefined} tabIndex={onOpen ? 0 : undefined}>
      <button className="ph-post-av" onClick={(e) => { e.stopPropagation(); onUser(p.handle); }} aria-label={`@${p.handle}`}><Avatar name={p.display} id={p.handle} size={detail ? 46 : 40} /></button>
      <div className="ph-post-main">
        <div className="ph-post-head"><strong>{p.display}</strong><em>@{p.handle}</em><time>{ago(p.at)}</time></div>
        <p><Mentions text={p.body} onUser={onUser} /></p>
        <div className="ph-post-actions">
          <button className={cx(p.liked && 'liked')} onClick={like} aria-label="Like"><Ico name="heart" size={16} style={p.liked ? { fill: 'currentColor' } : undefined} />{p.likes > 0 && p.likes}</button>
          <span><Ico name="chat" size={16} />{p.replies > 0 && p.replies}</span>
          {p.canDelete && <button className="push" onClick={(e) => { e.stopPropagation(); onRemove(p); }} aria-label="Delete post"><Ico name="trash" size={15} /></button>}
        </div>
      </div>
    </article>
  );
}

function Composer({ me, replyTo, placeholder, onPosted, autoFocus }: { me: Profile; replyTo?: number; placeholder: string; onPosted: (p: Post) => void; autoFocus?: boolean }) {
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const op = useRef(clientOp());
  const post = async () => {
    if (!text.trim() || busy) return;
    setBusy(true);
    const r = await api<Post>('flockPost', { body: text, replyTo, clientOp: op.current });
    setBusy(false);
    if (!say(r) || !r.data) return;
    op.current = clientOp(); setText(''); onPosted(r.data);
  };
  const left = LIMIT - text.length;
  return (
    <div className="ph-composer2">
      <Avatar name={me.display} id={me.handle} size={38} />
      <div>
        <TextInput multiline value={text} onChange={setText} placeholder={placeholder} maxLength={LIMIT} autoFocus={autoFocus} />
        <div className="ph-composer2-bar"><span className={cx('ph-sub', left < 20 && 'danger')}>{left}</span><Button kind="primary" onClick={post} disabled={!text.trim() || busy}>{replyTo ? 'Reply' : 'Post'}</Button></div>
      </div>
    </div>
  );
}

function useConfirmDelete(onDeleted: (p: Post) => void) {
  const [target, setTarget] = useState<Post | null>(null);
  const sheet = target && (
    <Sheet title="Delete this post?" onClose={() => setTarget(null)}>
      <div className="ph-form">
        <p className="ph-hint">It is removed for everyone.</p>
        <Button kind="danger" block onClick={async () => { if (say(await api('flockDelete', target.id))) { onDeleted(target); setTarget(null); } }}>Delete</Button>
        <Button kind="ghost" block onClick={() => setTarget(null)}>Cancel</Button>
      </div>
    </Sheet>
  );
  return { ask: setTarget, sheet };
}

// ---------------------------------------------------------------------------
function Feed({ me, counts, onOpen, onUser, onEditProfile }: { me: Profile; counts?: Counts; onOpen: (id: number) => void; onUser: (h: string) => void; onEditProfile: () => void }) {
  const [mode, setMode] = useState<'all' | 'following'>('all');
  const [posts, setPosts] = useState<Post[] | null>(null);
  const [next, setNext] = useState<number | undefined>();
  const load = useCallback(async (before?: number) => {
    const r = await api<{ items: Post[]; nextBefore?: number }>('flockFeed', mode, before);
    if (!r.ok || !r.data) return void say(r);
    setNext(r.data.nextBefore);
    setPosts((l) => (before ? [...(l ?? []), ...r.data!.items] : r.data!.items));
  }, [mode]);
  useEffect(() => { setPosts(null); void load(); }, [load]);
  const del = useConfirmDelete((p) => setPosts((l) => l?.filter((x) => x.id !== p.id) ?? null));

  return (
    <div className="ph-app">
      <Header title="Flock" right={<button className="ph-link" onClick={() => onUser(me.handle)}>@{me.handle}</button>} />
      <div className="ph-pad"><Segmented options={[{ id: 'all', label: 'For you' }, { id: 'following', label: 'Following' }]} value={mode} onChange={setMode} /></div>
      <div className="ph-scroll">
        <Composer me={me} placeholder="What is happening in Los Santos?" onPosted={(p) => setPosts((l) => [p, ...(l ?? [])])} />
        {posts === null && <Spinner />}
        {posts?.length === 0 && <Empty icon="bird" title={mode === 'following' ? 'Nothing from people you follow' : 'No posts yet'} text={mode === 'following' ? 'Follow people to fill this feed.' : 'Be the first to post.'} />}
        {posts?.map((p) => <PostCard key={p.id} p={p} onOpen={() => onOpen(p.id)} onUser={onUser} onChange={(n) => setPosts((l) => l?.map((x) => (x.id === n.id ? n : x)) ?? null)} onRemove={del.ask} />)}
        {next !== undefined && <button className="ph-more" onClick={() => void load(next)}>Load more</button>}
        {counts && <button className="ph-link ph-editprofile" onClick={onEditProfile}>Edit profile</button>}
      </div>
      {del.sheet}
    </div>
  );
}

function Thread({ id, me, onBack, onUser }: { id: number; me: Profile; onBack: () => void; onUser: (h: string) => void }) {
  const [data, setData] = useState<{ post: Post; replies: Post[] } | null>(null);
  const [gone, setGone] = useState(false);
  const load = useCallback(async () => {
    const r = await api<{ post: Post; replies: Post[] }>('flockThread', id);
    if (r.ok && r.data) setData(r.data); else setGone(true);
  }, [id]);
  useEffect(() => { void load(); }, [load]);
  const del = useConfirmDelete((p) => { if (p.id === id) onBack(); else void load(); });
  return (
    <div className="ph-app">
      <Header title="Post" onBack={onBack} backLabel="Flock" large={false} />
      <div className="ph-scroll">
        {gone && <Empty icon="x" title="This post was removed" />}
        {!data && !gone && <Spinner />}
        {data && (
          <>
            <PostCard p={data.post} detail onUser={onUser} onChange={(p) => setData({ ...data, post: p })} onRemove={del.ask} />
            <Composer me={me} replyTo={id} placeholder={`Reply to @${data.post.handle}`} onPosted={(r) => setData({ post: { ...data.post, replies: data.post.replies + 1 }, replies: [...data.replies, r] })} />
            {data.replies.map((r) => <PostCard key={r.id} p={r} onUser={onUser} onChange={(n) => setData({ ...data, replies: data.replies.map((x) => (x.id === n.id ? n : x)) })} onRemove={del.ask} />)}
          </>
        )}
      </div>
      {del.sheet}
    </div>
  );
}

function UserPage({ handle, onBack, onOpen, onUser }: { handle: string; onBack: () => void; onOpen: (id: number) => void; onUser: (h: string) => void }) {
  type U = { profile: Profile; counts: Counts; me: boolean; following: boolean; items: Post[]; nextBefore?: number };
  const [u, setU] = useState<U | null>(null);
  const [missing, setMissing] = useState(false);
  const load = useCallback(async () => { const r = await api<U>('flockUser', handle); if (r.ok && r.data) setU(r.data); else { setMissing(true); say(r); } }, [handle]);
  useEffect(() => { setU(null); setMissing(false); void load(); }, [load]);
  const del = useConfirmDelete(() => void load());
  const follow = async () => {
    if (!u) return;
    const r = await api<{ following: boolean; counts: Counts }>('flockFollow', handle, !u.following);
    if (r.ok && r.data) setU({ ...u, following: r.data.following, counts: r.data.counts }); else say(r);
  };
  return (
    <div className="ph-app">
      <Header onBack={onBack} backLabel="Flock" large={false} />
      <div className="ph-scroll">
        {missing && <Empty icon="user" title={`No one is using @${handle}`} />}
        {!u && !missing && <Spinner />}
        {u && (
          <>
            <div className="ph-profilehead">
              <Avatar name={u.profile.display} id={u.profile.handle} size={72} />
              <h2>{u.profile.display}</h2><em>@{u.profile.handle}</em>
              {u.profile.bio && <p>{u.profile.bio}</p>}
              <div className="ph-counts"><span><b>{u.counts.posts}</b> posts</span><span><b>{u.counts.followers}</b> followers</span><span><b>{u.counts.following}</b> following</span></div>
              {!u.me && <Button kind={u.following ? 'ghost' : 'primary'} onClick={follow}>{u.following ? 'Following' : 'Follow'}</Button>}
            </div>
            {u.items.length === 0 && <Empty icon="bird" title="No posts yet" />}
            {u.items.map((p) => <PostCard key={p.id} p={p} onOpen={() => onOpen(p.id)} onUser={onUser} onChange={(n) => setU({ ...u, items: u.items.map((x) => (x.id === n.id ? n : x)) })} onRemove={del.ask} />)}
          </>
        )}
      </div>
      {del.sheet}
    </div>
  );
}

