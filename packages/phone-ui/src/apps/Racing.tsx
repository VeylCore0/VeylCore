// Racing: record a track checkpoint by checkpoint, host or join a race at its start, and see the best times.
import { useState } from 'react';
import { api, post } from '../api';
import { Ico } from '../icons';
import { Button, Empty, Header, Segmented, Sheet, TextInput, cx, say, toast } from '../ui';
import { Chip, Fab, Loaded, useLoad } from './kit';

type Track = { id: number; name: string; creator: string; points: number; best: number | null };
type Open = { id: number; track: string; host: string; racers: number; mine: boolean; joined: boolean };
type Data = { tracks: Track[]; open: Open[] };
type Pt = { x: number; y: number; z: number };

export const raceTime = (ms: number | null) => {
  if (ms == null) return '--';
  const s = ms / 1000;
  return `${Math.floor(s / 60)}:${(s % 60).toFixed(2).padStart(5, '0')}`;
};

export function RacingApp() {
  const load = useLoad(() => api<Data>('raceData'));
  const [tab, setTab] = useState<'races' | 'tracks'>('races');
  const [rec, setRec] = useState(false);
  const [board, setBoard] = useState<Track | null>(null);

  const act = async (p: ReturnType<typeof api>) => { if (say(await p)) void load.reload(); };
  const join = async (r: Open) => {
    const res = await api<{ start: Pt }>('raceJoin', r.id);
    if (!say(res)) return;
    if (res.data?.start) await post('waypoint', { x: res.data.start.x, y: res.data.start.y });
    void load.reload();
  };
  const host = async (t: Track) => {
    const res = await api<{ id: number; start: Pt }>('raceHost', t.id);
    if (!say(res)) return;
    if (res.data?.start) await post('waypoint', { x: res.data.start.x, y: res.data.start.y });
    setTab('races'); void load.reload();
  };

  return (
    <div className="ph-app">
      <Header title="Racing" />
      <div className="ph-pad"><Segmented options={[{ id: 'races', label: load.data?.open.length ? `Open races (${load.data.open.length})` : 'Open races' }, { id: 'tracks', label: 'Tracks' }]} value={tab} onChange={setTab} /></div>
      <div className="ph-scroll ph-pad">
        <Loaded {...load}>
          {(d) => tab === 'races' ? (
            d.open.length === 0
              ? <Empty icon="flag" title="No open races" text="Host one from a track, then others near the start can join." />
              : d.open.map((r) => (
                <div key={r.id} className="ph-racecard">
                  <span className="ph-race-flag"><Ico name="flag" size={20} /></span>
                  <span className="ph-race-main"><strong>{r.track}</strong><em>Hosted by {r.host} · {r.racers} racer{r.racers === 1 ? '' : 's'}</em></span>
                  {r.mine ? <Button kind="primary" onClick={() => void act(api('raceStart', r.id))}>Start</Button>
                    : r.joined ? <Chip tone="ok" icon="check">Joined</Chip>
                    : <Button kind="primary" onClick={() => void join(r)}>Join</Button>}
                </div>
              ))
          ) : (
            d.tracks.length === 0
              ? <Empty icon="flag" title="No tracks yet" text="Record one: drive the route and mark checkpoints." />
              : d.tracks.map((t) => (
                <div key={t.id} className="ph-track">
                  <span className="ph-track-main"><strong>{t.name}</strong><em>{t.points} checkpoints · by {t.creator}</em></span>
                  <span className="ph-track-best"><small>Best</small>{raceTime(t.best)}</span>
                  <button className="ph-iconmini" onClick={() => setBoard(t)} aria-label={`Leaderboard for ${t.name}`}><Ico name="star" size={15} /></button>
                  <button className="ph-gps" onClick={() => void host(t)}>Host</button>
                </div>
              ))
          )}
        </Loaded>
      </div>
      {tab === 'tracks' && <Fab icon="plus" label="Record a track" onClick={() => setRec(true)} />}
      {rec && <RecordSheet onClose={() => setRec(false)} onDone={() => { setRec(false); void load.reload(); }} />}
      {board && <BoardSheet t={board} onClose={() => setBoard(null)} />}
    </div>
  );
}

function RecordSheet({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const [pts, setPts] = useState<Pt[]>([]);
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(false);
  const mark = async () => {
    const r = await post<Pt>('raceMark');
    if (r.ok && r.data) { setPts((p) => (p.length >= 40 ? p : [...p, r.data as Pt])); } else toast('Could not read your position', 'error');
  };
  const save = async () => { setBusy(true); const r = await api('raceTrackSave', name, pts); setBusy(false); if (say(r)) onDone(); };
  return (
    <Sheet title="Record a track" onClose={onClose}>
      <div className="ph-form">
        <p className="ph-hint">Drive the route and tap <b>Mark checkpoint</b> where each gate should be. The first mark is the start, the last is the finish.</p>
        <div className="ph-markcount"><strong>{pts.length}</strong><span>checkpoint{pts.length === 1 ? '' : 's'}</span>{pts.length > 0 && <button className="ph-link" onClick={() => setPts((p) => p.slice(0, -1))}>Undo</button>}</div>
        <Button block onClick={() => void mark()}><Ico name="pin" size={16} /> Mark checkpoint</Button>
        <label>Track name<TextInput value={name} onChange={setName} placeholder="Vinewood Sprint" maxLength={40} /></label>
        <Button kind="primary" block disabled={pts.length < 2 || name.trim().length < 3 || busy} onClick={save}>Save track</Button>
      </div>
    </Sheet>
  );
}

function BoardSheet({ t, onClose }: { t: Track; onClose: () => void }) {
  const load = useLoad(() => api<{ name: string; ms: number }[]>('raceBoard', t.id));
  return (
    <Sheet title={t.name} onClose={onClose}>
      <Loaded {...load}>
        {(rows) => rows.length === 0 ? <Empty icon="flag" title="No times yet" text="Be the first to finish." /> : (
          <ol className="ph-board">{rows.map((r, i) => <li key={r.name} className={cx(i === 0 && 'gold')}><b>{i + 1}</b><span>{r.name}</span><time>{raceTime(r.ms)}</time></li>)}</ol>
        )}
      </Loaded>
    </Sheet>
  );
}
