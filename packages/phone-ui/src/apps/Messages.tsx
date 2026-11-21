import { useCallback, useEffect, useRef, useState } from 'react';
import { Icon, nui } from '@veyl/ui';
import { api, newClientOp } from '../api';
import { AppHeader, usePhone } from '../App';
import { clock, fmtNumber, initials, timeAgo, type Contact, type ConversationItem, type Member, type Message } from '../types';

type View = { kind: 'list' } | { kind: 'thread'; convId?: number; number?: string } | { kind: 'new' } | { kind: 'group' } | { kind: 'info'; convId: number };

export function MessagesApp() {
  const { route } = usePhone();
  const initial: View = route.startsWith('c') && Number(route.slice(1)) ? { kind: 'thread', convId: Number(route.slice(1)) }
    : route.startsWith('n') ? { kind: 'thread', number: route.slice(1) } : { kind: 'list' };
  const [view, setView] = useState<View>(initial);
  if (view.kind === 'thread') return <Thread convId={view.convId} number={view.number} onBack={() => setView({ kind: 'list' })} onInfo={(id) => setView({ kind: 'info', convId: id })} onConv={(id) => setView({ kind: 'thread', convId: id })} />;
  if (view.kind === 'new') return <NewMessage onBack={() => setView({ kind: 'list' })} onPick={(n) => setView({ kind: 'thread', number: n })} onGroup={() => setView({ kind: 'group' })} />;
  if (view.kind === 'group') return <NewGroup onBack={() => setView({ kind: 'new' })} onCreated={(id) => setView({ kind: 'thread', convId: id })} />;
  if (view.kind === 'info') return <GroupInfo convId={view.convId} onBack={() => setView({ kind: 'thread', convId: view.convId })} onLeft={() => setView({ kind: 'list' })} />;
  return <ConversationList onOpen={(id) => setView({ kind: 'thread', convId: id })} onNew={() => setView({ kind: 'new' })} />;
}

function ConversationList({ onOpen, onNew }: { onOpen: (id: number) => void; onNew: () => void }) {
  const { onMessage, setUnread } = usePhone();
  const [items, setItems] = useState<ConversationItem[] | null>(null);
  const [next, setNext] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const load = useCallback(async (offset = 0) => {
    const r = await api<{ items: ConversationItem[]; nextOffset: number | null; unreadTotal: number }>('conversations', offset);
    if (!r.ok || !r.data) { setError(r.message ?? 'Could not load'); return; }
    setError(null);
    setItems((cur) => (offset === 0 ? r.data!.items : [...(cur ?? []), ...r.data!.items]));
    setNext(r.data.nextOffset);
    setUnread(r.data.unreadTotal);
  }, [setUnread]);
  useEffect(() => { void load(0); }, [load]);
  useEffect(() => onMessage(() => { void load(0); }), [onMessage, load]);
  return (
    <div className="ph-appview">
      <AppHeader title="Messages" right={<button className="ph-icon-btn" onClick={onNew} aria-label="New message"><Icon name="edit" size="1rem" /></button>} />
      <div className="ph-body">
        {error && <div className="ph-empty error">{error} <button className="ph-link" onClick={() => void load(0)}>Retry</button></div>}
        {!items && !error && <div className="ph-empty">Loading…</div>}
        {items && items.length === 0 && <div className="ph-empty">No conversations yet. Tap ✎ to start one.</div>}
        <ul className="ph-list">
          {(items ?? []).map((c) => (
            <li key={c.id}>
              <button className="ph-row" onClick={() => onOpen(c.id)}>
                <span className={`ph-avatar${c.kind === 'group' ? ' group' : ''}`}>{c.kind === 'group' ? <Icon name="users" size="1rem" /> : initials(c.title)}</span>
                <span className="ph-row-main">
                  <strong>{c.title}{c.muted && <Icon name="bell_off" size="0.75rem" />}</strong>
                  <span className="muted ph-preview">{c.blocked ? 'Blocked' : preview(c.last)}</span>
                </span>
                <span className="ph-row-meta">{c.last && <span className="muted">{timeAgo(c.last.at)}</span>}{c.unread > 0 && <em className="ph-count">{c.unread}</em>}</span>
              </button>
            </li>
          ))}
        </ul>
        {next !== null && <button className="ph-link" onClick={() => void load(next)}>Load more</button>}
      </div>
    </div>
  );
}

