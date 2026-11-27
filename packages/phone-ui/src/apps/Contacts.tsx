// Contacts: list with search, detail (call, message, favourite, block), add / edit.
import { useCallback, useEffect, useMemo, useState } from 'react';
import { api } from '../api';
import { openApp, startCall } from '../controller';
import { formatDigits } from '../format';
import { Ico } from '../icons';
import { useRouteOnce } from '../nav';
import { useStore } from '../store';
import { Avatar, Button, Empty, Group, Header, IconButton, Row, SearchField, Sheet, Spinner, TextInput, Toggle, say, toast } from '../ui';
import type { Contact } from '../types';

type Edit = { id?: number; name: string; number: string; note: string; favorite: boolean };

export function ContactsApp({ route }: { route?: string }) {
  const [list, setList] = useState<Contact[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [q, setQ] = useState('');
  const [detail, setDetail] = useState<Contact | null>(null);
  const [edit, setEdit] = useState<Edit | null>(null);

  const load = useCallback(async () => {
    const r = await api<Contact[]>('contacts');
    if (r.ok) { setList(r.data ?? []); setFailed(false); } else setFailed(true);
  }, []);
  useEffect(() => { void load(); }, [load]);
  useRouteOnce(route, (r) => {
    const m = /^new\/(\d{7})$/.exec(r);
    if (m) setEdit({ name: '', number: m[1], note: '', favorite: false });
  });

  const groups = useMemo(() => {
    const out = new Map<string, Contact[]>();
    for (const c of (list ?? []).filter((x) => `${x.name} ${x.number}`.toLowerCase().includes(q.trim().toLowerCase()))) {
      const k = /[a-z]/i.test(c.name[0] ?? '') ? c.name[0].toUpperCase() : '#';
      out.set(k, [...(out.get(k) ?? []), c]);
    }
    return [...out.entries()].sort(([a], [b]) => (a === '#' ? 1 : b === '#' ? -1 : a.localeCompare(b)));
  }, [list, q]);

  return (
    <div className="ph-app">
      <Header title="Contacts" right={<IconButton icon="plus" label="New contact" tone="accent" onClick={() => setEdit({ name: '', number: '', note: '', favorite: false })} />} />
      {!!list?.length && <div className="ph-pad"><SearchField value={q} onChange={setQ} /></div>}
      <div className="ph-scroll">
        {list === null && !failed && <Spinner />}
        {failed && !list && <Empty icon="x" title="Could not load contacts" action={<Button onClick={load}>Try again</Button>} />}
        {list?.length === 0 && <Empty icon="users" title="No contacts" text="Save people you call and message often." action={<Button kind="primary" onClick={() => setEdit({ name: '', number: '', note: '', favorite: false })}>Add contact</Button>} />}
        {list && list.length > 0 && groups.length === 0 && <Empty icon="search" title="No results" />}
        {groups.map(([letter, items]) => (
          <section key={letter} className="ph-letter">
            <h5>{letter}</h5>
            <ul className="ph-list">
              {items.map((c) => (
                <li key={c.id}>
                  <button className="ph-conv" onClick={() => setDetail(c)}>
                    <Avatar name={c.name} id={c.number} size={40} />
                    <span className="ph-conv-main"><strong>{c.name}</strong></span>
                    {c.favorite && <Ico name="star" size={14} style={{ color: 'var(--ph-gold)' }} />}
                  </button>
                </li>
              ))}
            </ul>
          </section>
        ))}
      </div>
      {detail && <Detail c={detail} onClose={() => setDetail(null)} onEdit={(c) => { setDetail(null); setEdit({ id: c.id, name: c.name, number: c.number, note: c.note ?? '', favorite: c.favorite }); }}
        onChanged={(next) => { setDetail(next); void load(); }} onDeleted={() => { setDetail(null); void load(); }} />}
      {edit && <Form e={edit} onClose={() => setEdit(null)} onSaved={() => { setEdit(null); void load(); }} />}
    </div>
  );
}

function Detail({ c, onClose, onEdit, onChanged, onDeleted }: { c: Contact; onClose: () => void; onEdit: (c: Contact) => void; onChanged: (c: Contact | null) => void; onDeleted: () => void }) {
  const [blocked, setBlocked] = useState<boolean | null>(null);
  const call = useStore((s) => s.call);
  const voice = useStore((s) => s.hello?.voice.available);
  useEffect(() => { void api<{ number: string }[]>('blocks').then((r) => setBlocked(!!r.data?.some((b) => b.number === c.number))); }, [c.number]);

  const fav = async () => {
    const r = await api<Contact>('contactSave', { id: c.id, name: c.name, number: c.number, note: c.note, favorite: !c.favorite });
    if (say(r)) onChanged(r.data ?? null);
  };
  const block = async () => {
    const r = await api<{ blocked: boolean }>('block', c.number, !blocked);
    if (say(r)) { setBlocked(!blocked); toast(!blocked ? 'Blocked' : 'Unblocked'); }
  };
  const del = async () => { if (say(await api('contactDelete', c.id))) onDeleted(); };

  return (
    <Sheet title="Contact" onClose={onClose} actions={<button className="ph-link" onClick={() => onEdit(c)}>Edit</button>}>
      <div className="ph-info-head">
        <Avatar name={c.name} id={c.number} size={76} />
        <strong>{c.name}</strong>
        <span className="ph-sub">{c.display}</span>
        {c.note && <span className="ph-note">{c.note}</span>}
      </div>
      <div className="ph-info-actions">
        <button onClick={() => { onClose(); void startCall(c.number); }} disabled={!voice || !!call}><Ico name="phone" size={20} /><span>Call</span></button>
        <button onClick={() => { onClose(); openApp('messages', `to/${c.number}`); }}><Ico name="chat" size={20} /><span>Message</span></button>
        <button onClick={fav}><Ico name="star" size={20} style={{ color: c.favorite ? 'var(--ph-gold)' : undefined }} /><span>{c.favorite ? 'Unfavorite' : 'Favorite'}</span></button>
      </div>
      <Group>
        <Row icon="block" iconColor="#c25661" title={blocked ? 'Unblock this number' : 'Block this number'} onClick={blocked === null ? undefined : block} />
        <Row icon="trash" iconColor="#c25661" danger title="Delete contact" onClick={del} />
      </Group>
    </Sheet>
  );
}

function Form({ e, onClose, onSaved }: { e: Edit; onClose: () => void; onSaved: () => void }) {
  const [v, setV] = useState(e);
  const [busy, setBusy] = useState(false);
  const limits = useStore((s) => s.hello?.limits);
  const ok = v.name.trim().length > 0 && v.number.replace(/\D/g, '').length === 7;
  const save = async () => {
    setBusy(true);
    const r = await api('contactSave', { id: v.id, name: v.name, number: v.number.replace(/\D/g, ''), note: v.note || undefined, favorite: v.favorite });
    setBusy(false);
    if (say(r)) onSaved();
  };
  return (
    <Sheet title={v.id ? 'Edit contact' : 'New contact'} onClose={onClose}>
      <div className="ph-form">
        <label>Name<TextInput value={v.name} onChange={(name) => setV({ ...v, name })} placeholder="Name" maxLength={limits?.name ?? 40} autoFocus={!v.name} /></label>
        <label>Number<TextInput value={formatDigits(v.number)} onChange={(number) => setV({ ...v, number })} placeholder="555-1234" inputMode="tel" autoFocus={!!v.name && !v.number} /></label>
        <label>Note<TextInput value={v.note} onChange={(note) => setV({ ...v, note })} placeholder="Optional" maxLength={80} /></label>
        <div className="ph-form-row"><span>Favorite</span><Toggle on={v.favorite} onChange={(favorite) => setV({ ...v, favorite })} label="Favorite" /></div>
        <Button kind="primary" block onClick={save} disabled={!ok || busy}>Save contact</Button>
      </div>
    </Sheet>
  );
}
