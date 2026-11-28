import { useCallback, useEffect, useMemo, useState } from 'react';
import { api, Btn, Card, cx, Empty, Form, Ico, usd, type Overview, type PlayerInfo, type PlayerRow } from './kit';

type Say = (ok: boolean, text: string) => void;

export function Players({ ov, say, items }: { ov: Overview; say: Say; items: { name: string; label: string }[] }) {
  const [rows, setRows] = useState<PlayerRow[] | null>(null);
  const [q, setQ] = useState('');
  const [sel, setSel] = useState<number | null>(null);

  const load = useCallback(async () => { const r = await api<PlayerRow[]>('players'); if (r.ok && r.data) setRows(r.data); }, []);
  useEffect(() => { void load(); const t = window.setInterval(() => void load(), 6000); return () => window.clearInterval(t); }, [load]);

  const shown = useMemo(() => {
    const s = q.trim().toLowerCase();
    return (rows ?? []).filter((p) => !s || `${p.id} ${p.name} ${p.character ?? ''} ${p.citizenid ?? ''} ${p.job ?? ''}`.toLowerCase().includes(s));
  }, [rows, q]);

  return (
    <div className="ad-split">
      <div className="ad-list">
        <label className="ad-search"><Ico name="search" size={16} /><input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search id, name, character, job" aria-label="Search players" /></label>
        <div className="ad-rows" role="list">
          {rows === null && <Empty text="Loading players…" />}
          {shown.map((p) => (
            <button key={p.id} role="listitem" className={cx('ad-prow', sel === p.id && 'on')} onClick={() => setSel(p.id)}>
              <b className="ad-id">{p.id}</b>
              <span><strong>{p.character || p.name}{p.staff && <em className="ad-tag">STAFF</em>}</strong><small>{p.name}{p.job ? ` · ${p.job}` : ''}</small></span>
              <i className={cx('ad-ping', p.ping > 150 ? 'bad' : p.ping > 80 ? 'mid' : '')}>{p.ping}ms</i>
            </button>
          ))}
          {rows !== null && shown.length === 0 && <Empty text="Nobody matches." />}
        </div>
      </div>
      <div className="ad-detail">
        {sel === null ? <Empty text="Pick a player to see their details and act on them." /> : <Detail key={sel} id={sel} ov={ov} say={say} items={items} onGone={() => { setSel(null); void load(); }} />}
      </div>
    </div>
  );
}

