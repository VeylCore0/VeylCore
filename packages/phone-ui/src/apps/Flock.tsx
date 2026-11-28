// Flock: short public posts. Sign up or log in with a @handle and password (and log out again); posts, replies, likes, follows and @mentions.
import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import { api } from '../api';
import { Ico } from '../icons';
import { useBack, useRouteOnce } from '../nav';
import { Avatar, Button, Empty, Header, Segmented, Sheet, Spinner, TextInput, cx, say } from '../ui';
import { ago, clientOp } from './kit';

type Post = { id: number; body: string; replyTo: number | null; likes: number; replies: number; at: number; handle: string; display: string; liked: boolean; mine: boolean; canDelete: boolean };
type Profile = { handle: string; display: string; bio?: string | null };
type Me = { profile: Profile | null; counts?: Counts; legacy?: { handle: string; display: string } | null };
type Counts = { posts: number; followers: number; following: number };
type View = { k: 'feed' } | { k: 'thread'; id: number } | { k: 'user'; handle: string };

const LIMIT = 280;

export function FlockApp({ route }: { route?: string }) {
  const [me, setMe] = useState<Me | null>(null);
  const [view, setView] = useState<View>({ k: 'feed' });
  const load = useCallback(async () => { const r = await api<Me>('flockMe'); if (r.ok && r.data) setMe(r.data); }, []);
  useEffect(() => { void load(); }, [load]);
  useRouteOnce(route, (r) => { const m = /^p(\d+)$/.exec(r); if (m) setView({ k: 'thread', id: Number(m[1]) }); });
  useBack(view.k !== 'feed', () => { setView({ k: 'feed' }); return true; });

  if (!me) return <div className="ph-app"><Header title="Flock" /><Spinner /></div>;
  // Not logged in: sign up or log in first. Nothing else in Flock is reachable (the server refuses it too).
  if (!me.profile) return <Auth legacy={me.legacy ?? null} onDone={() => { setView({ k: 'feed' }); void load(); }} />;
  const loggedOut = () => { setView({ k: 'feed' }); void load(); };
  if (view.k === 'thread') return <Thread id={view.id} me={me.profile} onBack={() => setView({ k: 'feed' })} onUser={(h) => setView({ k: 'user', handle: h })} />;
  if (view.k === 'user') return <UserPage handle={view.handle} onBack={() => setView({ k: 'feed' })} onOpen={(id) => setView({ k: 'thread', id })} onUser={(h) => setView({ k: 'user', handle: h })} />;
  return <Feed me={me.profile} counts={me.counts} onOpen={(id) => setView({ k: 'thread', id })} onUser={(h) => setView({ k: 'user', handle: h })} onProfile={(p) => setMe({ ...me, profile: p })} onLoggedOut={loggedOut} />;
}

