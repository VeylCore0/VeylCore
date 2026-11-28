// Messages: conversation list, threads (direct + group), new chat, location and contact cards, read receipts.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { api, newOp, post } from '../api';
import { onPush, openApp, setActiveThread, startCall } from '../controller';
import { dayLabel, listTime, sameDay, timeOfDay } from '../format';
import { Ico } from '../icons';
import { useBack, useRouteOnce } from '../nav';
import { getState, setState, useStore } from '../store';
import { Avatar, Button, Empty, Group, Header, IconButton, Row, SearchField, Sheet, Spinner, TextInput, cx, say, toast } from '../ui';
import type { Contact, Conversation, Message } from '../types';
import { GalleryPicker, PhotoSheet, useContactPhotos, useGalleryImage, useMessagePhoto } from './photos';

const SYSTEM_NUMBER = '0000000';
type View = { k: 'list' } | { k: 'new' } | { k: 'thread'; id: number | null; to?: string; title?: string };

/** The reserved number 000-0000 sends texts from city services (taxi, deliveries...). */
const titleOf = (c: Conversation) => (c.peer === SYSTEM_NUMBER ? 'City Services' : c.title);

const previewOf = (m: Message | null) => {
  if (!m) return 'No messages yet';
  const t = m.kind === 'location' ? 'Shared a location' : m.kind === 'contact' ? `Contact: ${m.body}` : m.kind === 'photo' ? (m.body && m.body !== 'Photo' ? `📷 ${m.body}` : '📷 Photo') : m.body;
  return `${m.mine ? 'You: ' : ''}${t}`;
};

async function markRead(id: number) {
  const res = await api<{ unread: number }>('read', id);
  if (!res.ok) return;
  setState((s) => ({
    unread: { ...s.unread, messages: res.data?.unread ?? s.unread.messages },
    conversations: s.conversations?.map((c) => (c.id === id ? { ...c, unread: 0 } : c)) ?? null,
  }));
}

