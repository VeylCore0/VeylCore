// Phone 2.0 phase 2 apps: Camera (with Gallery), Jobs, Bills, Music, News and Racing.
import { useCallback, useEffect, useState, useSyncExternalStore } from 'react';
import { Icon, nui } from '@veyl/ui';
import { api } from '../api';
import { AppHeader, usePhone } from '../App';
import { timeAgo } from '../types';
import { music, setStations, type Station } from '../music';

const money = (n: number) => `$${Math.round(n).toLocaleString('en-US')}`;
function Seg<T extends string>({ value, options, onChange }: { value: T; options: [T, string][]; onChange: (v: T) => void }) {
  return <div className="ph-seg" style={{ gridTemplateColumns: `repeat(${options.length}, 1fr)` }}>{options.map(([v, l]) => <button key={v} className={value === v ? 'on' : ''} onClick={() => onChange(v)}>{l}</button>)}</div>;
}

// ---------------------------------------------------------------------------
// Camera + Gallery
// ---------------------------------------------------------------------------
export function CameraApp() {
  const { toast } = usePhone();
  const [tab, setTab] = useState<'camera' | 'gallery'>('camera');
  const [last, setLast] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [photos, setPhotos] = useState<{ id: number; at: number }[] | null>(null);
  const [view, setView] = useState<{ id: number; image?: string } | null>(null);
  const [thumbs, setThumbs] = useState<Record<number, string>>({});

  const loadGallery = useCallback(async () => {
    const r = await api<{ id: number; at: number }[]>('photoList');
    if (r.ok && r.data) setPhotos(r.data);
  }, []);
  useEffect(() => { if (tab === 'gallery') void loadGallery(); }, [tab, loadGallery]);
  useEffect(() => { // fetch thumbnails a few at a time
    if (!photos) return;
    const missing = photos.filter((p) => !thumbs[p.id]).slice(0, 6);
    if (!missing.length) return;
    let off = false;
    void Promise.all(missing.map((p) => api<{ image: string }>('photoGet', p.id))).then((rs) => {
      if (off) return;
      setThumbs((t) => { const n = { ...t }; rs.forEach((r, i) => { if (r.ok && r.data) n[missing[i].id] = r.data.image; }); return n; });
    });
    return () => { off = true; };
  }, [photos, thumbs]);

  const shoot = async () => {
    setBusy(true);
    const r = await nui<{ image: string }>('cameraShot');
    if (!r.ok || !r.data?.image) { setBusy(false); toast(r.message ?? 'Camera unavailable', 'error'); return; }
    setLast(r.data.image);
    const s = await api('photoSave', r.data.image);
    setBusy(false);
    toast(s.message ?? (s.ok ? 'Saved' : 'Could not save'), s.ok ? undefined : 'error');
  };

  if (view) {
    return (
      <div className="ph-appview">
        <AppHeader title="Photo" onBack={() => setView(null)} right={<button className="ph-icon-btn" aria-label="Delete photo" onClick={async () => { await api('photoDelete', view.id); setView(null); setPhotos((p) => p?.filter((x) => x.id !== view.id) ?? null); }}><Icon name="close" size="1rem" /></button>} />
        <div className="ph-body">{thumbs[view.id] ? <img className="cm-full" src={thumbs[view.id]} alt="" /> : <div className="ph-empty">Loading…</div>}</div>
      </div>
    );
  }
  return (
    <div className="ph-appview">
      <AppHeader title={tab === 'camera' ? 'Camera' : 'Gallery'} />
      <div className="ph-body">
        <Seg value={tab} options={[['camera', 'Camera'], ['gallery', 'Gallery']]} onChange={setTab} />
        {tab === 'camera' ? (
          <div className="cm-cam">
            <div className="cm-preview">{last ? <img src={last} alt="Last photo" /> : <span className="muted">Frame your shot in the game view, then tap the shutter.</span>}</div>
            <button className="cm-shutter" disabled={busy} aria-label="Take photo" onClick={() => void shoot()}><Icon name="camera" size="1.4rem" /></button>
          </div>
        ) : (
          <>
            {photos === null && <div className="ph-empty">Loading…</div>}
            {photos?.length === 0 && <div className="ph-empty">No photos yet.</div>}
            <div className="cm-grid">{photos?.map((p) => <button key={p.id} onClick={() => setView(p)} aria-label={`Photo from ${timeAgo(p.at)}`}>{thumbs[p.id] ? <img src={thumbs[p.id]} alt="" /> : <span />}</button>)}</div>
          </>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Jobs
// ---------------------------------------------------------------------------
interface JobsData {
  mine: { name: string; label: string; grade: string; pay: number; primary: boolean }[]; primary: string; onduty: boolean; jobLabel: string;
  board: { job: string; label: string; description: string; open: boolean; apply?: string; member: boolean }[];
  apps: { id: number; job: string; status: string; at: number }[];
  inbox?: { id: number; name: string; number: string; message: string; status: string; at: number }[];
}
export function JobsApp() {
  const { toast } = usePhone();
  const [d, setD] = useState<JobsData | null>(null);
  const [tab, setTab] = useState<'mine' | 'board' | 'inbox'>('mine');
  const [applying, setApplying] = useState<JobsData['board'][number] | null>(null);
  const [text, setText] = useState('');
  const load = useCallback(async () => { const r = await api<JobsData>('jobsData'); if (r.ok && r.data) setD(r.data); else toast(r.message ?? 'Could not load', 'error'); }, [toast]);
  useEffect(() => { void load(); }, [load]);
  const act = async (name: string, ...args: unknown[]) => { const r = await api(name, ...args); toast(r.message ?? (r.ok ? 'Done' : 'Failed'), r.ok ? undefined : 'error'); void load(); return r.ok; };

  if (applying) {
    return (
      <div className="ph-appview">
        <AppHeader title={`Apply: ${applying.label}`} onBack={() => setApplying(null)} />
        <div className="ph-body ph-form">
          <div className="muted">{applying.description}</div>
          <label>Why should they hire you?<textarea className="ph-input" rows={6} maxLength={500} value={text} onChange={(e) => setText(e.target.value)} /></label>
          <button className="ph-btn wide primary" disabled={text.trim().length < 10} onClick={async () => { if (await act('jobsApply', applying.job, text)) { setApplying(null); setText(''); } }}><Icon name="send" size="0.9rem" /> Send application</button>
        </div>
      </div>
    );
  }
  const tabs: ['mine' | 'board' | 'inbox', string][] = [['mine', 'My jobs'], ['board', 'Job board']];
  if (d?.inbox) tabs.push(['inbox', `Applicants${d.inbox.length ? ` (${d.inbox.length})` : ''}`]);
  return (
    <div className="ph-appview">
      <AppHeader title="Jobs" />
      <div className="ph-body">
        {!d ? <div className="ph-empty">Loading…</div> : <>
          <Seg value={tab} options={tabs} onChange={setTab} />
          {tab === 'mine' && <>
            {d.primary !== 'unemployed' && (
              <div className="jb-duty">
                <div><strong>{d.jobLabel}</strong><div className="muted">{d.onduty ? 'On duty' : 'Off duty'}</div></div>
                <button className={`ph-btn${d.onduty ? ' danger' : ' primary'}`} onClick={() => void act('jobsDuty')}>{d.onduty ? 'Clock out' : 'Clock in'}</button>
              </div>
            )}
            <ul className="ph-list">
              {d.mine.map((j) => (
                <li key={j.name}><div className="ph-row static">
                  <span className="ph-row-main"><strong>{j.label}{j.primary && <span className="ph-chip on">Main</span>}</strong><span className="muted">{j.grade} · {money(j.pay)} per paycheck</span></span>
                  {!j.primary && <button className="ph-btn ghost" onClick={() => void act('jobsPrimary', j.name)}>Make main</button>}
                </div></li>
              ))}
            </ul>
            {d.mine.length === 0 && <div className="ph-empty">No jobs yet. Check the job board.</div>}
            {d.apps.length > 0 && <div className="ph-section">Your applications</div>}
            <ul className="ph-list">{d.apps.map((a) => <li key={a.id}><div className="ph-row static"><span className="ph-row-main"><strong>{d.board.find((b) => b.job === a.job)?.label ?? a.job}</strong><span className="muted">{a.status === 'sent' ? 'Sent' : a.status === 'seen' ? 'Seen' : 'Closed'} · {timeAgo(a.at)}</span></span></div></li>)}</ul>
          </>}
          {tab === 'board' && <ul className="ph-list">
            {d.board.map((b) => (
              <li key={b.job}><div className="ph-row static">
                <span className="ph-row-main"><strong>{b.label}</strong><span className="muted" style={{ whiteSpace: 'normal' }}>{b.description}</span>{b.apply && <span className="muted">{b.apply}</span>}</span>
                {b.member ? <span className="muted">Hired</span> : b.open ? <span className="muted">Walk in</span> : <button className="ph-btn" onClick={() => setApplying(b)}>Apply</button>}
              </div></li>
            ))}
          </ul>}
          {tab === 'inbox' && <>
            {d.inbox?.length === 0 && <div className="ph-empty">No open applications.</div>}
            {d.inbox?.map((a) => (
              <div key={a.id} className="jb-app">
                <div><strong>{a.name}</strong> <span className="muted">{a.number} · {timeAgo(a.at)}</span></div>
                <p>{a.message}</p>
                <button className="ph-btn ghost" onClick={() => void act('jobsAppClose', a.id)}>Close</button>
              </div>
            ))}
          </>}
        </>}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Bills (Bank 2.0)
// ---------------------------------------------------------------------------
interface BillsData {
  bills: { kind: 'invoice' | 'citation'; id: number; amount: number; label: string; at: number }[];
  standing: { id: number; to_label: string; amount: number; every_days: number; note?: string; next_at: number; failures: number }[];
  score: number;
}
export function BillsApp() {
  const { toast } = usePhone();
  const [d, setD] = useState<BillsData | null>(null);
  const [form, setForm] = useState<{ number: string; amount: string; days: string; note: string } | null>(null);
  const load = useCallback(async () => { const r = await api<BillsData>('billsData'); if (r.ok && r.data) setD(r.data); else toast(r.message ?? 'Could not load', 'error'); }, [toast]);
  useEffect(() => { void load(); }, [load]);
  const act = async (name: string, ...args: unknown[]) => { const r = await api(name, ...args); toast(r.message ?? (r.ok ? 'Done' : 'Failed'), r.ok ? undefined : 'error'); void load(); return r.ok; };

  if (form) {
    return (
      <div className="ph-appview">
        <AppHeader title="New standing order" onBack={() => setForm(null)} />
        <div className="ph-body ph-form">
          <label>To phone number<input className="ph-input" inputMode="numeric" value={form.number} onChange={(e) => setForm({ ...form, number: e.target.value })} /></label>
          <label>Amount<input className="ph-input" inputMode="numeric" value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value.replace(/\D/g, '') })} /></label>
          <label>Every (days)<input className="ph-input" inputMode="numeric" value={form.days} onChange={(e) => setForm({ ...form, days: e.target.value.replace(/\D/g, '') })} /></label>
          <label>Note<input className="ph-input" maxLength={80} value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} placeholder="Rent" /></label>
          <button className="ph-btn wide primary" onClick={async () => { if (await act('standingCreate', form.number, Number(form.amount), Number(form.days), form.note)) setForm(null); }}>Create</button>
          <div className="ph-help">Paid from your bank automatically. Three failed payments cancel it.</div>
        </div>
      </div>
    );
  }
  const band = !d ? '' : d.score >= 750 ? 'Excellent' : d.score >= 670 ? 'Good' : d.score >= 580 ? 'Fair' : 'Poor';
  return (
    <div className="ph-appview">
      <AppHeader title="Bills" />
      <div className="ph-body">
        {!d ? <div className="ph-empty">Loading…</div> : <>
          <div className="bl-score">
            <div className="bl-dial" style={{ '--p': `${((d.score - 300) / 550) * 100}%` } as React.CSSProperties}><strong>{d.score}</strong><span>{band}</span></div>
            <div className="muted">Credit score: paying bills on time raises it, unpaid bills and failed standing orders lower it.</div>
          </div>
          <div className="ph-section">Unpaid ({d.bills.length})</div>
          {d.bills.length === 0 && <div className="ph-empty">Nothing to pay.</div>}
          <ul className="ph-list">
            {d.bills.map((b) => (
              <li key={`${b.kind}${b.id}`}><div className="ph-row static">
                <span className="ph-row-main"><strong>{money(b.amount)}</strong><span className="muted">{b.label}</span><span className="muted">{timeAgo(b.at)}</span></span>
                <button className="ph-btn primary" onClick={() => void act('billPay', b.kind, b.id, 'bank')}>Pay</button>
              </div></li>
            ))}
          </ul>
          <div className="ph-section">Standing orders</div>
          <ul className="ph-list">
            {d.standing.map((s) => (
              <li key={s.id}><div className="ph-row static">
                <span className="ph-row-main"><strong>{money(s.amount)} → {s.to_label}</strong><span className="muted">Every {s.every_days} day{s.every_days === 1 ? '' : 's'}{s.note ? ` · ${s.note}` : ''}</span>
                  <span className="muted">Next {new Date(s.next_at * 1000).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}{s.failures ? ` · ${s.failures} failed` : ''}</span></span>
                <button className="ph-icon-btn" aria-label="Cancel standing order" onClick={() => void act('standingCancel', s.id)}><Icon name="close" size="0.9rem" /></button>
              </div></li>
            ))}
          </ul>
          <button className="ph-btn wide ghost" onClick={() => setForm({ number: '', amount: '', days: '7', note: '' })}><Icon name="plus" size="0.9rem" /> New standing order</button>
        </>}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Music
// ---------------------------------------------------------------------------
let stationCache: Station[] | null = null;
export async function loadStations() {
  if (stationCache) return stationCache;
  const r = await nui<Station[]>('musicStations');
  stationCache = r.ok && r.data ? r.data : [];
  setStations(stationCache);
  return stationCache;
}
export function MusicApp() {
  const { toast } = usePhone();
  const [stations, setList] = useState<Station[]>(stationCache ?? []);
  const [speaker, setSpeaker] = useState(false);
  const snap = useSyncExternalStore(music.subscribe, () => `${music.station?.id ?? ''}|${music.volume}`);
  const [playingId, vol] = snap.split('|');
  useEffect(() => { void loadStations().then(setList); }, []);
  const play = async (s: Station) => {
    music.play(s);
    if (speaker) { const r = await api('speakerPlay', s.id); if (!r.ok) toast(r.message ?? 'Speaker unavailable', 'error'); }
  };
  const stop = () => { music.stop(); if (speaker) void api('speakerStop'); };
  const toggleSpeaker = async () => {
    const on = !speaker;
    setSpeaker(on);
    if (on && music.station) { const r = await api('speakerPlay', music.station.id); toast(r.message ?? '', r.ok ? undefined : 'error'); }
    if (!on) void api('speakerStop');
  };
  return (
    <div className="ph-appview">
      <AppHeader title="Music" />
      <div className="ph-body">
        <div className="mu-now">
          <div className="mu-disc"><Icon name="mic" size="1.6rem" /></div>
          <div><strong>{stations.find((s) => s.id === playingId)?.label ?? 'Not playing'}</strong><div className="muted">{speaker ? 'Out loud: people nearby hear it' : 'Only you hear it'}</div></div>
        </div>
        <label className="mu-vol">Volume<input type="range" min={0} max={1} step={0.05} value={Number(vol)} onChange={(e) => music.setVolume(Number(e.target.value))} /></label>
        <div className="mu-ctrl">
          <button className={`ph-btn${speaker ? ' primary' : ''}`} onClick={() => void toggleSpeaker()}>Speaker {speaker ? 'on' : 'off'}</button>
          <button className="ph-btn ghost" disabled={!playingId} onClick={stop}>Stop</button>
        </div>
        <div className="ph-section">Stations</div>
        <ul className="ph-list">
          {stations.map((s) => (
            <li key={s.id}><button className={`ph-row${s.id === playingId ? ' unread' : ''}`} onClick={() => void play(s)}>
              <span className="ph-row-main"><strong>{s.label}</strong><span className="muted">{s.url ? 'Internet radio' : 'Veyl live mix'}</span></span>
              {s.id === playingId && <span className="ph-chip on">Playing</span>}
            </button></li>
          ))}
        </ul>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// News
// ---------------------------------------------------------------------------
interface Article { id: number; author: string; title: string; body: string; breaking: number; at: number }
export function NewsApp() {
  const { toast } = usePhone();
  const [d, setD] = useState<{ articles: Article[]; reporter: boolean } | null>(null);
  const [open, setOpen] = useState<Article | null>(null);
  const [write, setWrite] = useState<{ title: string; body: string; breaking: boolean } | null>(null);
  const load = useCallback(async () => { const r = await api<{ articles: Article[]; reporter: boolean }>('newsList'); if (r.ok && r.data) setD(r.data); }, []);
  useEffect(() => { void load(); }, [load]);
  if (write) {
    return (
      <div className="ph-appview">
        <AppHeader title="New story" onBack={() => setWrite(null)} />
        <div className="ph-body ph-form">
          <label>Headline<input className="ph-input" maxLength={120} value={write.title} onChange={(e) => setWrite({ ...write, title: e.target.value })} /></label>
          <label>Story<textarea className="ph-input" rows={9} maxLength={4000} value={write.body} onChange={(e) => setWrite({ ...write, body: e.target.value })} /></label>
          <label className="nw-check"><input type="checkbox" checked={write.breaking} onChange={(e) => setWrite({ ...write, breaking: e.target.checked })} /> Breaking news (alerts every phone)</label>
          <button className="ph-btn wide primary" onClick={async () => { const r = await api('newsPost', write.title, write.body, write.breaking); toast(r.message ?? '', r.ok ? undefined : 'error'); if (r.ok) { setWrite(null); void load(); } }}>Publish</button>
        </div>
      </div>
    );
  }
  if (open) {
    return (
      <div className="ph-appview">
        <AppHeader title="Weazel News" onBack={() => setOpen(null)} />
        <div className="ph-body ml-read">
          {open.breaking ? <span className="nw-flag">BREAKING</span> : null}
          <h3>{open.title}</h3>
          <div className="muted">By {open.author} · {timeAgo(open.at)}</div>
          {open.body.split(/\n+/).map((p, i) => <p key={i}>{p}</p>)}
        </div>
      </div>
    );
  }
  return (
    <div className="ph-appview">
      <AppHeader title="Weazel News" right={d?.reporter ? <button className="ph-icon-btn" aria-label="Write a story" onClick={() => setWrite({ title: '', body: '', breaking: false })}><Icon name="edit" size="1rem" /></button> : undefined} />
      <div className="ph-body">
        {!d && <div className="ph-empty">Loading…</div>}
        {d?.articles.length === 0 && <div className="ph-empty">No stories yet.</div>}
        <ul className="ph-list">
          {d?.articles.map((a) => (
            <li key={a.id}><button className="ph-row" onClick={() => setOpen(a)}>
              <span className="ph-row-main"><strong>{a.breaking ? <span className="nw-flag">BREAKING</span> : null}{a.title}</strong><span className="muted">{a.body.replace(/\s+/g, ' ').slice(0, 80)}</span><span className="muted">{a.author} · {timeAgo(a.at)}</span></span>
            </button></li>
          ))}
        </ul>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Racing
// ---------------------------------------------------------------------------
interface RaceData { tracks: { id: number; name: string; creator: string; points: number; best?: number }[]; open: { id: number; track: string; host: string; racers: number; mine: boolean; joined: boolean }[] }
const fmtMs = (ms: number) => `${Math.floor(ms / 60000)}:${((ms % 60000) / 1000).toFixed(2).padStart(5, '0')}`;
export function RacingApp() {
  const { toast } = usePhone();
  const [d, setD] = useState<RaceData | null>(null);
  const [rec, setRec] = useState<{ name: string; points: { x: number; y: number; z: number }[] } | null>(null);
  const [board, setBoard] = useState<{ track: string; rows: { name: string; ms: number }[] } | null>(null);
  const load = useCallback(async () => { const r = await api<RaceData>('raceData'); if (r.ok && r.data) setD(r.data); }, []);
  useEffect(() => { void load(); const t = window.setInterval(() => void load(), 5000); return () => window.clearInterval(t); }, [load]);
  const act = async (name: string, ...args: unknown[]) => {
    const r = await api<{ start?: { x: number; y: number } }>(name, ...args);
    toast(r.message ?? (r.ok ? 'Done' : 'Failed'), r.ok ? undefined : 'error');
    if (r.ok && r.data?.start) void nui('waypoint', { x: r.data.start.x, y: r.data.start.y });
    void load();
    return r.ok;
  };
  if (rec) {
    return (
      <div className="ph-appview">
        <AppHeader title="Record track" onBack={() => setRec(null)} />
        <div className="ph-body ph-form">
          <label>Track name<input className="ph-input" maxLength={40} value={rec.name} onChange={(e) => setRec({ ...rec, name: e.target.value })} /></label>
          <div className="muted">Drive the route and tap <strong>Add checkpoint</strong> at each point. The first one is the start line, the last is the finish.</div>
          <button className="ph-btn wide" disabled={rec.points.length >= 40} onClick={async () => { const r = await nui<{ x: number; y: number; z: number }>('raceMark'); if (r.ok && r.data) setRec({ ...rec, points: [...rec.points, r.data] }); }}><Icon name="pin" size="0.9rem" /> Add checkpoint ({rec.points.length})</button>
          {rec.points.length > 0 && <button className="ph-btn ghost" onClick={() => setRec({ ...rec, points: rec.points.slice(0, -1) })}>Undo last</button>}
          <button className="ph-btn wide primary" disabled={rec.points.length < 2 || rec.name.trim().length < 3} onClick={async () => { if (await act('raceTrackSave', rec.name, rec.points)) setRec(null); }}>Save track</button>
        </div>
      </div>
    );
  }
  if (board) {
    return (
      <div className="ph-appview">
        <AppHeader title={board.track} onBack={() => setBoard(null)} />
        <div className="ph-body">
          {board.rows.length === 0 && <div className="ph-empty">No times yet.</div>}
          <ol className="rc-board">{board.rows.map((r, i) => <li key={i}><span>{r.name}</span><strong>{fmtMs(r.ms)}</strong></li>)}</ol>
        </div>
      </div>
    );
  }
  return (
    <div className="ph-appview">
      <AppHeader title="Racing" right={<button className="ph-icon-btn" aria-label="Record a track" onClick={() => setRec({ name: '', points: [] })}><Icon name="plus" size="1rem" /></button>} />
      <div className="ph-body">
        {!d ? <div className="ph-empty">Loading…</div> : <>
          <div className="ph-section">Open races</div>
          {d.open.length === 0 && <div className="ph-empty">No races open. Host one from a track below.</div>}
          <ul className="ph-list">
            {d.open.map((r) => (
              <li key={r.id}><div className="ph-row static">
                <span className="ph-row-main"><strong>{r.track}</strong><span className="muted">Host {r.host} · {r.racers} racer{r.racers === 1 ? '' : 's'}</span></span>
                {r.mine ? <button className="ph-btn primary" onClick={() => void act('raceStart', r.id)}>Start</button>
                  : r.joined ? <span className="muted">Joined</span> : <button className="ph-btn" onClick={() => void act('raceJoin', r.id)}>Join</button>}
              </div></li>
            ))}
          </ul>
          <div className="ph-section">Tracks</div>
          {d.tracks.length === 0 && <div className="ph-empty">No tracks yet. Tap + to record one.</div>}
          <ul className="ph-list">
            {d.tracks.map((t) => (
              <li key={t.id}><div className="ph-row static">
                <span className="ph-row-main"><strong>{t.name}</strong><span className="muted">{t.points} checkpoints · by {t.creator}{t.best ? ` · record ${fmtMs(t.best)}` : ''}</span></span>
                <button className="ph-btn ghost" onClick={async () => { const r = await api<{ name: string; ms: number }[]>('raceBoard', t.id); setBoard({ track: t.name, rows: r.data ?? [] }); }}>Times</button>
                <button className="ph-btn" onClick={() => void act('raceHost', t.id)}>Host</button>
              </div></li>
            ))}
          </ul>
          <div className="ph-help">Join within 60 m of the start line. Type /quitrace to leave a race.</div>
        </>}
      </div>
    </div>
  );
}
