import { useCallback, useEffect, useRef, useState } from 'react';
import { announceReady, nui, useNuiMessage } from '@veyl/ui';
import { api, Btn, Card, cx, Form, Ico, tool, Toggle, uptime, type Overview, type SelfState } from './kit';
import { Players } from './Players';
import { Bans, Logs, Reports, Server } from './Lists';

type Tab = 'home' | 'players' | 'self' | 'vehicles' | 'world' | 'reports' | 'bans' | 'logs' | 'server';
const NAV: { id: Tab; label: string; icon: string }[] = [
  { id: 'home', label: 'Dashboard', icon: 'home' }, { id: 'players', label: 'Players', icon: 'users' }, { id: 'self', label: 'Self tools', icon: 'user' },
  { id: 'vehicles', label: 'Vehicles', icon: 'car' }, { id: 'world', label: 'World', icon: 'globe' }, { id: 'reports', label: 'Reports', icon: 'flag' },
  { id: 'bans', label: 'Bans', icon: 'ban' }, { id: 'logs', label: 'Audit log', icon: 'log' }, { id: 'server', label: 'Server', icon: 'server' },
];

interface Open { overview: Overview; self: SelfState; vehicles: string[]; speeds: number[] }

export function App() {
  const [open, setOpen] = useState<Open | null>(null);
  const [tab, setTab] = useState<Tab>('home');
  const [toast, setToast] = useState<{ ok: boolean; text: string } | null>(null);
  const [items, setItems] = useState<{ name: string; label: string }[]>([]);
  const timer = useRef<number>();
  useEffect(() => announceReady(), []);

  useNuiMessage<Open>('admin:open', (d) => { setOpen(d); setTab('home'); setToast(null); });
  useNuiMessage('admin:close', () => setOpen(null));

  const close = useCallback(() => { void nui('close'); }, []);
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape' && !(e.target instanceof HTMLInputElement && e.target.value)) close(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, close]);

  // The item list is long: fetch it once when the menu opens.
  useEffect(() => { if (open) void api<{ name: string; label: string }[]>('itemList').then((r) => { if (r.ok && r.data) setItems(r.data); }); }, [open]);

  const say = useCallback((ok: boolean, text: string) => {
    setToast({ ok, text });
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setToast(null), 3400);
  }, []);

  const refresh = useCallback(async () => {
    const r = await api<Overview>('overview');
    if (r.ok && r.data) setOpen((o) => (o ? { ...o, overview: r.data as Overview } : o));
  }, []);

  if (!open) return null;
  const ov = open.overview;
  return (
    <div className="ad-root">
      <div className="ad-shell" role="application" aria-label="Staff menu">
        <nav className="ad-nav" aria-label="Sections">
          <div className="ad-brand"><span>V</span><div><b>VEYL</b><i>STAFF MENU</i></div></div>
          {NAV.map((n) => (
            <button key={n.id} className={cx('ad-navbtn', tab === n.id && 'on')} onClick={() => setTab(n.id)} aria-current={tab === n.id ? 'page' : undefined}>
              <Ico name={n.icon} size={17} />{n.label}
              {n.id === 'reports' && ov.reports > 0 && <em>{ov.reports}</em>}
            </button>
          ))}
          <div className="ad-me"><span>{ov.me.name.slice(0, 1).toUpperCase()}</span><div><strong>{ov.me.name}</strong><small>id {ov.me.id} · staff</small></div></div>
        </nav>
        <main className="ad-main">
          <header className="ad-top">
            <h1>{NAV.find((n) => n.id === tab)?.label}</h1>
            <button className="ad-close" onClick={close}><kbd>ESC</kbd>Close</button>
          </header>
          <div className="ad-body">
            {tab === 'home' && <Home ov={ov} say={say} go={setTab} />}
            {tab === 'players' && <Players ov={ov} say={say} items={items} />}
            {tab === 'self' && <SelfTools state={open.self} speeds={open.speeds} say={say} set={(s) => setOpen({ ...open, self: s })} />}
            {tab === 'vehicles' && <Vehicles quick={open.vehicles} say={say} />}
            {tab === 'world' && <World ov={ov} say={say} onChange={() => void refresh()} />}
            {tab === 'reports' && <Reports say={say} onChange={() => void refresh()} />}
            {tab === 'bans' && <Bans say={say} onChange={() => void refresh()} />}
            {tab === 'logs' && <Logs />}
            {tab === 'server' && <Server ov={ov} say={say} />}
          </div>
        </main>
        {toast && <div className={cx('ad-toast', !toast.ok && 'err')} role="status"><Ico name={toast.ok ? 'check' : 'alert'} size={16} />{toast.text}</div>}
      </div>
    </div>
  );
}