export function MessagesApp({ route }: { route?: string }) {
  const { photoOf } = useContactPhotos();
  const [view, setView] = useState<View>({ k: 'list' });
  const conversations = useStore((s) => s.conversations);
  const [failed, setFailed] = useState(false);
  const [q, setQ] = useState('');

  const load = useCallback(async () => {
    const res = await api<Conversation[]>('conversations');
    if (res.ok && res.data) { setState({ conversations: res.data }); setFailed(false); } else setFailed(true);
  }, []);
  useEffect(() => { void load(); }, [load]);

  // Deep links: thread/<id> (notification tap) and to/<number> (from a call or contact).
  useRouteOnce(route, (r) => {
    const t = /^thread\/(\d+)$/.exec(r), to = /^to\/(\d{7})$/.exec(r);
    if (t) setView({ k: 'thread', id: Number(t[1]) });
    else if (to) {
      const existing = getState().conversations?.find((c) => c.kind === 'direct' && c.peer === to[1]);
      setView(existing ? { k: 'thread', id: existing.id } : { k: 'thread', id: null, to: to[1] });
    }
  });
  useBack(view.k !== 'list', () => { setView({ k: 'list' }); return true; });

  const filtered = useMemo(() => (conversations ?? []).filter((c) => titleOf(c).toLowerCase().includes(q.trim().toLowerCase())), [conversations, q]);

  if (view.k === 'new') {
    return <NewChat onBack={() => setView({ k: 'list' })} onOpen={(v) => setView(v)} />;
  }
  if (view.k === 'thread') {
    return <Thread key={view.id ?? view.to} id={view.id} to={view.to} title={view.title} onBack={() => { setView({ k: 'list' }); void load(); }} onOpened={(id) => setView({ k: 'thread', id })} />;
  }

  return (
    <div className="ph-app">
      <Header title="Messages" right={<IconButton icon="edit" label="New message" onClick={() => setView({ k: 'new' })} tone="accent" />} />
      {conversations && conversations.length > 0 && <div className="ph-pad"><SearchField value={q} onChange={setQ} /></div>}
      <div className="ph-scroll">
        {conversations === null && !failed && <Spinner />}
        {failed && conversations === null && <Empty icon="x" title="Could not load messages" action={<Button onClick={load}>Try again</Button>} />}
        {conversations?.length === 0 && <Empty icon="chat" title="No messages yet" text="Start a conversation with anyone who has a phone number." action={<Button kind="primary" onClick={() => setView({ k: 'new' })}>New message</Button>} />}
        {filtered.length === 0 && !!conversations?.length && <Empty icon="search" title="No results" />}
        <ul className="ph-list">
          {filtered.map((c) => (
            <li key={c.id}>
              <button className="ph-conv" onClick={() => setView({ k: 'thread', id: c.id })}>
                <Avatar name={c.kind === 'group' ? '' : titleOf(c)} id={c.peer ?? String(c.id)} group={c.kind === 'group'} size={48} photo={c.kind === 'direct' ? photoOf(c.peer) : null} />
                <span className="ph-conv-main">
                  <span className="ph-conv-top"><strong>{titleOf(c)}</strong><time>{c.last ? listTime(c.last.time) : ''}</time></span>
                  <span className="ph-conv-bot">
                    <span className={cx('ph-conv-prev', c.unread > 0 && 'unread')}>{previewOf(c.last)}</span>
                    {c.muted && <Ico name="bellOff" size={13} style={{ opacity: 0.5 }} />}
                    {c.unread > 0 && <span className="ph-pill">{c.unread > 99 ? '99+' : c.unread}</span>}
                  </span>
                </span>
              </button>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// New chat: pick people (or type a number), then a direct draft or a named group
// ---------------------------------------------------------------------------
type Pick = { number: string; name: string };

function NewChat({ onBack, onOpen }: { onBack: () => void; onOpen: (v: View) => void }) {
  const [contacts, setContacts] = useState<Contact[] | null>(null);
  const [picked, setPicked] = useState<Pick[]>([]);
  const [typed, setTyped] = useState('');
  const [naming, setNaming] = useState(false);
  const [groupName, setGroupName] = useState('');
  const [busy, setBusy] = useState(false);
  const limits = useStore((s) => s.hello?.limits);
  const me = useStore((s) => s.hello?.number);
  useEffect(() => { void api<Contact[]>('contacts').then((r) => setContacts(r.ok ? r.data ?? [] : [])); }, []);
  useBack(true, () => { onBack(); return true; });

  const toggle = (p: Pick) => setPicked((l) => (l.some((x) => x.number === p.number) ? l.filter((x) => x.number !== p.number) : [...l, p]));
  const addTyped = () => {
    const d = typed.replace(/\D/g, '');
    if (d.length !== 7) return toast('Enter a 7-digit number', 'error');
    if (d === me) return toast('That is your own number', 'error');
    if (!picked.some((x) => x.number === d)) setPicked((l) => [...l, { number: d, name: `${d.slice(0, 3)}-${d.slice(3)}` }]);
    setTyped('');
  };

  const next = () => {
    if (picked.length === 0) return;
    if (picked.length === 1) {
      const n = picked[0].number;
      const existing = getState().conversations?.find((c) => c.kind === 'direct' && c.peer === n);
      return onOpen(existing ? { k: 'thread', id: existing.id } : { k: 'thread', id: null, to: n, title: picked[0].name });
    }
    setNaming(true);
  };
  const createGroup = async () => {
    setBusy(true);
    const res = await api<Conversation>('groupCreate', { name: groupName, numbers: picked.map((p) => p.number) });
    setBusy(false);
    if (!say(res) || !res.data) return;
    const c = res.data;
    setState((s) => ({ conversations: s.conversations ? [c, ...s.conversations.filter((x) => x.id !== c.id)] : [c] }));
    onOpen({ k: 'thread', id: c.id });
  };

  return (
    <div className="ph-app">
      <Header title="New message" onBack={onBack} backLabel="Messages" right={<Button kind="primary" onClick={next} disabled={picked.length === 0}>{picked.length > 1 ? 'Group' : 'Next'}</Button>} />
      <div className="ph-pad">
        <div className="ph-to">
          <span>To</span>
          <div className="ph-chips">
            {picked.map((p) => <button key={p.number} className="ph-chip" onClick={() => toggle(p)}>{p.name}<Ico name="x" size={12} /></button>)}
            <TextInput value={typed} onChange={(v) => setTyped(v.replace(/[^\d-]/g, '').slice(0, 8))} placeholder={picked.length ? 'Add number' : 'Name or number'} inputMode="tel" onEnter={addTyped} />
          </div>
          {typed.replace(/\D/g, '').length === 7 && <button className="ph-link" onClick={addTyped}>Add</button>}
        </div>
        {limits && picked.length > limits.groupMembers - 1 && <p className="ph-hint danger">Groups have up to {limits.groupMembers} members.</p>}
      </div>
      <div className="ph-scroll">
        {contacts === null && <Spinner />}
        {contacts?.length === 0 && <Empty icon="users" title="No contacts yet" text="Type a number above to message anyone." />}
        <ul className="ph-list">
          {contacts?.filter((c) => !typed || c.name.toLowerCase().includes(typed.toLowerCase())).map((c) => {
            const on = picked.some((p) => p.number === c.number);
            return (
              <li key={c.id}>
                <button className="ph-conv" onClick={() => toggle({ number: c.number, name: c.name })}>
                  <Avatar name={c.name} id={c.number} size={40} />
                  <span className="ph-conv-main"><strong>{c.name}</strong><span className="ph-sub">{c.display}</span></span>
                  <span className={cx('ph-check', on && 'on')}>{on && <Ico name="check" size={14} stroke={3} />}</span>
                </button>
              </li>
            );
          })}
        </ul>
      </div>
      {naming && (
        <Sheet title="Name your group" onClose={() => setNaming(false)}>
          <div className="ph-form">
            <TextInput value={groupName} onChange={setGroupName} placeholder="Group name" maxLength={limits?.groupName ?? 32} autoFocus onEnter={() => groupName.trim() && createGroup()} />
            <p className="ph-hint">{picked.length} people will be added.</p>
            <Button kind="primary" block onClick={createGroup} disabled={busy || !groupName.trim()}>Create group</Button>
          </div>
        </Sheet>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Thread
// ---------------------------------------------------------------------------
function Thread({ id: initialId, to, title: draftTitle, onBack, onOpened }: { id: number | null; to?: string; title?: string; onBack: () => void; onOpened: (id: number) => void }) {
  const [id, setId] = useState<number | null>(initialId);
  const [messages, setMessages] = useState<Message[] | null>(initialId ? null : []);
  const [more, setMore] = useState(false);
  const [text, setText] = useState('');
  const [sheet, setSheet] = useState<'info' | 'attach' | 'contact' | 'photo' | null>(null);
  const [loadError, setLoadError] = useState(false);
  const conv = useStore((s) => (id ? s.conversations?.find((c) => c.id === id) ?? null : null));
  const maxLen = useStore((s) => s.hello?.limits.message ?? 500);
  const scroller = useRef<HTMLDivElement>(null);
  const stick = useRef(true);
  const idRef = useRef(id);
  idRef.current = id;
  const readOnly = conv?.peer === SYSTEM_NUMBER;

  const load = useCallback(async (convId: number) => {
    const res = await api<{ conversation: Conversation; messages: Message[]; more: boolean }>('thread', convId);
    if (!res.ok || !res.data) { setLoadError(true); return; }
    setLoadError(false);
    setMessages(res.data.messages); setMore(res.data.more);
    const c = res.data.conversation;
    setState((s) => ({ conversations: s.conversations?.map((x) => (x.id === c.id ? { ...c, unread: 0 } : x)) ?? s.conversations }));
    void markRead(convId);
  }, []);

  useEffect(() => { if (initialId) void load(initialId); }, [initialId, load]);
  useEffect(() => { setActiveThread(id); return () => setActiveThread(null); }, [id]);

  // Live messages for this conversation.
  useEffect(() => onPush((e) => {
    if (e.event !== 'message' || e.data.conversation.id !== idRef.current) return;
    const m = e.data.message;
    setMessages((list) => (list && !list.some((x) => x.id === m.id) ? [...list.filter((x) => !(x.pending && x.clientOp && m.mine && x.body === m.body)), m] : list));
    if (!m.mine) void markRead(e.data.conversation.id);
  }), []);

  useEffect(() => {
    const el = scroller.current;
    if (el && stick.current) el.scrollTop = el.scrollHeight;
  }, [messages]);
  useBack(sheet !== null, () => { setSheet(null); return true; });

  const loadEarlier = async () => {
    if (!id || !messages) return;
    const first = messages.find((m) => m.id > 0);
    if (!first) return;
    const el = scroller.current, prevH = el?.scrollHeight ?? 0;
    stick.current = false;
    const res = await api<{ messages: Message[]; more: boolean }>('thread', id, first.id);
    if (!res.ok || !res.data) return void say(res);
    setMessages((l) => [...res.data!.messages, ...(l ?? [])]);
    setMore(res.data.more);
    requestAnimationFrame(() => { if (el) el.scrollTop = el.scrollHeight - prevH; });
  };

  const sendInput = async (input: Record<string, unknown>, optimistic: Message) => {
    stick.current = true;
    setMessages((l) => [...(l ?? []), optimistic]);
    const res = await api<{ conversation: Conversation; message: Message }>('send', { ...(idRef.current ? { conversationId: idRef.current } : { to }), ...input, clientOp: optimistic.clientOp });
    if (!res.ok || !res.data) {
      setMessages((l) => l?.map((m) => (m.clientOp === optimistic.clientOp ? { ...m, pending: false, failed: true } : m)) ?? null);
      return void say(res);
    }
    const { conversation, message } = res.data;
    setMessages((l) => {
      const rest = (l ?? []).filter((m) => m.clientOp !== optimistic.clientOp && m.id !== message.id);
      return [...rest, message];
    });
    setState((s) => ({ conversations: [conversation, ...(s.conversations ?? []).filter((c) => c.id !== conversation.id)] }));
    if (!idRef.current) { setId(conversation.id); onOpened(conversation.id); }
  };

  const mk = (kind: Message['kind'], body: string, extra: Partial<Message> = {}): Message => ({
    id: -Date.now() - Math.floor(Math.random() * 1000), conversationId: id ?? 0, sender: '', mine: true, time: Math.floor(Date.now() / 1000),
    kind, body, pending: true, clientOp: newOp(), ...extra,
  });

  const send = () => {
    const body = text.trim();
    if (!body) return;
    setText('');
    void sendInput({ kind: 'text', body }, mk('text', body));
  };
  const retry = (m: Message) => {
    setMessages((l) => l?.filter((x) => x.clientOp !== m.clientOp) ?? null);
    void sendInput({ kind: m.kind, body: m.body, payload: m.payload }, mk(m.kind, m.body, { payload: m.payload }));
  };
  const shareLocation = async () => {
    setSheet(null);
    const loc = await post<{ label: string }>('location');
    const label = loc.data?.label || 'Shared location';
    void sendInput({ kind: 'location', body: label }, mk('location', label));
  };
  const sendPhoto = (photoId: number) => {
    void sendInput({ kind: 'photo', payload: { photoId }, body: '' }, mk('photo', 'Photo', { payload: { photoId } }));
  };
  const shareContact = (c: Contact) => {
    setSheet(null);
    void sendInput({ kind: 'contact', payload: { number: c.number, name: c.name } }, mk('contact', c.name, { payload: { number: c.number, name: c.name } }));
  };

  const title = (conv ? titleOf(conv) : undefined) ?? draftTitle ?? (to ? `${to.slice(0, 3)}-${to.slice(3)}` : 'Message');
  const group = conv?.kind === 'group';

  // Group consecutive messages by sender and day for spacing, names and timestamps.
  const rows = useMemo(() => {
    const out: { m: Message; first: boolean; last: boolean; day?: string }[] = [];
    const list = messages ?? [];
    list.forEach((m, i) => {
      const prev = list[i - 1], next = list[i + 1];
      const newDay = !prev || !sameDay(prev.time, m.time);
      const sameRun = (a?: Message) => !!a && a.sender === m.sender && a.mine === m.mine && a.kind !== 'system' && m.kind !== 'system' && sameDay(a.time, m.time) && Math.abs(a.time - m.time) < 600;
      out.push({ m, first: newDay || !sameRun(prev), last: !next || !sameRun(next) || !sameDay(next.time, m.time), day: newDay ? dayLabel(m.time) : undefined });
    });
    return out;
  }, [messages]);

  const lastMine = [...(messages ?? [])].reverse().find((m) => m.mine && m.kind !== 'system');

  return (
    <div className="ph-app ph-thread">
      <header className="ph-thread-head">
        <button className="ph-back" onClick={onBack}><Ico name="back" size={22} stroke={2.2} /></button>
        <button className="ph-thread-title" onClick={() => conv && setSheet('info')}>
          <Avatar name={group ? '' : title} id={conv?.peer ?? to ?? String(id)} group={group} size={36} />
          <span><strong>{title}</strong>{group && <em>{conv?.members.length} members</em>}</span>
        </button>
        <IconButton icon="more" label="Conversation info" onClick={() => conv && setSheet('info')} disabled={!conv} />
      </header>

      <div className="ph-thread-body" ref={scroller} onScroll={(e) => { const el = e.currentTarget; stick.current = el.scrollHeight - el.scrollTop - el.clientHeight < 80; }}>
        {messages === null && !loadError && <Spinner />}
        {loadError && <Empty icon="x" title="Could not load this chat" action={<Button onClick={() => id && load(id)}>Try again</Button>} />}
        {more && <button className="ph-more" onClick={loadEarlier}>Load earlier messages</button>}
        {messages?.length === 0 && <Empty icon="chat" title={`Message ${title}`} text="Say hello." />}
        {rows.map(({ m, first, last, day }) => (
          <div key={m.clientOp ?? m.id} className="ph-msg-wrap">
            {day && <div className="ph-day">{day}</div>}
            {m.kind === 'system' ? <div className="ph-sys">{m.body}</div> : (
              <div className={cx('ph-msg', m.mine ? 'mine' : 'theirs', first && 'first', last && 'last')}>
                {group && !m.mine && first && <span className="ph-msg-name">{m.senderDisplay ?? m.sender}</span>}
                <Bubble m={m} onRetry={() => retry(m)} />
                {last && !m.failed && <time>{timeOfDay(m.time)}</time>}
                {m === lastMine && <span className="ph-msg-status">{m.failed ? '' : m.pending ? 'Sending...' : conv?.kind === 'direct' && conv.peerReadId !== undefined && conv.peerReadId >= m.id ? 'Read' : 'Sent'}</span>}
              </div>
            )}
          </div>
        ))}
      </div>

      {readOnly ? <div className="ph-composer off">You cannot reply to this sender.</div> : (
        <div className="ph-composer">
          <IconButton icon="plus" label="Attach" onClick={() => setSheet('attach')} />
          <TextInput value={text} onChange={setText} placeholder="Message" maxLength={maxLen} onEnter={send} />
          <button className={cx('ph-send', text.trim() && 'on')} onClick={send} disabled={!text.trim()} aria-label="Send"><Ico name="send" size={18} /></button>
        </div>
      )}

      {sheet === 'attach' && (
        <Sheet title="Share" onClose={() => setSheet(null)}>
          <Group>
            <Row icon="pin" iconColor="#e0576a" title="Location" sub="Where you are right now" onClick={shareLocation} chevron />
            <Row icon="image" iconColor="#4a8dff" title="Photo" sub="Send a picture from your gallery" onClick={() => setSheet('photo')} chevron />
            <Row icon="users" iconColor="#d98a45" title="Contact" sub="Send a saved contact" onClick={() => setSheet('contact')} chevron />
          </Group>
        </Sheet>
      )}
      {sheet === 'contact' && <ContactPicker onPick={shareContact} onClose={() => setSheet(null)} />}
      {sheet === 'photo' && <GalleryPicker title="Send a photo" onPick={(pid) => { setSheet(null); sendPhoto(pid); }} onClose={() => setSheet(null)} />}
      {sheet === 'info' && conv && <ConversationInfo conv={conv} onClose={() => setSheet(null)} onLeft={() => { setSheet(null); onBack(); }} />}
    </div>
  );
}

function PhotoBubble({ m, onRetry }: { m: Message; onRetry: () => void }) {
  const mine = m.mine;
  const pending = !!m.pending || (m.id < 0);
  // Your own photo while it is still sending comes from the gallery; once sent (and for received ones) the message id fetches it.
  const local = useGalleryImage(pending && m.payload?.photoId ? m.payload.photoId : -1);
  const remote = useMessagePhoto(m.id, !pending);
  const src = local ?? remote.src;
  const [open, setOpen] = useState(false);
  const caption = m.body && m.body !== 'Photo' ? m.body : '';
  return (
    <div className={cx('ph-bubble photo', pending && 'pending', m.failed && 'failed')}>
      <button className="ph-msgphoto" onClick={() => src && setOpen(true)} aria-label="Open photo">{src ? <img src={src} alt="" /> : <span className="ph-thumb-load">{remote.failed ? 'Photo unavailable' : ''}</span>}</button>
      {caption && <span className="ph-photo-cap">{caption}</span>}
      {m.failed && <button className="ph-retry" onClick={onRetry}>Not delivered. Tap to retry</button>}
      {open && src && <PhotoSheet src={src} messageId={pending ? undefined : m.id} mine={mine} onClose={() => setOpen(false)} />}
    </div>
  );
}

function Bubble({ m, onRetry }: { m: Message; onRetry: () => void }) {
  if (m.kind === 'photo') return <PhotoBubble m={m} onRetry={onRetry} />;
  if (m.kind === 'location') {
    const p = m.payload;
    return (
      <div className={cx('ph-bubble card', m.pending && 'pending')}>
        <div className="ph-card-ico"><Ico name="pin" size={20} /></div>
        <div className="ph-card-text"><strong>Location</strong><span>{m.body}</span></div>
        {p?.x !== undefined && p.y !== undefined && (
          <button className="ph-card-btn" onClick={async () => say(await post('waypoint', { x: p.x, y: p.y }))}>Set waypoint</button>
        )}
      </div>
    );
  }
  if (m.kind === 'contact') {
    const p = m.payload;
    return (
      <div className={cx('ph-bubble card', m.pending && 'pending')}>
        <Avatar name={m.body} id={p?.number} size={38} />
        <div className="ph-card-text"><strong>{m.body}</strong><span>{p?.number ? `${p.number.slice(0, 3)}-${p.number.slice(3)}` : ''}</span></div>
        {!m.mine && p?.number && <button className="ph-card-btn" onClick={async () => say(await api('contactSave', { name: m.body, number: p.number }))}>Save</button>}
      </div>
    );
  }
  return (
    <div className={cx('ph-bubble', m.pending && 'pending', m.failed && 'failed')}>
      {m.body}
      {m.failed && <button className="ph-retry" onClick={onRetry}>Not delivered. Tap to retry</button>}
    </div>
  );
}

function ContactPicker({ onPick, onClose }: { onPick: (c: Contact) => void; onClose: () => void }) {
  const [list, setList] = useState<Contact[] | null>(null);
  useEffect(() => { void api<Contact[]>('contacts').then((r) => setList(r.ok ? r.data ?? [] : [])); }, []);
  return (
    <Sheet title="Share a contact" onClose={onClose}>
      {list === null && <Spinner />}
      {list?.length === 0 && <Empty icon="users" title="No contacts" />}
      <Group>{list?.map((c) => <Row key={c.id} title={c.name} sub={c.display} onClick={() => onPick(c)} right={<Avatar name={c.name} id={c.number} size={30} />} />)}</Group>
    </Sheet>
  );
}

function ConversationInfo({ conv, onClose, onLeft }: { conv: Conversation; onClose: () => void; onLeft: () => void }) {
  const me = useStore((s) => s.hello?.number);
  const limits = useStore((s) => s.hello?.limits);
  const [adding, setAdding] = useState(false);
  const [number, setNumber] = useState('');
  const [name, setName] = useState(conv.title);
  const [renaming, setRenaming] = useState(false);
  const group = conv.kind === 'group';
  const peer = conv.peer;

  const toggleMute = async () => {
    const res = await api<{ muted: boolean }>('mute', conv.id, !conv.muted);
    if (say(res)) setState((s) => ({ conversations: s.conversations?.map((c) => (c.id === conv.id ? { ...c, muted: !conv.muted } : c)) ?? null }));
  };
  const leave = async () => {
    const res = await api('leave', conv.id);
    if (!say(res)) return;
    setState((s) => ({ conversations: s.conversations?.filter((c) => c.id !== conv.id) ?? null }));
    onLeft();
  };
  const block = async () => {
    if (!peer) return;
    if (say(await api('block', peer, true))) toast('Blocked. You will not get their messages or calls.');
  };
  const rename = async () => { if (say(await api('groupRename', conv.id, name))) setRenaming(false); };
  const add = async () => { const res = await api('groupAdd', conv.id, number); if (say(res)) { setNumber(''); setAdding(false); } };
  const remove = async (n: string) => { say(await api('groupRemove', conv.id, n)); };

  return (
    <Sheet title={group ? 'Group info' : 'Conversation'} onClose={onClose}>
      <div className="ph-info-head">
        <Avatar name={group ? '' : titleOf(conv)} id={peer ?? String(conv.id)} group={group} size={72} />
        <strong>{titleOf(conv)}</strong>
        {!group && peer && <span className="ph-sub">{peer.slice(0, 3)}-{peer.slice(3)}</span>}
      </div>
      {!group && peer && peer !== SYSTEM_NUMBER && (
        <div className="ph-info-actions">
          <button onClick={() => { onClose(); void startCall(peer); }}><Ico name="phone" size={20} /><span>Call</span></button>
          <button onClick={toggleMute}><Ico name={conv.muted ? 'bell' : 'bellOff'} size={20} /><span>{conv.muted ? 'Unmute' : 'Mute'}</span></button>
          <button onClick={() => { onClose(); openApp('contacts', `new/${peer}`); }}><Ico name="userplus" size={20} /><span>Save</span></button>
        </div>
      )}
      {group && (
        <Group title={`Members (${conv.members.length})`}>
          {conv.members.map((m) => (
            <Row key={m.number} title={m.number === me ? 'You' : m.display} sub={m.admin ? 'Admin' : m.number === me ? undefined : `${m.number.slice(0, 3)}-${m.number.slice(3)}`}
              right={conv.admin && m.number !== me ? <IconButton icon="x" label={`Remove ${m.display}`} onClick={() => remove(m.number)} size={16} tone="danger" /> : undefined} />
          ))}
        </Group>
      )}
      {group && conv.admin && !adding && !renaming && (
        <Group>
          <Row icon="userplus" iconColor="var(--ph-accent)" title="Add someone" onClick={() => setAdding(true)} chevron />
          <Row icon="edit" iconColor="#6f7585" title="Rename group" onClick={() => setRenaming(true)} chevron />
        </Group>
      )}
      {adding && (
        <div className="ph-form">
          <TextInput value={number} onChange={(v) => setNumber(v.replace(/[^\d-]/g, '').slice(0, 8))} placeholder="Phone number" inputMode="tel" autoFocus onEnter={add} />
          <Button kind="primary" block onClick={add} disabled={number.replace(/\D/g, '').length !== 7 || conv.members.length >= (limits?.groupMembers ?? 12)}>Add to group</Button>
        </div>
      )}
      {renaming && (
        <div className="ph-form">
          <TextInput value={name} onChange={setName} maxLength={limits?.groupName ?? 32} autoFocus onEnter={rename} />
          <Button kind="primary" block onClick={rename} disabled={!name.trim()}>Save name</Button>
        </div>
      )}
      <Group>
        {group && <Row icon={conv.muted ? 'bell' : 'bellOff'} iconColor="#6f7585" title={conv.muted ? 'Unmute' : 'Mute notifications'} onClick={toggleMute} />}
        {!group && peer && peer !== SYSTEM_NUMBER && <Row icon="block" iconColor="#c25661" title="Block this number" onClick={block} />}
        <Row icon="trash" iconColor="#c25661" danger title={group ? 'Leave group' : 'Delete conversation'} onClick={leave} />
      </Group>
    </Sheet>
  );
}