// ---------------------------------------------------------------------------
function Auth({ legacy, onDone }: { legacy: { handle: string; display: string } | null; onDone: () => void }) {
  const [mode, setMode] = useState<'login' | 'signup'>(legacy ? 'login' : 'signup');
  const [handle, setHandle] = useState('');
  const [display, setDisplay] = useState('');
  const [password, setPassword] = useState('');
  const [again, setAgain] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [claimPw, setClaimPw] = useState('');
  const [claimAgain, setClaimAgain] = useState('');
  const [claimError, setClaimError] = useState<string | null>(null);
  const cleanHandle = (v: string) => v.replace(/[^a-zA-Z0-9_]/g, '').slice(0, 15);
  const handleOk = /^[a-z0-9_]{3,15}$/i.test(handle);
  const pwOk = password.length >= 6 && password.length <= 64;
  const ok = !busy && (mode === 'login' ? handleOk && password.length > 0 : handleOk && pwOk && again === password);
  const submit = async () => {
    if (!ok) return;
    setBusy(true); setError(null);
    const r = mode === 'login' ? await api('flockLogin', handle, password) : await api('flockSignup', handle, display, password);
    setBusy(false);
    if (r.ok) { say(r); onDone(); } else setError(r.message ?? 'That did not work');
  };
  const claim = async () => {
    if (busy || claimPw.length < 6 || claimAgain !== claimPw) return;
    setBusy(true); setClaimError(null);
    const r = await api('flockClaim', claimPw);
    setBusy(false);
    if (r.ok) { say(r); onDone(); } else setClaimError(r.message ?? 'That did not work');
  };
  const switchTo = (m: 'login' | 'signup') => { setMode(m); setError(null); setPassword(''); setAgain(''); };

  return (
    <div className="ph-app">
      <Header title="Flock" />
      <div className="ph-scroll ph-pad">
        <div className="ph-flockhero"><span><Ico name="bird" size={34} /></span><h2>{mode === 'login' ? 'Welcome back' : 'Join the conversation'}</h2><p>{mode === 'login' ? 'Log in to see the feed and post.' : 'Create an account. Everyone in the city can see your posts.'}</p></div>
        {legacy && (
          <div className="ph-form ph-claim">
            <p className="ph-hint">You already have <b>@{legacy.handle}</b> on this character. Choose a password to keep it, or log in to a different account below.</p>
            <label>New password<TextInput type="password" value={claimPw} onChange={setClaimPw} placeholder="At least 6 characters" maxLength={64} /></label>
            <label>Repeat it<TextInput type="password" value={claimAgain} onChange={setClaimAgain} placeholder="Type it again" maxLength={64} onEnter={claim} /></label>
            <Button kind="primary" block onClick={claim} disabled={busy || claimPw.length < 6 || claimAgain !== claimPw}>Protect @{legacy.handle}</Button>
            {claimError && <p className="ph-error" role="alert">{claimError}</p>}
            <p className="ph-hint">Or use another account:</p>
          </div>
        )}
        <Segmented options={[{ id: 'signup', label: 'Sign up' }, { id: 'login', label: 'Log in' }]} value={mode} onChange={switchTo} />
        <div className="ph-form" style={{ marginTop: 14 }}>
          <label>Handle<span className="ph-emailrow"><em>@</em><TextInput value={handle} onChange={(v) => setHandle(cleanHandle(v))} placeholder="yourname" autoFocus={!legacy} /></span></label>
          {mode === 'signup' && <label>Display name<TextInput value={display} onChange={setDisplay} placeholder="Your name" maxLength={32} /></label>}
          <label>Password<TextInput type="password" value={password} onChange={setPassword} placeholder={mode === 'signup' ? 'At least 6 characters' : 'Your password'} maxLength={64} onEnter={mode === 'login' ? submit : undefined} /></label>
          {mode === 'signup' && <label>Repeat password<TextInput type="password" value={again} onChange={setAgain} placeholder="Type it again" maxLength={64} onEnter={submit} /></label>}
          {mode === 'signup' && password.length > 0 && again.length > 0 && again !== password && <p className="ph-error" role="alert">The passwords do not match</p>}
          {error && <p className="ph-error" role="alert">{error}</p>}
          <Button kind="primary" block onClick={submit} disabled={!ok}>{busy ? 'Please wait…' : mode === 'login' ? 'Log in' : 'Create account'}</Button>
          <button className="ph-link" onClick={() => switchTo(mode === 'login' ? 'signup' : 'login')}>{mode === 'login' ? 'New here? Sign up' : 'Have an account? Log in'}</button>
        </div>
      </div>
    </div>
  );
}

function EditProfile({ me, onClose, onSaved, onLogout }: { me: Profile; onClose: () => void; onSaved: (p: Profile) => void; onLogout: () => void }) {
  const [handle, setHandle] = useState(me.handle);
  const [display, setDisplay] = useState(me.display);
  const [bio, setBio] = useState(me.bio ?? '');
  const [busy, setBusy] = useState(false);
  const save = async () => {
    setBusy(true);
    const r = await api<Profile>('flockSetup', handle, display, bio);
    setBusy(false);
    if (say(r) && r.data) { onSaved(r.data); onClose(); }
  };
  return (
    <Sheet title="Your profile" onClose={onClose}>
      <div className="ph-form">
        <label>Handle<span className="ph-emailrow"><em>@</em><TextInput value={handle} onChange={(v) => setHandle(v.replace(/[^a-zA-Z0-9_]/g, '').slice(0, 15))} /></span></label>
        <label>Display name<TextInput value={display} onChange={setDisplay} maxLength={32} /></label>
        <label>Bio<TextInput multiline value={bio} onChange={setBio} maxLength={120} /></label>
        <Button kind="primary" block onClick={save} disabled={busy || !/^[a-z0-9_]{3,15}$/i.test(handle)}>Save</Button>
        <Button kind="danger" block onClick={onLogout}>Log out of @{me.handle}</Button>
      </div>
    </Sheet>
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
function Feed({ me, counts, onOpen, onUser, onProfile, onLoggedOut }: { me: Profile; counts?: Counts; onOpen: (id: number) => void; onUser: (h: string) => void; onProfile: (p: Profile) => void; onLoggedOut: () => void }) {
  const [editing, setEditing] = useState(false);
  const [confirmOut, setConfirmOut] = useState(false);
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
        {counts && <button className="ph-link ph-editprofile" onClick={() => setEditing(true)}>Edit profile or log out</button>}
      </div>
      {del.sheet}
      {editing && <EditProfile me={me} onClose={() => setEditing(false)} onSaved={onProfile} onLogout={() => { setEditing(false); setConfirmOut(true); }} />}
      {confirmOut && (
        <Sheet title="Log out of Flock?" onClose={() => setConfirmOut(false)}>
          <div className="ph-form">
            <p className="ph-hint">You will need @{me.handle} and its password to get back in. Your posts stay.</p>
            <Button kind="danger" block onClick={async () => { const r = await api('flockLogout'); if (say(r)) { setConfirmOut(false); onLoggedOut(); } }}>Log out</Button>
            <Button kind="ghost" block onClick={() => setConfirmOut(false)}>Stay logged in</Button>
          </div>
        </Sheet>
      )}
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

