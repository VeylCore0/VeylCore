import { useCallback, useEffect, useMemo, useState } from 'react';
import { Icon } from '@veyl/ui';
import { api, newClientOp } from '../api';
import { AppHeader, usePhone } from '../App';
import { CONTACT_COLORS, initials, type Contact } from '../types';

type View = { kind: 'list' } | { kind: 'detail'; id: number } | { kind: 'edit'; contact?: Contact } | { kind: 'blocked' } | { kind: 'share'; contact: Contact };

export function ContactsApp() {
  const { toast, startCall, go, session } = usePhone();
  const [items, setItems] = useState<Contact[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [view, setView] = useState<View>({ kind: 'list' });
  const [search, setSearch] = useState('');
  const load = useCallback(async () => {
    const r = await api<Contact[]>('contacts');
    if (r.ok && r.data) { setItems(r.data); setError(null); } else setError(r.message ?? 'Could not load contacts');
  }, []);
  useEffect(() => { void load(); }, [load]);

  const list = useMemo(() => {
    const q = search.trim().toLowerCase();
    const all = (items ?? []).filter((c) => !q || c.name.toLowerCase().includes(q) || c.number.includes(q.replace(/\D/g, '') || '§'));
    return { fav: all.filter((c) => c.favorite), rest: all.filter((c) => !c.favorite) };
  }, [items, search]);

  if (view.kind === 'edit') return <EditContact contact={view.contact} onDone={async (saved) => { await load(); setView(saved ? { kind: 'detail', id: saved } : { kind: 'list' }); }} />;
  if (view.kind === 'blocked') return <Blocked onBack={() => setView({ kind: 'list' })} />;
  if (view.kind === 'share') return <ShareContact contact={view.contact} onBack={() => setView({ kind: 'detail', id: view.contact.id })} />;
  if (view.kind === 'detail') {
    const c = items?.find((x) => x.id === view.id);
    if (!c) return <div className="ph-appview"><AppHeader title="Contact" onBack={() => setView({ kind: 'list' })} /><div className="ph-empty">Contact not found.</div></div>;
    const del = async () => { const r = await api('contactDelete', c.id); toast(r.message ?? (r.ok ? 'Deleted' : 'Failed'), r.ok ? 'ok' : 'error'); if (r.ok) { await load(); setView({ kind: 'list' }); } };
    const fav = async () => { const r = await api('contactSave', { ...c, favorite: !c.favorite }); if (r.ok) await load(); };
    const block = async () => { const r = await api('block', c.number, true); toast(r.message ?? '', r.ok ? 'ok' : 'error'); };
    return (
      <div className="ph-appview">
        <AppHeader title="" onBack={() => setView({ kind: 'list' })} right={<button className="ph-icon-btn" onClick={() => setView({ kind: 'edit', contact: c })} aria-label="Edit"><Icon name="edit" size="1rem" /></button>} />
        <div className="ph-body ph-contact">
          <div className="ph-avatar xl" style={{ background: CONTACT_COLORS[c.color] }}>{initials(c.name)}</div>
          <div className="ph-contact-name">{c.name}</div>
          <div className="muted">{c.display}</div>
          {c.note && <div className="ph-contact-note">{c.note}</div>}
          <div className="ph-actions">
            <button onClick={() => go('messages', `n${c.number}`)}><Icon name="chat" size="1.1rem" />Message</button>
            <button disabled={!session.voice.available} title={session.voice.available ? undefined : session.voice.reason} onClick={async () => { await startCall(c.number); go('phone', 'call'); }}><Icon name="call" size="1.1rem" />Call</button>
            <button onClick={() => setView({ kind: 'share', contact: c })}><Icon name="share" size="1.1rem" />Share</button>
            <button onClick={() => void fav()}><Icon name="star" size="1.1rem" />{c.favorite ? 'Unfavorite' : 'Favorite'}</button>
          </div>
          <button className="ph-link danger" onClick={() => void block()}><Icon name="block" size="0.95rem" /> Block this number</button>
          <button className="ph-link danger" onClick={() => void del()}>Delete contact</button>
        </div>
      </div>
    );
  }

  return (
    <div className="ph-appview">
      <AppHeader title="Contacts" right={<button className="ph-icon-btn" onClick={() => setView({ kind: 'edit' })} aria-label="Add contact"><Icon name="plus" size="1.1rem" /></button>} />
      <div className="ph-body">
        <label className="ph-search inapp"><Icon name="search" size="0.9rem" /><input placeholder="Search name or number" value={search} onChange={(e) => setSearch(e.target.value)} /></label>
        <div className="ph-mycard"><span className="muted">My number</span><strong>{session.display}</strong></div>
        {error && <div className="ph-empty error">{error} <button className="ph-link" onClick={() => void load()}>Retry</button></div>}
        {!items && !error && <div className="ph-empty">Loading…</div>}
        {items && items.length === 0 && <div className="ph-empty">No contacts yet. Tap + to add one.</div>}
        {list.fav.length > 0 && <div className="ph-section">Favorites</div>}
        <ul className="ph-list">
          {[...list.fav, ...list.rest].map((c, i) => (
            <li key={c.id}>
              {i === list.fav.length && list.fav.length > 0 && <div className="ph-section">All contacts</div>}
              <button className="ph-row" onClick={() => setView({ kind: 'detail', id: c.id })}>
                <span className="ph-avatar" style={{ background: CONTACT_COLORS[c.color] }}>{initials(c.name)}</span>
                <span className="ph-row-main"><strong>{c.name}</strong><span className="muted">{c.display}</span></span>
                {c.favorite && <Icon name="star" size="0.9rem" />}
              </button>
            </li>
          ))}
        </ul>
        <button className="ph-link" onClick={() => setView({ kind: 'blocked' })}><Icon name="block" size="0.9rem" /> Blocked numbers</button>
      </div>
    </div>
  );
}

function EditContact({ contact, onDone }: { contact?: Contact; onDone: (savedId?: number) => void }) {
  const { toast } = usePhone();
  const [name, setName] = useState(contact?.name ?? '');
  const [number, setNumber] = useState(contact?.display ?? '');
  const [note, setNote] = useState(contact?.note ?? '');
  const [color, setColor] = useState(contact?.color ?? 0);
  const [busy, setBusy] = useState(false);
  const save = async () => {
    setBusy(true);
    const r = await api<{ id: number }>('contactSave', { id: contact?.id, name, number, note, color, favorite: contact?.favorite ?? false });
    setBusy(false);
    if (!r.ok) { toast(r.message ?? 'Could not save', 'error'); return; }
    toast(r.message ?? 'Saved');
    onDone(r.data?.id ?? contact?.id);
  };
  return (
    <div className="ph-appview">
      <AppHeader title={contact ? 'Edit contact' : 'New contact'} onBack={() => onDone(contact?.id)} />
      <div className="ph-body ph-form">
        <div className="ph-avatar xl" style={{ background: CONTACT_COLORS[color] }}>{initials(name || '?')}</div>
        <div className="ph-colors" role="radiogroup" aria-label="Photo colour">
          {CONTACT_COLORS.map((c, i) => <button key={c} role="radio" aria-checked={i === color} className={i === color ? 'on' : ''} style={{ background: c }} onClick={() => setColor(i)} aria-label={`Colour ${i + 1}`} />)}
        </div>
        <label>Name<input className="ph-input" value={name} maxLength={40} onChange={(e) => setName(e.target.value)} /></label>
        <label>Number<input className="ph-input" value={number} maxLength={8} placeholder="555-1234" inputMode="numeric" onChange={(e) => setNumber(e.target.value)} /></label>
        <label>Note<input className="ph-input" value={note} maxLength={80} onChange={(e) => setNote(e.target.value)} /></label>
        <button className="ph-btn primary" disabled={busy || !name.trim() || number.replace(/\D/g, '').length !== 7} onClick={() => void save()}>{busy ? 'Saving…' : 'Save'}</button>
      </div>
    </div>
  );
}

function Blocked({ onBack }: { onBack: () => void }) {
  const { toast } = usePhone();
  const [items, setItems] = useState<{ number: string; display: string; name?: string }[] | null>(null);
  const [add, setAdd] = useState('');
  const load = async () => { const r = await api<{ number: string; display: string; name?: string }[]>('blocked'); setItems(r.ok && r.data ? r.data : []); };
  useEffect(() => { void load(); }, []);
  const set = async (n: string, on: boolean) => { const r = await api('block', n, on); toast(r.message ?? '', r.ok ? 'ok' : 'error'); if (r.ok) { setAdd(''); await load(); } };
  return (
    <div className="ph-appview">
      <AppHeader title="Blocked" onBack={onBack} />
      <div className="ph-body">
        <p className="ph-help">Blocked numbers can't call you or start messages with you. In shared groups their messages are hidden from you.</p>
        <div className="ph-inline"><input className="ph-input" placeholder="555-1234" value={add} onChange={(e) => setAdd(e.target.value)} /><button className="ph-btn" disabled={add.replace(/\D/g, '').length !== 7} onClick={() => void set(add, true)}>Block</button></div>
        {!items ? <div className="ph-empty">Loading…</div> : items.length === 0 ? <div className="ph-empty">Nobody is blocked.</div> : (
          <ul className="ph-list">{items.map((b) => <li key={b.number}><div className="ph-row static"><span className="ph-row-main"><strong>{b.name ?? b.display}</strong><span className="muted">{b.display}</span></span><button className="ph-btn" onClick={() => void set(b.number, false)}>Unblock</button></div></li>)}</ul>
        )}
      </div>
    </div>
  );
}

/** Share a contact card into a conversation (direct by number). */
function ShareContact({ contact, onBack }: { contact: Contact; onBack: () => void }) {
  const { toast } = usePhone();
  const [to, setTo] = useState('');
  const [busy, setBusy] = useState(false);
  const send = async () => {
    setBusy(true);
    const r = await api('send', { to, kind: 'contact', contact: { name: contact.name, number: contact.number }, clientOp: newClientOp() });
    setBusy(false);
    toast(r.ok ? 'Contact card sent' : r.message ?? 'Not sent', r.ok ? 'ok' : 'error');
    if (r.ok) onBack();
  };
  return (
    <div className="ph-appview">
      <AppHeader title="Share contact" onBack={onBack} />
      <div className="ph-body ph-form">
        <div className="ph-card-preview"><Icon name="user" size="1rem" /> {contact.name} · {contact.display}</div>
        <label>Send to number<input className="ph-input" value={to} placeholder="555-1234" onChange={(e) => setTo(e.target.value)} /></label>
        <button className="ph-btn primary" disabled={busy || to.replace(/\D/g, '').length !== 7} onClick={() => void send()}>Send card</button>
      </div>
    </div>
  );
}