function preview(m?: Message | null) {
  if (!m) return '';
  if (m.kind === 'location') return '📍 Shared a location';
  if (m.kind === 'contact') return '👤 Contact card';
  return m.body;
}

function Ticks({ m, group }: { m: Message; group: boolean }) {
  if (m.failed) return <span className="ph-tick failed">Not sent</span>;
  if (m.pending) return <span className="ph-tick">Sending…</span>;
  if (group && m.total) return <span className="ph-tick">{m.deliveredCount ?? 0}/{m.total} delivered</span>;
  if (m.state === 'read') return <span className="ph-tick read">Read</span>;
  if (m.state === 'delivered') return <span className="ph-tick">Delivered</span>;
  return <span className="ph-tick">Sent</span>;
}

function Thread({ convId: initialConv, number, onBack, onInfo, onConv }: { convId?: number; number?: string; onBack: () => void; onInfo: (id: number) => void; onConv: (id: number) => void }) {
  const { session, onMessage, onReceipt, setOpenThread, toast, setUnread, go } = usePhone();
  const [convId, setConvId] = useState<number | undefined>(initialConv);
  const [conv, setConv] = useState<{ title: string; kind: 'direct' | 'group'; muted: boolean } | null>(number ? { title: fmtNumber(number), kind: 'direct', muted: false } : null);
  const [items, setItems] = useState<Message[]>([]);
  const [before, setBefore] = useState<number | null>(null);
  const [loading, setLoading] = useState(!!initialConv);
  const [error, setError] = useState<string | null>(null);
  const [text, setText] = useState('');
  const [attach, setAttach] = useState(false);
  const listRef = useRef<HTMLDivElement>(null);
  const group = conv?.kind === 'group';

  const markRead = useCallback(async (id: number, upto: number) => {
    const r = await api<{ unreadTotal: number }>('read', id, upto);
    if (r.ok && r.data) setUnread(r.data.unreadTotal);
  }, [setUnread]);

  const load = useCallback(async (id: number, beforeId?: number) => {
    const r = await api<{ conv: { title: string; kind: 'direct' | 'group'; muted: boolean }; items: Message[]; nextBefore: number | null }>('thread', id, beforeId);
    setLoading(false);
    if (!r.ok || !r.data) { setError(r.message ?? 'Could not load'); return; }
    setConv(r.data.conv);
    const older = [...r.data.items].reverse();
    setItems((cur) => (beforeId ? [...older, ...cur] : older));
    setBefore(r.data.nextBefore);
    if (!beforeId && older.length) void markRead(id, older[older.length - 1].id);
    if (!beforeId) window.setTimeout(() => listRef.current?.scrollTo({ top: listRef.current.scrollHeight }), 30);
  }, [markRead]);

  // New direct thread by number: find the existing conversation, if any.
  useEffect(() => {
    if (initialConv) { void load(initialConv); return; }
    if (!number) return;
    void api<{ items: ConversationItem[] }>('conversations', 0).then((r) => {
      const found = r.ok && r.data ? r.data.items.find((c) => c.kind === 'direct' && c.number === number) : undefined;
      if (found) { setConvId(found.id); setLoading(true); void load(found.id); }
    });
  }, [initialConv, number, load]);

  useEffect(() => { setOpenThread(convId ? `c${convId}` : null); return () => setOpenThread(null); }, [convId, setOpenThread]);
  useEffect(() => onMessage((m) => {
    if (m.convId !== convId) return;
    setItems((cur) => (cur.some((x) => x.id === m.id) ? cur : [...cur, m]));
    void markRead(m.convId, m.id);
    window.setTimeout(() => listRef.current?.scrollTo({ top: listRef.current.scrollHeight, behavior: 'smooth' }), 30);
  }), [onMessage, convId, markRead]);
  useEffect(() => onReceipt((r) => {
    if (r.convId !== convId) return;
    setItems((cur) => cur.map((m) => (m.id === r.id ? { ...m, state: r.state, deliveredCount: r.delivered, total: r.total } : m)));
  }), [onReceipt, convId]);

  const send = async (payload: Record<string, unknown>) => {
    const clientOp = newClientOp();
    const temp: Message = { id: -Date.now(), convId: convId ?? 0, sender: session.number, kind: (payload.kind as Message['kind']) ?? 'text',
      body: (payload.body as string) ?? '…', at: Date.now() / 1000, pending: true };
    setItems((cur) => [...cur, temp]);
    window.setTimeout(() => listRef.current?.scrollTo({ top: listRef.current.scrollHeight, behavior: 'smooth' }), 30);
    const r = await api<Message>('send', { ...payload, clientOp, ...(convId ? { convId } : { to: number }) });
    if (!r.ok || !r.data) {
      setItems((cur) => cur.map((m) => (m.id === temp.id ? { ...m, pending: false, failed: true } : m)));
      toast(r.message ?? 'Message not sent', 'error');
      return false;
    }
    setItems((cur) => cur.map((m) => (m.id === temp.id ? { ...r.data!, state: r.data!.state ?? 'sent' } : m)));
    if (!convId) { setConvId(r.data.convId); onConv(r.data.convId); }
    return true;
  };

  const sendText = async () => {
    const body = text.trim();
    if (!body) return;
    setText('');
    if (!(await send({ kind: 'text', body }))) setText(body);
  };
  const shareLocation = async () => {
    setAttach(false);
    const l = await nui<{ label: string }>('locationLabel');
    await send({ kind: 'location', label: l.data?.label ?? 'Shared location', body: l.data?.label });
  };
  const [pickContact, setPickContact] = useState<Contact[] | null>(null);
  const openContacts = async () => { setAttach(false); const r = await api<Contact[]>('contacts'); setPickContact(r.ok && r.data ? r.data : []); };

  return (
    <div className="ph-appview">
      <AppHeader title={conv?.title ?? '…'} onBack={onBack}
        right={convId && group ? <button className="ph-icon-btn" onClick={() => onInfo(convId)} aria-label="Group info"><Icon name="more" size="1.1rem" /></button>
          : convId ? <MuteButton convId={convId} muted={conv?.muted ?? false} onChange={(m) => setConv((c) => (c ? { ...c, muted: m } : c))} /> : null} />
      <div className="ph-thread v-scroll" ref={listRef}>
        {before !== null && <button className="ph-link" onClick={() => void load(convId!, before)}>Load earlier messages</button>}
        {loading && <div className="ph-empty">Loading…</div>}
        {error && <div className="ph-empty error">{error}</div>}
        {!loading && items.length === 0 && !error && <div className="ph-empty">Say hello.</div>}
        {items.map((m) => {
          const mine = m.sender === session.number;
          if (m.kind === 'system') return <div key={m.id} className="ph-system">{m.body}</div>;
          return (
            <div key={m.id} className={`ph-bubble-row${mine ? ' mine' : ''}`}>
              <div className={`ph-bubble${mine ? ' mine' : ''}${m.failed ? ' failed' : ''}`}>
                {group && !mine && <div className="ph-bubble-from">{fmtNumber(m.sender)}</div>}
                {m.kind === 'text' && <span>{m.body}</span>}
                {m.kind === 'location' && m.payload && (
                  <div className="ph-pin">
                    <div className="ph-pin-map"><Icon name="pin" size="1.4rem" /></div>
                    <div className="ph-pin-label"><Icon name="pin" size="0.8rem" /> {m.payload.label}</div>
                    <button className="ph-pin-btn" onClick={() => void nui('waypoint', { x: m.payload!.x, y: m.payload!.y }).then(() => toast('Waypoint set'))}>Set waypoint</button>
                  </div>
                )}
                {m.kind === 'contact' && m.payload && (
                  <div className="ph-cardmsg">
                    <div><Icon name="user" size="0.9rem" /> <strong>{m.payload.name}</strong></div>
                    <div className="muted">{fmtNumber(m.payload.number)}</div>
                    {!mine && <button className="ph-pin-btn" onClick={() => void api('contactSave', { name: m.payload!.name, number: m.payload!.number }).then((r) => toast(r.message ?? (r.ok ? 'Saved' : 'Failed'), r.ok ? 'ok' : 'error'))}>Add to contacts</button>}
                    <button className="ph-pin-btn" onClick={() => go('messages', `n${m.payload!.number}`)}>Message</button>
                  </div>
                )}
              </div>
              <div className="ph-bubble-meta">{clock(m.at)} {mine && <Ticks m={m} group={group} />}</div>
            </div>
          );
        })}
      </div>
      {attach && (
        <div className="ph-attach">
          <button onClick={() => void shareLocation()}><Icon name="pin" size="1rem" /> My location</button>
          <button onClick={() => void openContacts()}><Icon name="user" size="1rem" /> Contact card</button>
        </div>
      )}
      {pickContact && (
        <div className="ph-sheet" role="dialog" aria-label="Choose a contact">
          <div className="ph-sheet-title">Share a contact</div>
          {pickContact.length === 0 && <div className="ph-empty">No contacts.</div>}
          {pickContact.slice(0, 30).map((c) => <button key={c.id} onClick={() => { setPickContact(null); void send({ kind: 'contact', contact: { name: c.name, number: c.number }, body: c.name }); }}>{c.name} · {c.display}</button>)}
          <button className="muted" onClick={() => setPickContact(null)}>Cancel</button>
        </div>
      )}
      <div className="ph-composer">
        <button className="ph-icon-btn" aria-label="Attach" onClick={() => setAttach((a) => !a)}><Icon name="plus" size="1.1rem" /></button>
        <input className="ph-input" placeholder="Message…" value={text} maxLength={session.limits.message}
          onChange={(e) => setText(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') void sendText(); }} />
        <button className="ph-send" aria-label="Send" disabled={!text.trim()} onClick={() => void sendText()}><Icon name="send" size="1rem" /></button>
      </div>
    </div>
  );
}

function MuteButton({ convId, muted, onChange }: { convId: number; muted: boolean; onChange: (m: boolean) => void }) {
  const { toast } = usePhone();
  return (
    <button className="ph-icon-btn" aria-label={muted ? 'Unmute' : 'Mute'} onClick={() => void api<{ muted: boolean }>('mute', convId, !muted).then((r) => { if (r.ok) { onChange(!muted); toast(r.message ?? ''); } })}>
      <Icon name={muted ? 'bell_off' : 'bell'} size="1rem" />
    </button>
  );
}

function NewMessage({ onBack, onPick, onGroup }: { onBack: () => void; onPick: (n: string) => void; onGroup: () => void }) {
  const [to, setTo] = useState('');
  const [contacts, setContacts] = useState<Contact[]>([]);
  useEffect(() => { void api<Contact[]>('contacts').then((r) => setContacts(r.ok && r.data ? r.data : [])); }, []);
  const digits = to.replace(/\D/g, '');
  const q = to.trim().toLowerCase();
  return (
    <div className="ph-appview">
      <AppHeader title="New message" onBack={onBack} />
      <div className="ph-body">
        <div className="ph-inline"><input className="ph-input" placeholder="Name or 555-1234" value={to} onChange={(e) => setTo(e.target.value)} autoFocus />
          <button className="ph-btn primary" disabled={digits.length !== 7} onClick={() => onPick(digits)}>Next</button></div>
        <button className="ph-row" onClick={onGroup}><span className="ph-avatar group"><Icon name="users" size="1rem" /></span><span className="ph-row-main"><strong>New group</strong></span></button>
        <ul className="ph-list">
          {contacts.filter((c) => !q || c.name.toLowerCase().includes(q) || c.number.includes(digits || '§')).map((c) => (
            <li key={c.id}><button className="ph-row" onClick={() => onPick(c.number)}><span className="ph-avatar">{initials(c.name)}</span><span className="ph-row-main"><strong>{c.name}</strong><span className="muted">{c.display}</span></span></button></li>
          ))}
        </ul>
      </div>
    </div>
  );
}

function NewGroup({ onBack, onCreated }: { onBack: () => void; onCreated: (id: number) => void }) {
  const { toast, session } = usePhone();
  const [name, setName] = useState('');
  const [picked, setPicked] = useState<string[]>([]);
  const [manual, setManual] = useState('');
  const [contacts, setContacts] = useState<Contact[]>([]);
  const [busy, setBusy] = useState(false);
  useEffect(() => { void api<Contact[]>('contacts').then((r) => setContacts(r.ok && r.data ? r.data : [])); }, []);
  const toggle = (n: string) => setPicked((p) => (p.includes(n) ? p.filter((x) => x !== n) : p.length + 1 < session.limits.groupMembers ? [...p, n] : p));
  const create = async () => {
    setBusy(true);
    const r = await api<{ id: number }>('groupCreate', name, picked);
    setBusy(false);
    if (!r.ok || !r.data) { toast(r.message ?? 'Could not create', 'error'); return; }
    onCreated(r.data.id);
  };
  return (
    <div className="ph-appview">
      <AppHeader title="New group" onBack={onBack} />
      <div className="ph-body ph-form">
        <label>Group name<input className="ph-input" value={name} maxLength={32} onChange={(e) => setName(e.target.value)} /></label>
        <div className="ph-inline"><input className="ph-input" placeholder="Add 555-1234" value={manual} onChange={(e) => setManual(e.target.value)} />
          <button className="ph-btn" disabled={manual.replace(/\D/g, '').length !== 7} onClick={() => { toggle(manual.replace(/\D/g, '')); setManual(''); }}>Add</button></div>
        <div className="ph-chips">{picked.map((n) => <button key={n} className="ph-chip" onClick={() => toggle(n)}>{contacts.find((c) => c.number === n)?.name ?? fmtNumber(n)} ✕</button>)}</div>
        <ul className="ph-list">
          {contacts.map((c) => (
            <li key={c.id}><button className={`ph-row${picked.includes(c.number) ? ' picked' : ''}`} onClick={() => toggle(c.number)} aria-pressed={picked.includes(c.number)}>
              <span className="ph-avatar">{initials(c.name)}</span><span className="ph-row-main"><strong>{c.name}</strong><span className="muted">{c.display}</span></span>{picked.includes(c.number) && <Icon name="check" size="1rem" />}
            </button></li>
          ))}
        </ul>
        <button className="ph-btn primary" disabled={busy || !name.trim() || picked.length === 0} onClick={() => void create()}>Create group ({picked.length + 1})</button>
      </div>
    </div>
  );
}

function GroupInfo({ convId, onBack, onLeft }: { convId: number; onBack: () => void; onLeft: () => void }) {
  const { toast } = usePhone();
  const [data, setData] = useState<{ conv: { title: string; role: string; muted: boolean }; members: Member[] } | null>(null);
  const [rename, setRename] = useState('');
  const [add, setAdd] = useState('');
  const load = useCallback(async () => {
    const r = await api<{ conv: { title: string; role: string; muted: boolean }; members: Member[] }>('thread', convId, 1);
    if (r.ok && r.data) { setData(r.data); setRename(r.data.conv.title); } else { toast(r.message ?? 'No access', 'error'); onLeft(); }
  }, [convId, toast, onLeft]);
  useEffect(() => { void load(); }, [load]);
  if (!data) return <div className="ph-appview"><AppHeader title="Group" onBack={onBack} /><div className="ph-empty">Loading…</div></div>;
  const isAdmin = data.conv.role === 'admin';
  const act = async (name: string, ...args: unknown[]) => { const r = await api(name, convId, ...args); toast(r.message ?? (r.ok ? 'Done' : 'Failed'), r.ok ? 'ok' : 'error'); if (r.ok) await load(); return r.ok; };
  return (
    <div className="ph-appview">
      <AppHeader title="Group info" onBack={onBack} />
      <div className="ph-body ph-form">
        {isAdmin ? <div className="ph-inline"><input className="ph-input" value={rename} maxLength={32} onChange={(e) => setRename(e.target.value)} /><button className="ph-btn" onClick={() => void act('groupRename', rename)}>Rename</button></div>
          : <div className="ph-contact-name">{data.conv.title}</div>}
        <div className="ph-section">{data.members.length} members</div>
        <ul className="ph-list">
          {data.members.map((m) => (
            <li key={m.number}><div className="ph-row static"><span className="ph-avatar">{initials(m.name ?? m.display)}</span>
              <span className="ph-row-main"><strong>{m.me ? 'You' : m.name ?? m.display}</strong><span className="muted">{m.display}{m.role === 'admin' ? ' · Admin' : ''}</span></span>
              {isAdmin && !m.me && <button className="ph-btn" onClick={() => void act('groupRemove', m.number)}>Remove</button>}</div></li>
          ))}
        </ul>
        {isAdmin && <div className="ph-inline"><input className="ph-input" placeholder="Add 555-1234" value={add} onChange={(e) => setAdd(e.target.value)} /><button className="ph-btn" disabled={add.replace(/\D/g, '').length !== 7} onClick={() => void act('groupAdd', add).then((ok) => ok && setAdd(''))}>Add</button></div>}
        <button className="ph-btn" onClick={() => void act('mute', !data.conv.muted)}>{data.conv.muted ? 'Unmute' : 'Mute'} conversation</button>
        <button className="ph-btn danger" onClick={() => void api('groupLeave', convId).then((r) => { toast(r.message ?? '', r.ok ? 'ok' : 'error'); if (r.ok) onLeft(); })}>Leave group</button>
      </div>
    </div>
  );
}
