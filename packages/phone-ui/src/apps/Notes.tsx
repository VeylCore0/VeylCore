// Notes: private to the character. Autosaves when you leave a note; empty new notes are discarded.
import { useMemo, useState } from 'react';
import { api } from '../api';
import { listTime } from '../format';
import { Ico } from '../icons';
import { useBack } from '../nav';
import { Button, Empty, Header, IconButton, SearchField, Sheet, TextInput, say } from '../ui';
import { Fab, Loaded, useLoad } from './kit';

type Note = { id: number; title: string; body: string; at: number };
type Draft = { id?: number; title: string; body: string };

const STRIPES = ['#8b63d6', '#4f8cff', '#2fbf8a', '#f2b443', '#ef6f7c', '#d98a45'];

export function NotesApp() {
  const load = useLoad(() => api<Note[]>('notes'));
  const [q, setQ] = useState('');
  const [draft, setDraft] = useState<Draft | null>(null);

  const list = useMemo(() => (load.data ?? []).filter((n) => `${n.title} ${n.body}`.toLowerCase().includes(q.trim().toLowerCase())), [load.data, q]);

  if (draft) {
    return <Editor draft={draft} onClose={() => { setDraft(null); void load.reload(); }} />;
  }
  return (
    <div className="ph-app">
      <Header title="Notes" />
      <div className="ph-pad">{!!load.data?.length && <SearchField value={q} onChange={setQ} />}</div>
      <div className="ph-scroll">
        <Loaded {...load}>
          {(notes) => notes.length === 0
            ? <Empty icon="note" title="No notes" text="Jot something down. Only you can see your notes." action={<Button kind="primary" onClick={() => setDraft({ title: '', body: '' })}>New note</Button>} />
            : list.length === 0 ? <Empty icon="search" title="No results" /> : (
              <div className="ph-notegrid">
                {list.map((n) => (
                  <button key={n.id} className="ph-ncard" onClick={() => setDraft({ id: n.id, title: n.title, body: n.body })} style={{ ['--stripe' as string]: STRIPES[n.id % STRIPES.length] }}>
                    <strong>{n.title}</strong>
                    <span>{n.body || 'No text'}</span>
                    <time>{listTime(n.at)}</time>
                  </button>
                ))}
              </div>
            )}
        </Loaded>
      </div>
      <Fab label="New note" icon="edit" onClick={() => setDraft({ title: '', body: '' })} />
    </div>
  );
}

function Editor({ draft, onClose }: { draft: Draft; onClose: () => void }) {
  const [title, setTitle] = useState(draft.title);
  const [body, setBody] = useState(draft.body);
  const [confirm, setConfirm] = useState(false);
  const dirty = title !== draft.title || body !== draft.body;

  const save = async () => {
    if (!dirty) return onClose();
    if (!title.trim() && !body.trim()) { if (!draft.id) return onClose(); }
    const r = await api('noteSave', { id: draft.id, title, body });
    if (!r.ok) { say(r); return; }
    onClose();
  };
  useBack(true, () => { void save(); return true; });
  const remove = async () => { if (draft.id && say(await api('noteDelete', draft.id))) onClose(); else if (!draft.id) onClose(); };

  return (
    <div className="ph-app ph-noteedit">
      <Header onBack={() => void save()} backLabel="Notes" large={false}
        right={<>{draft.id && <IconButton icon="trash" label="Delete note" tone="danger" onClick={() => setConfirm(true)} />}<Button kind="primary" onClick={() => void save()}>Done</Button></>} />
      <div className="ph-noteedit-body">
        <TextInput value={title} onChange={setTitle} placeholder="Title" maxLength={48} className="ph-notetitle" autoFocus={!draft.id} />
        <TextInput multiline value={body} onChange={setBody} placeholder="Start typing..." maxLength={2000} className="ph-notebody" />
        <span className="ph-sub">{body.length} / 2000</span>
      </div>
      {confirm && (
        <Sheet title="Delete this note?" onClose={() => setConfirm(false)}>
          <div className="ph-form">
            <p className="ph-hint">This cannot be undone.</p>
            <Button kind="danger" block onClick={remove}><Ico name="trash" size={16} /> Delete note</Button>
            <Button kind="ghost" block onClick={() => setConfirm(false)}>Keep it</Button>
          </div>
        </Sheet>
      )}
    </div>
  );
}