function Home({ ov, say, go }: { ov: Overview; say: (ok: boolean, t: string) => void; go: (t: Tab) => void }) {
  const w = ov.world;
  return (
    <div className="ad-pane">
      <div className="ad-tiles">
        <button onClick={() => go('players')}><small>PLAYERS ONLINE</small><b>{ov.players}<em>/{ov.max}</em></b><i>{ov.inCity} in the city</i></button>
        <button onClick={() => go('reports')}><small>OPEN REPORTS</small><b className={cx(ov.reports > 0 && 'warn')}>{ov.reports}</b><i>{ov.reports > 0 ? 'Need an answer' : 'All clear'}</i></button>
        <button onClick={() => go('bans')}><small>ACTIVE BANS</small><b>{ov.bans}</b><i>manage</i></button>
        <button onClick={() => go('server')}><small>UPTIME</small><b>{uptime(ov.uptime)}</b><i>{ov.resources} resources up</i></button>
      </div>
      <Card title="World now"><div className="ad-world"><b>{w.hour !== undefined ? `${String(w.hour).padStart(2, '0')}:${String(w.minute ?? 0).padStart(2, '0')}` : '–'}</b><span>{w.weather ?? 'unknown'}{w.frozen ? ' · frozen' : ''}</span><Btn onClick={() => go('world')}>Change</Btn></div></Card>
      <Card title="Announce to everyone" right={<Ico name="megaphone" size={17} />}>
        <Form fields={[{ key: 'text', label: 'Message', wide: true, placeholder: 'Restart in 10 minutes…' }]} action="Send" onSubmit={async (v) => { const r = await api('announce', v.text); say(r.ok, r.message ?? (r.ok ? 'Sent' : 'That did not work')); return r.ok; }} />
      </Card>
      <Card title="Shortcuts">
        <div className="ad-quick">
          <Btn onClick={() => go('players')}><Ico name="users" size={15} />Find a player</Btn>
          <Btn onClick={() => go('self')}><Ico name="bolt" size={15} />Noclip</Btn>
          <Btn onClick={() => go('vehicles')}><Ico name="car" size={15} />Spawn a car</Btn>
          <Btn onClick={() => go('logs')}><Ico name="log" size={15} />Audit log</Btn>
        </div>
      </Card>
    </div>
  );
}

function SelfTools({ state, speeds, say, set }: { state: SelfState; speeds: number[]; say: (ok: boolean, t: string) => void; set: (s: SelfState) => void }) {
  const run = async (kind: string, value?: unknown) => {
    const r = await tool(kind, value);
    if (r.data?.state) set(r.data.state);
    if (r.data?.copy) try { await navigator.clipboard.writeText(r.data.copy); } catch { /* the console has it */ }
    if (r.message) say(r.ok, r.message); else if (!r.ok) say(false, 'That did not work');
  };
  return (
    <div className="ad-pane">
      <Card title="Toggles">
        <div className="ad-toggles">
          <Toggle on={state.noclip} label="Noclip" hint="Fly through the world. Closes this menu." onClick={() => void run('noclip')} />
          <Toggle on={state.god} label="God mode" hint="No damage" onClick={() => void run('god')} />
          <Toggle on={state.invisible} label="Invisible" hint="Others cannot see you" onClick={() => void run('invisible')} />
          <Toggle on={state.names} label="Player names" hint="Ids and names over heads" onClick={() => void run('names')} />
        </div>
      </Card>
      <Card title="Noclip speed">
        <div className="ad-chips">{speeds.map((s, i) => <button key={s} className={cx('ad-chip', state.speed === i + 1 && 'on')} onClick={() => void run('speed', i + 1)}>×{s}</button>)}</div>
        <small className="ad-dim">In noclip: WASD fly · Shift faster · Ctrl slower · Q up · E down.</small>
      </Card>
      <Card title="Quick actions">
        <div className="ad-quick">
          <Btn kind="primary" onClick={() => void run('heal')}>Heal me</Btn>
          <Btn onClick={() => void run('armor')}>Full armour</Btn>
          <Btn onClick={() => void run('tpm')}><Ico name="pin" size={15} />Teleport to waypoint</Btn>
          <Btn onClick={() => void run('coords')}>Copy my coordinates</Btn>
        </div>
      </Card>
    </div>
  );
}

