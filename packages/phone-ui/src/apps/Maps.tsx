// Maps: places everyone knows, your saved places, and locations people shared with you (live ones follow them).
// GPS sets a waypoint in the game. Sharing sends your position to a phone number for a while.
import { useEffect, useMemo, useState } from 'react';
import { api, post } from '../api';
import { formatDigits } from '../format';
import { Ico } from '../icons';
import { Avatar, Button, Empty, Header, Segmented, SearchField, Sheet, TextInput, Toggle, say, toast } from '../ui';
import { Chip, Loaded, useLoad } from './kit';
import type { Contact } from '../types';

type Saved = { id: number; label: string; x: number; y: number };
type Shared = { id: number; from_name: string; x: number; y: number; live: number; expires: number };
type Place = { label: string; category: string; x: number; y: number };
type Data = { saved: Saved[]; shared: Shared[]; places: Place[]; shareMinutes: number[] };

const CAT: Record<string, { icon: string; color: string }> = {
  City: { icon: 'briefcase', color: '#6a6cf0' }, Services: { icon: 'shield', color: '#e0576a' }, Food: { icon: 'bag', color: '#ef7a3a' },
  Vehicles: { icon: 'car', color: '#3a7bf0' }, Housing: { icon: 'home', color: '#34a853' }, Jobs: { icon: 'wrench', color: '#b8782f' },
};
const look = (c: string) => CAT[c] ?? { icon: 'pin', color: '#6f7585' };
const gps = async (x: number, y: number, label: string) => { await post('waypoint', { x, y }); toast(`Waypoint set: ${label}`); };
const left = (ts: number) => { const m = Math.max(0, Math.round((ts - Date.now() / 1000) / 60)); return m < 1 ? 'ending' : `${m} min left`; };

export function MapsApp() {
  const load = useLoad(() => api<Data>('mapsData'));
  const [tab, setTab] = useState<'places' | 'saved' | 'shared'>('places');
  const [q, setQ] = useState('');
  const [sheet, setSheet] = useState<'save' | 'share' | null>(null);

  // Live shares move: refresh while this tab is showing.
  useEffect(() => {
    if (tab !== 'shared') return;
    const t = window.setInterval(() => void load.reload(), 10000);
    return () => window.clearInterval(t);
  }, [tab, load]);

  const places = useMemo(() => (load.data?.places ?? []).filter((p) => `${p.label} ${p.category}`.toLowerCase().includes(q.trim().toLowerCase())), [load.data, q]);
  const grouped = useMemo(() => {
    const m = new Map<string, Place[]>();
    for (const p of places) m.set(p.category, [...(m.get(p.category) ?? []), p]);
    return [...m.entries()];
  }, [places]);

  return (
    <div className="ph-app">
      <Header title="Maps" right={<button className="ph-link" onClick={() => setSheet('share')}><Ico name="share" size={15} /> Share location</button>} />
      <div className="ph-pad">
        <Segmented options={[{ id: 'places', label: 'Places' }, { id: 'saved', label: 'Saved' }, { id: 'shared', label: load.data?.shared.length ? `Shared (${load.data.shared.length})` : 'Shared' }]} value={tab} onChange={setTab} />
      </div>
      <div className="ph-scroll ph-pad">
        <Loaded {...load}>
          {(d) => (
            <>
              {tab === 'places' && (
                <>
                  <SearchField value={q} onChange={setQ} placeholder="Search places" />
                  {grouped.length === 0 && <Empty icon="search" title="No places found" />}
                  {grouped.map(([cat, list]) => (
                    <section key={cat} className="ph-mapgroup">
                      <h4><span style={{ background: look(cat).color }}><Ico name={look(cat).icon} size={12} /></span>{cat}</h4>
                      {list.map((p) => (
                        <button key={p.label} className="ph-place" onClick={() => void gps(p.x, p.y, p.label)}>
                          <span className="ph-place-ico" style={{ background: look(cat).color }}><Ico name={look(cat).icon} size={16} /></span>
                          <strong>{p.label}</strong>
                          <span className="ph-gps"><Ico name="nav" size={14} /> GPS</span>
                        </button>
                      ))}
                    </section>
                  ))}
                </>
              )}
              {tab === 'saved' && (
                <>
                  <Button kind="primary" block onClick={() => setSheet('save')}><Ico name="pin" size={16} /> Save my location</Button>
                  {d.saved.length === 0 && <Empty icon="pin" title="No saved places" text="Save where you are, like your garage or a good fishing spot." />}
                  {d.saved.map((s) => (
                    <div key={s.id} className="ph-place static">
                      <span className="ph-place-ico" style={{ background: '#8b63d6' }}><Ico name="pin" size={16} /></span>
                      <strong>{s.label}</strong>
                      <button className="ph-gps" onClick={() => void gps(s.x, s.y, s.label)}><Ico name="nav" size={14} /> GPS</button>
                      <button className="ph-iconmini" onClick={async () => { if (say(await api('placeDelete', s.id))) void load.reload(); }} aria-label={`Delete ${s.label}`}><Ico name="trash" size={15} /></button>
                    </div>
                  ))}
                </>
              )}
              {tab === 'shared' && (
                <>
                  {d.shared.length === 0 && <Empty icon="nav" title="Nothing shared with you" text="When someone shares their location it shows up here." />}
                  {d.shared.map((s) => (
                    <div key={s.id} className="ph-sharedcard">
                      <Avatar name={s.from_name} id={s.from_name} size={44} />
                      <span><strong>{s.from_name}</strong><em>{s.live ? <b className="ph-livedot" /> : null}{s.live ? 'Live location' : 'Shared location'} · {left(s.expires)}</em></span>
                      <button className="ph-gps" onClick={() => void gps(s.x, s.y, s.from_name)}><Ico name="nav" size={14} /> GPS</button>
                    </div>
                  ))}
                </>
              )}
            </>
          )}
        </Loaded>
      </div>
      {sheet === 'save' && <SaveSheet onClose={() => setSheet(null)} onSaved={() => { setSheet(null); void load.reload(); }} />}
      {sheet === 'share' && load.data && <ShareSheet minutes={load.data.shareMinutes} onClose={() => setSheet(null)} />}
    </div>
  );
}

