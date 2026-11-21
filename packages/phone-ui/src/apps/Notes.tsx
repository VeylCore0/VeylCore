import { useCallback, useEffect, useState } from 'react';
import { Icon } from '@veyl/ui';
import { api } from '../api';
import { AppHeader, usePhone } from '../App';
import { timeAgo } from '../types';

interface Note { id: number; title: string; body: string; at: number }

export function NotesApp() {
  const { toast } = usePhone();
  const [items, setItems] = useState<Note[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [edit, setEdit] = useState<Partial<Note> | null>(null);
  const [search, setSearch] = useState('');
  const load = useCallback(async () => {
    const r = await api<Note[]>('notes');
    if (r.ok && r.data) { setItems(r.data); setError(null); } else setError(r.message ?? 'Could not load notes');
  }, []);
  useEffect(() => { void load(); }, [load]);

  if (edit) return <Editor note={edit} onBack={() => { setEdit(null); void load(); }} onDeleted={() => { setEdit(null); void load(); toast('Note deleted'); }} />;
  const q = search.trim().toLowerCase();
  const shown = (items ?? []).filter((n) => !q || n.title.toLowerCase().includes(q) || n.body.toLowerCase().includes(q));
  return (
    <div className="ph-appview">
      <AppHeader title="Notes" right={<button className="ph-icon-btn" aria-label="New note" onClick={() => setEdit({})}><Icon name="edit" size="1rem" /></button>} />
      <div className="ph-body">
        <label className="ph-search store-search"><Icon name="search" size="0.9rem" /><input placeholder="Search notes" value={search} onChange={(e) => setSearch(e.target.value)} /></label>
        {error && <div className="ph-empty">{error}<br /><button className="ph-link" onClick={() => void load()}>Retry</button></div>}
        {!error && items === null && <div className="ph-empty">Loading…</div>}
        {items?.length === 0 && <div className="ph-empty">No notes yet.<br /><button className="ph-link" onClick={() => setEdit({})}>Write one</button></div>}
        <ul className="ph-list">
          {shown.map((n) => (
            <li key={n.id}><button className="ph-row nt-row" onClick={() => setEdit(n)}>
              <span className="ph-row-main"><strong>{n.title}</strong><span className="muted">{timeAgo(n.at)} · {n.body.replace(/\s+/g, ' ').slice(0, 60) || 'No text'}</span></span>
            </button></li>
          ))}
        </ul>
      </div>
    </div>
  );
}

function Editor({ note, onBack, onDeleted }: { note: Partial<Note>; onBack: () => void; onDeleted: () => void }) {
  const { toast } = usePhone();
  const [id, setId] = useState(note.id);
  const [title, setTitle] = useState(note.title ?? '');
  const [body, setBody] = useState(note.body ?? '');
  const [saved, setSaved] = useState(true);
  const [busy, setBusy] = useState(false);
  const save = async () => {
    if (!title.trim() && !body.trim()) return true;
    setBusy(true);
    const r = await api<{ id: number }>('noteSave', { id, title, body });
    setBusy(false);
    if (!r.ok || !r.data) { toast(r.message ?? 'Could not save', 'error'); return false; }
    setId(r.data.id); setSaved(true);
    return true;
  };
  const back = async () => { if (saved || (await save())) onBack(); };
  const del = async () => {
    if (!id) { onBack(); return; }
    const r = await api('noteDelete', id);
    if (r.ok) onDeleted(); else toast(r.message ?? 'Could not delete', 'error');
  };
  return (
    <div className="ph-appview">
      <AppHeader title={saved ? 'Note' : 'Note · unsaved'} onBack={() => void back()}
        right={<>
          <button className="ph-icon-btn" aria-label="Delete note" onClick={() => void del()}><Icon name="close" size="1rem" /></button>
          <button className="ph-icon-btn" aria-label="Save note" disabled={busy || saved} onClick={() => void save()}><Icon name="check" size="1rem" /></button>
        </>} />
      <div className="ph-body nt-edit">
        <input className="nt-title" placeholder="Title" maxLength={48} value={title} onChange={(e) => { setTitle(e.target.value); setSaved(false); }} />
        <textarea className="nt-body" placeholder="Start writing…" maxLength={2000} value={body} autoFocus={!note.id} onChange={(e) => { setBody(e.target.value); setSaved(false); }} />
        <div className="ph-help">{body.length}/2000 · Saved when you go back</div>
      </div>
    </div>
  );
}