function Vehicles({ quick, say }: { quick: string[]; say: (ok: boolean, t: string) => void }) {
  const run = async (kind: string, value?: unknown, extra?: unknown) => { const r = await tool(kind, value, extra); say(r.ok, r.message ?? (r.ok ? 'Done' : 'That did not work')); return r.ok; };
  return (
    <div className="ad-pane">
      <Card title="Spawn a vehicle">
        <Form fields={[{ key: 'model', label: 'Model name', placeholder: 'adder', wide: true }, { key: 'plate', label: 'Plate (optional)', placeholder: 'STAFF' }]} action="Spawn" onSubmit={(v) => run('spawn', v.model.trim(), v.plate.trim())} />
        <div className="ad-chips">{quick.map((m) => <button key={m} className="ad-chip" onClick={() => void run('spawn', m)}>{m}</button>)}</div>
        <small className="ad-dim">Spawned cars are temporary and not owned by anyone. Your current vehicle is replaced.</small>
      </Card>
      <Card title="The vehicle you are in or next to">
        <div className="ad-quick">
          <Btn kind="primary" onClick={() => void run('fix')}>Repair</Btn>
          <Btn onClick={() => void run('clean')}>Clean</Btn>
          <Btn onClick={() => void run('flip')}>Flip upright</Btn>
          <Btn kind="danger" onClick={() => void run('delete')}>Delete</Btn>
        </div>
      </Card>
    </div>
  );
}

function World({ ov, say, onChange }: { ov: Overview; say: (ok: boolean, t: string) => void; onChange: () => void }) {
  const run = async (kind: string, a?: unknown, b?: unknown) => { const r = await api('world', kind, a, b); say(r.ok, r.message ?? (r.ok ? 'Done' : 'That did not work')); onChange(); return r.ok; };
  return (
    <div className="ad-pane">
      <Card title={`Weather: ${ov.world.weather ?? 'unknown'}`}>
        <div className="ad-chips">{ov.weather.map((w) => <button key={w} className={cx('ad-chip', ov.world.weather === w && 'on')} onClick={() => void run('weather', w)}>{w.toLowerCase()}</button>)}</div>
      </Card>
      <Card title="Time of day">
        <div className="ad-chips">
          {[['Dawn', 6], ['Morning', 9], ['Noon', 12], ['Evening', 18], ['Night', 22], ['Midnight', 0]].map(([l, h]) => <button key={l} className="ad-chip" onClick={() => void run('time', h, 0)}>{l}</button>)}
        </div>
        <Form fields={[{ key: 'h', label: 'Hour (0–23)', type: 'number', init: '12' }, { key: 'm', label: 'Minute', type: 'number', init: '0' }]} action="Set time" onSubmit={(v) => run('time', Number(v.h), Number(v.m))} />
        <Btn onClick={() => void run('freeze')}>{ov.world.frozen ? 'Resume time and weather' : 'Freeze time and weather'}</Btn>
      </Card>
      <Card title="Clean up"><Btn onClick={() => void run('clear')}>Remove abandoned vehicles near me</Btn><small className="ad-dim">Never touches owned, dealer or job vehicles.</small></Card>
    </div>
  );
}
