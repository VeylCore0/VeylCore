import { useCallback, useEffect, useState } from 'react';
import { api, Btn, Card, Empty, Ico, uptime, type Overview } from './kit';

type Say = (ok: boolean, text: string) => void;

export function Reports({ say, onChange }: { say: Say; onChange: () => void }) {
  const [rows, setRows] = useState<{ id: number; name: string; message: string; status: string; handler?: string; at: string }[] | null>(null);
  const load = useCallback(async () => { const r = await api<typeof rows>('reports'); if (r.ok && r.data) setRows(r.data); }, []);
  useEffect(() => { void load(); }, [load]);
  if (!rows) return <Empty text="Loading reports…" />;
  return (
    <div className="ad-pane">
      {rows.length === 0 && <Empty text="No reports. Quiet city." />}
      {rows.map((r) => (
        <Card key={r.id} title={`#${r.id} · ${r.name}`} right={r.status === 'open' ? <Btn kind="primary" onClick={async () => { const x = await api('closeReport', r.id); say(x.ok, x.message ?? 'Done'); void load(); onChange(); }}><Ico name="check" size={14} />Close</Btn> : <small className="ad-dim">closed by {r.handler ?? '?'}</small>}>
          <p className="ad-msg">{r.message}</p><small className="ad-dim">{r.at}</small>
        </Card>
      ))}
    </div>
  );
}

export function Bans({ say, onChange }: { say: Say; onChange: () => void }) {
  const [rows, setRows] = useState<{ id: number; name: string; reason: string; bannedBy: string; at: string; expires: string | null }[] | null>(null);
  const load = useCallback(async () => { const r = await api<typeof rows>('bans'); if (r.ok && r.data) setRows(r.data); }, []);
  useEffect(() => { void load(); }, [load]);
  if (!rows) return <Empty text="Loading bans…" />;
  return (
    <div className="ad-pane">
      {rows.length === 0 && <Empty text="Nobody is banned." />}
      {rows.map((b) => (
        <Card key={b.id} title={`#${b.id} · ${b.name}`} right={<Btn kind="danger" onClick={async () => { const x = await api('unban', b.id); say(x.ok, x.message ?? 'Done'); void load(); onChange(); }}>Unban</Btn>}>
          <p className="ad-msg">{b.reason}</p><small className="ad-dim">by {b.bannedBy} · {b.at} · {b.expires ? `until ${b.expires}` : 'permanent'}</small>
        </Card>
      ))}
    </div>
  );
}

export function Logs() {
  const [rows, setRows] = useState<{ id: number; resource: string; action: string; citizenid?: string; data?: string; at: string }[] | null>(null);
  const [q, setQ] = useState('');
  const load = useCallback(async (f?: string) => { const r = await api<typeof rows>('logs', f || undefined); if (r.ok && r.data) setRows(r.data); }, []);
  useEffect(() => { void load(); }, [load]);
  return (
    <div className="ad-pane">
      <form className="ad-search wide" onSubmit={(e) => { e.preventDefault(); void load(q.trim()); }}>
        <Ico name="search" size={16} /><input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Filter by action, resource or citizen id, then Enter" aria-label="Filter logs" />
        <Btn onClick={() => void load(q.trim())}>Search</Btn>
      </form>
      {!rows && <Empty text="Loading the log…" />}
      {rows && rows.length === 0 && <Empty text="No entries match." />}
      {rows && rows.length > 0 && (
        <table className="ad-table">
          <thead><tr><th>Time</th><th>Resource</th><th>Action</th><th>Citizen</th><th>Data</th></tr></thead>
          <tbody>{rows.map((r) => <tr key={r.id}><td>{r.at}</td><td>{r.resource}</td><td><b>{r.action}</b></td><td className="mono">{r.citizenid ?? ''}</td><td className="mono ad-data">{r.data ?? ''}</td></tr>)}</tbody>
        </table>
      )}
    </div>
  );
}

export function Server({ ov, say }: { ov: Overview; say: Say }) {
  const [rows, setRows] = useState<{ name: string; state: string; locked: boolean }[] | null>(null);
  const [q, setQ] = useState('');
  const load = useCallback(async () => { const r = await api<typeof rows>('resources'); if (r.ok && r.data) setRows(r.data); }, []);
  useEffect(() => { void load(); }, [load]);
  const shown = (rows ?? []).filter((r) => !q.trim() || r.name.includes(q.trim().toLowerCase()));
  const run = async (action: string, name: string) => { const r = await api('resource', action, name); say(r.ok, r.message ?? (r.ok ? 'Done' : 'That did not work')); window.setTimeout(() => void load(), 900); };
  return (
    <div className="ad-pane">
      <div className="ad-tiles">
        <div><small>UPTIME</small><b>{uptime(ov.uptime)}</b></div><div><small>PLAYERS</small><b>{ov.players}/{ov.max}</b></div>
        <div><small>RESOURCES UP</small><b>{ov.resources}</b></div><div><small>OPEN REPORTS</small><b>{ov.reports}</b></div>
      </div>
      <label className="ad-search wide"><Ico name="search" size={16} /><input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Find a resource" aria-label="Find a resource" /></label>
      {!rows && <Empty text="Loading resources…" />}
      <div className="ad-res">
        {shown.map((r) => (
          <div key={r.name} className="ad-resrow">
            <i className={r.state === 'started' ? 'up' : 'down'} title={r.state} /><b>{r.name}</b><small>{r.state}</small>
            <span>
              <Btn onClick={() => void run('restart', r.name)} disabled={r.locked} title={r.locked ? 'Protected' : 'Restart'}>Restart</Btn>
              {r.state === 'started' ? <Btn kind="danger" onClick={() => void run('stop', r.name)} disabled={r.locked}>Stop</Btn> : <Btn kind="primary" onClick={() => void run('start', r.name)}>Start</Btn>}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
