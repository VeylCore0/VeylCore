import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { CloseHint, Icon, SearchBox, StateView, announceReady, nui, useNuiMessage } from '@veyl/ui';

// ---------------------------------------------------------------------------
// Types (see resources/[veyl]/veyl_emotes/client/main.lua: openMenu)
// ---------------------------------------------------------------------------
interface Emote { id: string; label: string; cat: string; prop: boolean; shared: boolean; loop: boolean }
interface Category { id: string; label: string }
interface OpenData { emotes: Emote[]; categories: Category[]; favourites: string[]; current?: string | null; command: string; maxFavourites: number }

export function App() {
  const [data, setData] = useState<OpenData | null>(null);
  const [favs, setFavs] = useState<string[]>([]);
  const [current, setCurrent] = useState<string | null>(null);
  const [cat, setCat] = useState<string>('all');
  const [search, setSearch] = useState('');
  const [note, setNote] = useState<string | null>(null);
  const timer = useRef<number>();
  useEffect(() => announceReady(), []);

  // You can keep walking with the menu open; while the search box has focus, Lua pauses movement.
  useEffect(() => {
    const isField = (el: EventTarget | null) => el instanceof HTMLInputElement;
    const onIn = (e: FocusEvent) => { if (isField(e.target)) void nui('ui:typing', { typing: true }); };
    const onOut = (e: FocusEvent) => { if (isField(e.target)) void nui('ui:typing', { typing: false }); };
    document.addEventListener('focusin', onIn);
    document.addEventListener('focusout', onOut);
    return () => { document.removeEventListener('focusin', onIn); document.removeEventListener('focusout', onOut); };
  }, []);

  useNuiMessage<OpenData>('emotes:open', (d) => {
    setData(d);
    setFavs(d.favourites);
    setCurrent(d.current ?? null);
    setCat(d.favourites.length > 0 ? 'favourites' : 'all');
    setSearch('');
  });
  useNuiMessage('emotes:close', () => setData(null));
  useNuiMessage<{ current: string | null }>('emotes:current', (d) => setCurrent(d.current ?? null));

  const close = useCallback(() => { void nui('close'); setData(null); }, []);
  useEffect(() => {
    if (!data) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return; // F3 reaches the game (keepInput) and toggles the menu from Lua
      const t = e.target as HTMLElement;
      if (t && t.tagName === 'INPUT') { t.blur(); return; }
      close();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [data, close]);

  const say = (text: string) => {
    setNote(text);
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setNote(null), 3000);
  };

  const list = useMemo(() => {
    if (!data) return [];
    const q = search.trim().toLowerCase();
    const byId = new Map(data.emotes.map((e) => [e.id, e]));
    let rows: Emote[];
    if (q) rows = data.emotes.filter((e) => e.label.toLowerCase().includes(q) || e.id.includes(q));
    else if (cat === 'favourites') rows = favs.map((id) => byId.get(id)).filter((e): e is Emote => !!e);
    else if (cat === 'all') rows = data.emotes;
    else rows = data.emotes.filter((e) => e.cat === cat);
    return rows;
  }, [data, cat, search, favs]);

  if (!data) return null;

  const play = (e: Emote) => { void nui('play', { id: e.id }); if (e.shared) say('Asking the person next to you…'); };
  const toggleFav = async (e: Emote) => {
    const on = !favs.includes(e.id);
    const r = await nui<string[]>('favourite', { id: e.id, on });
    if (r.ok && r.data) setFavs(r.data);
    else if (r.message) say(r.message);
  };

  const tabs: Category[] = [{ id: 'favourites', label: '★' }, { id: 'all', label: 'All' }, ...data.categories];

  return (
    <aside className="em-panel v-panel" aria-label="Emotes">
      <header className="em-head">
        <div className="em-title"><Icon name="hand" size="1.1rem" /> Emotes</div>
        <CloseHint onClose={close} />
      </header>
      <SearchBox value={search} onChange={setSearch} placeholder="Search emotes…" />
      {!search && (
        <div className="em-tabs" role="tablist">
          {tabs.map((t) => (
            <button key={t.id} role="tab" aria-selected={cat === t.id} className={`em-tab${cat === t.id ? ' active' : ''}`} onClick={() => setCat(t.id)}
              title={t.id === 'favourites' ? 'Favourites' : undefined}>{t.label}</button>
          ))}
        </div>
      )}
      <div className="em-list v-scroll">
        {list.length === 0 && (
          <StateView kind="empty" message={search ? 'No emotes match.' : cat === 'favourites' ? 'Star an emote to keep it here.' : 'Nothing here.'} />
        )}
        {list.map((e) => {
          const fav = favs.includes(e.id);
          return (
            <div key={e.id} className={`em-row${current === e.id ? ' playing' : ''}`}>
              <button className="em-play" onClick={() => play(e)}>
                <span className="em-label">{e.label}</span>
                <span className="em-meta">
                  {e.shared && <span className="em-tag">with someone</span>}
                  {e.prop && <span className="em-tag">prop</span>}
                  <code>/{data.command} {e.id}</code>
                </span>
              </button>
              <button className={`em-star${fav ? ' on' : ''}`} aria-label={fav ? `Remove ${e.label} from favourites` : `Add ${e.label} to favourites`}
                onClick={() => void toggleFav(e)}><Icon name="star" size="1rem" /></button>
            </div>
          );
        })}
      </div>
      <footer className="em-foot">
        <button className="v-btn block" disabled={!current} onClick={() => { void nui('stop'); setCurrent(null); }}>
          <Icon name="block" size="1rem" /> Stop emote <span className="v-key">X</span>
        </button>
        {note && <div className="em-note" role="status">{note}</div>}
      </footer>
    </aside>
  );
}