function SaveSheet({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const [label, setLabel] = useState('');
  return (
    <Sheet title="Save this place" onClose={onClose}>
      <div className="ph-form">
        <label>Name<TextInput value={label} onChange={setLabel} placeholder="My garage" maxLength={40} autoFocus onEnter={async () => { if (label.trim() && say(await api('placeSave', label))) onSaved(); }} /></label>
        <p className="ph-hint">Saves the spot where you are standing right now.</p>
        <Button kind="primary" block disabled={!label.trim()} onClick={async () => { if (say(await api('placeSave', label))) onSaved(); }}>Save place</Button>
      </div>
    </Sheet>
  );
}

function ShareSheet({ minutes, onClose }: { minutes: number[]; onClose: () => void }) {
  const [number, setNumber] = useState('');
  const [mins, setMins] = useState(minutes[0] ?? 15);
  const [live, setLive] = useState(true);
  const [contacts, setContacts] = useState<Contact[]>([]);
  const [busy, setBusy] = useState(false);
  useEffect(() => { void api<Contact[]>('contacts').then((r) => setContacts(r.ok ? (r.data ?? []).slice(0, 10) : [])); }, []);
  const ok = number.replace(/\D/g, '').length === 7 && !busy;
  const send = async () => {
    setBusy(true);
    const r = await api('shareLocation', number, mins, live);
    setBusy(false);
    if (say(r)) onClose();
  };
  return (
    <Sheet title="Share my location" onClose={onClose}>
      <div className="ph-form">
        {contacts.length > 0 && (
          <div className="ph-quickrow">{contacts.map((c) => <button key={c.id} onClick={() => setNumber(c.number)}><Avatar name={c.name} id={c.number} size={46} /><span>{c.name.split(' ')[0]}</span></button>)}</div>
        )}
        <label>Phone number<TextInput value={formatDigits(number)} onChange={setNumber} placeholder="555-1234" inputMode="tel" /></label>
        <div className="ph-chiprow flush">{minutes.map((m) => <Chip key={m} active={mins === m} icon="clock" onClick={() => setMins(m)}>{m} min</Chip>)}</div>
        <div className="ph-form-row"><span>Follow me while sharing<br /><small className="ph-sub">Otherwise they get where you are right now</small></span><Toggle on={live} onChange={setLive} label="Live location" /></div>
        <Button kind="primary" block onClick={send} disabled={!ok}>Share for {mins} minutes</Button>
      </div>
    </Sheet>
  );
}