function Detail({ id, ov, say, items, onGone }: { id: number; ov: Overview; say: Say; items: { name: string; label: string }[]; onGone: () => void }) {
  const [p, setP] = useState<PlayerInfo | null>(null);
  const [gone, setGone] = useState(false);
  const [tab, setTab] = useState<'act' | 'econ' | 'inv'>('act');
  const [frozen, setFrozen] = useState(false);

  const load = useCallback(async () => {
    const r = await api<PlayerInfo>('playerInfo', id);
    if (r.ok && r.data) setP(r.data); else setGone(true);
  }, [id]);
  useEffect(() => { void load(); }, [load]);

  const act = async (kind: string, data?: Record<string, unknown>, reload = false): Promise<boolean> => {
    const r = await api('action', kind, id, data ?? {});
    say(r.ok, r.message ?? (r.ok ? 'Done' : 'That did not work'));
    if (r.ok && (reload || kind === 'kick' || kind === 'ban')) { if (kind === 'kick' || kind === 'ban') onGone(); else void load(); }
    return r.ok;
  };

  if (gone) return <Empty text="That player left." />;
  if (!p) return <Empty text="Loading…" />;
  const money = p.money ?? {};
  return (
    <>
      <header className="ad-dhead">
        <span className="ad-avatar">{(p.character || p.name).slice(0, 1).toUpperCase()}</span>
        <div><h2>{p.character || p.name}</h2><small>#{p.id} · {p.name}{p.citizenid ? ` · ${p.citizenid}` : ''}{p.staff ? ' · staff' : ''}</small></div>
        <div className="ad-stats"><span title="Health">♥ {p.health ?? '–'}</span><span title="Armour">⛨ {p.armor ?? 0}</span><span title="Ping">{p.ping}ms</span></div>
      </header>

      <div className="ad-quick">
        <Btn onClick={() => void act('teleport')}><Ico name="pin" size={15} />Go to</Btn>
        <Btn onClick={() => void act('bring')}>Bring</Btn>
        <Btn onClick={() => void act('spectate')}><Ico name="eye" size={15} />Spectate</Btn>
        <Btn onClick={() => { const n = !frozen; void act('freeze', { on: n }).then((ok) => ok && setFrozen(n)); }}>{frozen ? 'Unfreeze' : 'Freeze'}</Btn>
        <Btn kind="primary" onClick={() => void act('revive')}>Revive</Btn>
        <Btn onClick={() => void act('heal')}>Heal</Btn>
        <Btn kind="danger" onClick={() => void act('kill')}>Kill</Btn>
      </div>

      <div className="ad-tabs" role="tablist">
        {([['act', 'Discipline'], ['econ', 'Money & job'], ['inv', 'Inventory']] as const).map(([k, l]) => <button key={k} role="tab" aria-selected={tab === k} className={cx(tab === k && 'on')} onClick={() => setTab(k)}>{l}</button>)}
      </div>

      {tab === 'act' && (
        <>
          <Card title="Message"><Form fields={[{ key: 'text', label: 'Shown on their screen', wide: true, placeholder: 'What should they know?' }]} action="Send" onSubmit={(v) => act('message', { text: v.text })} /></Card>
          <Card title="Warn"><Form fields={[{ key: 'reason', label: 'Reason', wide: true, placeholder: 'Recorded on their file' }]} action="Warn" onSubmit={(v) => act('warn', { reason: v.reason }, true)} /></Card>
          <Card title="Kick"><Form fields={[{ key: 'reason', label: 'Reason', wide: true }]} action="Kick" kind="danger" onSubmit={(v) => act('kick', { reason: v.reason })} /></Card>
          <Card title="Ban"><Form fields={[{ key: 'reason', label: 'Reason', wide: true }, { key: 'hours', label: 'Hours (0 = permanent)', type: 'number', init: '24' }]} action="Ban" kind="danger" onSubmit={(v) => act('ban', { reason: v.reason, hours: Number(v.hours) })} /></Card>
          <Card title={`Warnings (${p.warnings.length})`}>
            {p.warnings.length === 0 ? <Empty text="A clean record." /> : <ul className="ad-lines">{p.warnings.map((w) => <li key={w.id}><b>{w.reason}</b><small>{w.issued_by} · {w.at}</small></li>)}</ul>}
          </Card>
          <Card title="Identifiers"><ul className="ad-lines">{Object.entries(p.identifiers).filter(([, v]) => v).map(([k, v]) => <li key={k}><b>{k}</b><small className="mono">{v}</small></li>)}</ul></Card>
        </>
      )}

      {tab === 'econ' && (
        <>
          <Card title="Wallet"><div className="ad-money">{(['cash', 'bank', 'crypto'] as const).map((k) => <div key={k}><small>{k.toUpperCase()}</small><b>{usd(money[k] ?? 0)}</b></div>)}</div></Card>
          <Card title="Give money"><Form fields={[{ key: 'kind', label: 'Account', type: 'select', options: ['cash', 'bank', 'crypto'].map((x) => ({ value: x, label: x })) }, { key: 'amount', label: 'Amount', type: 'number' }, { key: 'reason', label: 'Reason', wide: true }]} action="Give" onSubmit={(v) => act('money', { kind: v.kind, amount: Number(v.amount), reason: v.reason }, true)} /></Card>
          <Card title="Take money"><Form fields={[{ key: 'kind', label: 'Account', type: 'select', options: ['cash', 'bank', 'crypto'].map((x) => ({ value: x, label: x })) }, { key: 'amount', label: 'Amount', type: 'number' }, { key: 'reason', label: 'Reason', wide: true }]} action="Take" kind="danger" onSubmit={(v) => act('money', { kind: v.kind, amount: Number(v.amount), reason: v.reason, take: true }, true)} /></Card>
          <Card title={`Job: ${p.job?.label ?? p.job?.name ?? 'none'}`}><Form fields={[{ key: 'job', label: 'Job', type: 'select', options: ov.jobs.map((j) => ({ value: j.id, label: j.label })) }, { key: 'grade', label: 'Grade', type: 'number', init: '0' }]} action="Set job" onSubmit={(v) => act('job', { job: v.job, grade: Number(v.grade) }, true)} /></Card>
          <Card title={`Gang: ${p.gang?.label ?? p.gang?.name ?? 'none'}`}><Form fields={[{ key: 'gang', label: 'Gang', type: 'select', options: ov.gangs.map((j) => ({ value: j.id, label: j.label })) }, { key: 'grade', label: 'Grade', type: 'number', init: '0' }]} action="Set gang" onSubmit={(v) => act('gang', { gang: v.gang, grade: Number(v.grade) }, true)} /></Card>
        </>
      )}

      {tab === 'inv' && (
        <>
          <Card title="Give or take an item">
            <datalist id="ad-items">{items.map((i) => <option key={i.name} value={i.name}>{i.label}</option>)}</datalist>
            <form className="ad-form" onSubmit={(e) => { e.preventDefault(); }}>
              <ItemTool act={act} />
            </form>
          </Card>
          <Card title={`Carrying (${p.items.length})`}>
            {p.items.length === 0 ? <Empty text="Empty pockets." /> : <ul className="ad-lines">{p.items.map((i, k) => <li key={i.name + k}><b>{i.label ?? i.name}</b><small>×{i.count} · {i.name}</small></li>)}</ul>}
          </Card>
        </>
      )}
      <small className="ad-foot">{ov.me.name} is acting as staff. Every action here is written to the audit log.</small>
    </>
  );
}

function ItemTool({ act }: { act: (k: string, d?: Record<string, unknown>, r?: boolean) => Promise<boolean> }) {
  const [item, setItem] = useState('');
  const [count, setCount] = useState('1');
  return (
    <>
      <label className="wide"><span>Item name</span><input list="ad-items" value={item} onChange={(e) => setItem(e.target.value)} placeholder="Start typing: lockpick, weapon_pistol…" /></label>
      <label><span>Amount</span><input type="number" min={1} value={count} onChange={(e) => setCount(e.target.value)} /></label>
      <Btn kind="primary" onClick={() => void act('giveitem', { item, count: Number(count) }, true)}>Give</Btn>
      <Btn kind="danger" onClick={() => void act('takeitem', { item, count: Number(count) }, true)}>Take</Btn>
    </>
  );
}
