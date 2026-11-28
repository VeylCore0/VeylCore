// Contacts: list with search, detail (call, message, favourite, block), add / edit.
import { useCallback, useEffect, useMemo, useState } from 'react';
import { api } from '../api';
import { openApp, startCall } from '../controller';
import { formatDigits } from '../format';
import { Ico } from '../icons';
import { useRouteOnce } from '../nav';
import { useStore } from '../store';
import { Avatar, Button, Empty, Group, Header, IconButton, Row, SearchField, Sheet, Spinner, TextInput, Toggle, say, toast } from '../ui';
import type { Contact, Nearby } from '../types';
import { GalleryPicker, galleryImage, resetContactPhotos, squareThumb } from './photos';

type Edit = { id?: number; name: string; number: string; note: string; favorite: boolean; photo?: string | null; photoChanged?: boolean };

export function ContactsApp({ route }: { route?: string }) {
  const [list, setList] = useState<Contact[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [q, setQ] = useState('');
  const [detail, setDetail] = useState<Contact | null>(null);
  const [edit, setEdit] = useState<Edit | null>(null);
  const [sharing, setSharing] = useState(false);

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
      <Header title="Contacts" right={<><IconButton icon="share" label="Share my number" onClick={() => setSharing(true)} /><IconButton icon="plus" label="New contact" tone="accent" onClick={() => setEdit({ name: '', number: '', note: '', favorite: false })} /></>} />
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
                    <Avatar name={c.name} id={c.number} size={40} photo={c.photo} />
                    <span className="ph-conv-main"><strong>{c.name}</strong></span>
                    {c.favorite && <Ico name="star" size={14} style={{ color: 'var(--ph-gold)' }} />}
                  </button>
                </li>
              ))}
            </ul>
          </section>
        ))}
      </div>
      {detail && <Detail c={detail} onClose={() => setDetail(null)} onEdit={(c) => { setDetail(null); setEdit({ id: c.id, name: c.name, number: c.number, note: c.note ?? '', favorite: c.favorite, photo: c.photo ?? null }); }}
        onChanged={(next) => { setDetail(next); void load(); }} onDeleted={() => { setDetail(null); void load(); }} />}
      {sharing && <ShareSheet onClose={() => setSharing(false)} />}
      {edit && <Form e={edit} onClose={() => setEdit(null)} onSaved={() => { setEdit(null); resetContactPhotos(); void load(); }} />}
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
        <Avatar name={c.name} id={c.number} size={76} photo={c.photo} />
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
  const [picking, setPicking] = useState(false);
  const ok = v.name.trim().length > 0 && v.number.replace(/\D/g, '').length === 7;
  const choose = async (photoId: number) => {
    setPicking(false);
    const full = await galleryImage(photoId);
    const thumb = full ? await squareThumb(full) : null;
    if (thumb) setV((x) => ({ ...x, photo: thumb, photoChanged: true })); else say({ ok: false, message: 'Could not use that photo' } as never);
  };
  const save = async () => {
    setBusy(true);
    // The picture is only sent when it was changed here (a new one, or false to remove it); otherwise the server keeps the old one.
    const body: Record<string, unknown> = { id: v.id, name: v.name, number: v.number.replace(/\D/g, ''), note: v.note || undefined, favorite: v.favorite };
    if (v.photoChanged) body.photo = v.photo ?? false;
    const r = await api('contactSave', body);
    setBusy(false);
    if (say(r)) onSaved();
  };
  return (
    <Sheet title={v.id ? 'Edit contact' : 'New contact'} onClose={onClose}>
      <div className="ph-form">
        <div className="ph-contactpic">
          <Avatar name={v.name} id={v.number} size={84} photo={v.photo} />
          <div>
            <button className="ph-link" onClick={() => setPicking(true)}>{v.photo ? 'Change photo' : 'Add photo'}</button>
            {v.photo && <button className="ph-link danger" onClick={() => setV({ ...v, photo: null, photoChanged: true })}>Remove photo</button>}
          </div>
        </div>
        <label>Name<TextInput value={v.name} onChange={(name) => setV({ ...v, name })} placeholder="Name" maxLength={limits?.name ?? 40} autoFocus={!v.name} /></label>
        <label>Number<TextInput value={formatDigits(v.number)} onChange={(number) => setV({ ...v, number })} placeholder="555-1234" inputMode="tel" autoFocus={!!v.name && !v.number} /></label>
        <label>Note<TextInput value={v.note} onChange={(note) => setV({ ...v, note })} placeholder="Optional" maxLength={80} /></label>
        <div className="ph-form-row"><span>Favorite</span><Toggle on={v.favorite} onChange={(favorite) => setV({ ...v, favorite })} label="Favorite" /></div>
        <Button kind="primary" block onClick={save} disabled={!ok || busy}>Save contact</Button>
      </div>
      {picking && <GalleryPicker title="Contact photo" onPick={(id) => void choose(id)} onClose={() => setPicking(false)} />}
    </Sheet>
  );
}

/** "Share my number": people standing next to you who have a phone. They get a prompt and can save you. */
function ShareSheet({ onClose }: { onClose: () => void }) {
  const hello = useStore((s) => s.hello);
  const streamer = useStore((s) => s.settings.streamer);
  const airplane = useStore((s) => s.settings.airplane);
  const [list, setList] = useState<Nearby[] | null>(null);
  const [sent, setSent] = useState<Set<number>>(new Set());
  const [busy, setBusy] = useState<number | null>(null);

  const scan = useCallback(async () => {
    const r = await api<Nearby[]>('nearby');
    if (r.ok) setList(r.data ?? []); else if (list === null) setList([]);
  }, [list]);
  useEffect(() => {
    void scan();
    const t = window.setInterval(() => { void scan(); }, 4000);
    return () => window.clearInterval(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const send = async (p: Nearby) => {
    setBusy(p.id);
    const r = await api('shareNumber', p.id);
    setBusy(null);
    if (say(r)) setSent((s) => new Set(s).add(p.id));
  };

  return (
    <Sheet title="Share my number" onClose={onClose}>
      <div className="ph-share-me">
        <span className="ph-share-radar"><i /><i /><Ico name="share" size={22} /></span>
        <strong>{streamer ? '•••-••••' : hello?.display}</strong>
        <span className="ph-sub">{airplane ? 'Turn off airplane mode to share' : 'Pick someone next to you. They choose whether to save you.'}</span>
      </div>
      {list === null && <Spinner />}
      {list?.length === 0 && <Empty icon="users" title="No one nearby" text="Stand next to someone who has a phone." />}
      {!!list?.length && (
        <Group title="Nearby">
          {list.map((p) => (
            <div key={p.id} className="ph-near">
              <Avatar name={p.name} id={String(p.id)} size={40} />
              <span><strong>{p.name}</strong><em>{p.distance < 1 ? 'Right here' : `${p.distance.toFixed(1)} m away`}</em></span>
              {sent.has(p.id) ? <span className="ph-near-sent"><Ico name="check" size={15} stroke={3} /> Sent</span>
                : <Button kind="primary" onClick={() => send(p)} disabled={busy === p.id || airplane}>Send</Button>}
            </div>
          ))}
        </Group>
      )}
    </Sheet>
  );
}
