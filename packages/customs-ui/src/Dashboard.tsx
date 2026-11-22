import { useCallback, useMemo, useState } from 'react';
import { Icon, nui } from '@veyl/ui';
import { api, money, STATUS, type Line } from './lib';
import type { Toast } from './App';

interface Order { id: number; model: string; plate: string; customer: string; customerCid: string; mechanic?: string; mechanicCid?: string; bay?: string; kind: string; status: string;
  version: number; note?: string; subtotal: number; labor: number; tax: number; total: number; paid: number; refunded: number; lines: Line[] }
interface Data {
  shop: { id: string; label: string; sub?: string; stock: boolean; business?: string };
  me: { cid: string; name: string; onduty: boolean; manager: boolean };
  metrics: { active: number; freeBays: number; totalBays: number; revenueToday: number };
  orders: Order[]; bays: { id: string; state: string; orderId?: number; plate?: string }[];
  parts: { part: string; label: string; qty: number; reserved: number; reorderAt: number; cost: number; delivery: number; incoming: number }[];
  partOrders: { id: number; part: string; qty: number; cost: number; ordered_by: string; status: string; arrives: number }[];
  team: { cid: string; name: string; grade: string; onduty: boolean; active: number }[];
  history: { id: number; model: string; plate: string; customer_name: string; mechanic_name?: string; kind: string; status: string; total: number; paid: number; refunded: number; at: number }[];
  log: { order_id?: number; actor: string; action: string; detail?: string; at: number }[];
  pricing: { multiplier: number; laborRate: number };
}
type Section = 'overview' | 'orders' | 'bays' | 'parts' | 'team' | 'history';
const NAV: [Section, string, string][] = [['overview', 'Overview', 'home'], ['orders', 'Work orders', 'receipt'], ['bays', 'Service bays', 'garage'], ['parts', 'Parts', 'box'], ['team', 'Team', 'users'], ['history', 'History', 'clock']];
const FILTERS: [string, string, (o: Order) => boolean][] = [
  ['all', 'All', () => true], ['draft', 'Drafts', (o) => o.status === 'draft'], ['sent', 'Awaiting approval', (o) => o.status === 'sent'],
  ['queued', 'Approved', (o) => o.status === 'approved'], ['progress', 'In progress', (o) => o.status === 'in_progress'],
];
const imageBase = 'nui://veyl_vehicles/web/images';
const services = (o: Order) => { const cats = [...new Set(o.lines.map((l) => l.cat))]; return cats.length ? cats.map((c) => (c ?? '')[0]?.toUpperCase() + (c ?? '').slice(1)).join(' & ') : o.note || 'Request'; };
const when = (t: number) => new Date(t * 1000).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });

function Thumb({ model }: { model: string }) {
  const [bad, setBad] = useState(false);
  return <span className="thumb">{!bad && /^[a-z0-9_]+$/i.test(model) ? <img src={`${imageBase}/${model.toLowerCase()}.webp`} alt="" onError={() => setBad(true)} /> : <Icon name="car" size="1.4em" />}</span>;
}
const Status = ({ s }: { s: string }) => <span className={`status ${STATUS[s]?.tone ?? 'muted'}`}>{STATUS[s]?.label ?? s}</span>;

export function Dashboard({ initial, shopId, say, close }: { initial: Data; shopId: string; say: Toast; close: () => void }) {
  const [d, setD] = useState<Data>(initial);
  const [section, setSection] = useState<Section>('orders');
  const [filter, setFilter] = useState('all');
  const [q, setQ] = useState('');
  const [sel, setSel] = useState<number | null>(initial.orders[0]?.id ?? null);
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(async () => { const r = await api<Data>('dashboard', shopId); if (r.ok && r.data) setD(r.data); }, [shopId]);
  const run = async (name: string, ...args: unknown[]) => {
    setBusy(true);
    const r = await api(name, ...args);
    setBusy(false);
    say(r.message ?? (r.ok ? 'Done' : 'Failed'), !r.ok);
    void refresh();
    return r.ok;
  };
  const order = d.orders.find((o) => o.id === sel) ?? null;
  const rows = useMemo(() => {
    const f = FILTERS.find((x) => x[0] === filter)?.[2] ?? (() => true);
    const s = q.trim().toLowerCase();
    return d.orders.filter((o) => f(o) && (!s || `${o.model} ${o.plate} ${o.customer} ${o.mechanic ?? ''} ${o.id}`.toLowerCase().includes(s)));
  }, [d.orders, filter, q]);
  const activeOrders = d.orders.filter((o) => ['draft', 'sent', 'approved', 'in_progress'].includes(o.status));

  return (
    <div className="dash-wrap" onKeyDown={(e) => { if (e.key === 'Escape') close(); }}>
      <div className="dash" role="dialog" aria-label="Workshop dashboard">
        <header className="dash-head">
          <div><div className="wordmark"><b>VEYL</b><i>/</i><span>CUSTOMS</span></div><div className="shop">{d.shop.label}{d.shop.sub ? ` · ${d.shop.sub}` : ''}</div></div>
          <span className="spacer" style={{ flex: 1 }} />
          <div className="who"><span className="avatar" aria-hidden>{d.me.name.split(' ').map((w) => w[0]).join('').slice(0, 2)}</span>
            <span>{d.me.name}</span><span className={`status ${d.me.onduty ? 'ok' : 'muted'}`}>{d.me.onduty ? 'On duty' : 'Off duty'}</span></div>
          <button className="iconbtn" aria-label="Close" onClick={close}><Icon name="close" size="1.1em" /></button>
        </header>
        <div className="dash-body" style={{ gridTemplateColumns: order && (section === 'orders' || section === 'overview') ? '15em 1fr auto' : '15em 1fr' }}>
          <nav className="nav">{NAV.map(([id, label, icon]) => <button key={id} className={section === id ? 'on' : ''} aria-current={section === id} onClick={() => setSection(id)}><Icon name={icon} size="1.15em" /> {label}</button>)}</nav>
          <main className="main">
            {(section === 'overview' || section === 'orders') && <>
              <h1>{section === 'overview' ? 'Overview' : 'Work orders'}</h1>
              <div className="lead">{section === 'overview' ? 'Today in the workshop' : 'Manage your workshop'}</div>
              <div className="metrics">
                <span className="metric"><b>{d.metrics.active}</b> Active jobs</span><span className="sep" />
                <span className="metric"><b>{d.metrics.freeBays}</b> Available bay{d.metrics.freeBays === 1 ? '' : 's'} of {d.metrics.totalBays}</span><span className="sep" />
                <span className="metric" title="Money kept by the shop for orders completed since midnight (server time)"><b>{money(d.metrics.revenueToday)}</b> Revenue today</span>
              </div>
              <div className="toolbar">
                <label className="search"><Icon name="search" size="1em" /><input placeholder="Search work orders…" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Search work orders" /></label>
                <div className="chips">{FILTERS.map(([id, label, f]) => <button key={id} className={`chip${filter === id ? ' on' : ''}`} onClick={() => setFilter(id)}>{label} {d.orders.filter(f).length}</button>)}</div>
                <span style={{ flex: 1 }} />
                {d.me.onduty && <button className="btn small" onClick={() => void nui('editOrder', { shop: shopId })}><Icon name="plus" size="0.9em" /> New quote</button>}
              </div>
              <table>
                <thead><tr><th>VEHICLE</th><th>SERVICE</th><th>BAY</th><th>MECHANIC</th><th>STATUS</th></tr></thead>
                <tbody>
                  {(section === 'overview' ? activeOrders : rows).map((o) => (
                    <tr key={o.id} className={`click${sel === o.id ? ' sel' : ''}`} onClick={() => setSel(o.id)} tabIndex={0} onKeyDown={(e) => { if (e.key === 'Enter') setSel(o.id); }}>
                      <td><div className="veh"><Thumb model={o.model} /><div>{o.model.toUpperCase()}<small>{o.plate} · #{o.id}</small></div></div></td>
                      <td>{services(o)}</td><td>{o.bay ?? '—'}</td><td>{o.mechanic ?? <span className="status muted">Unassigned</span>}</td><td><Status s={o.status} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
              {!(section === 'overview' ? activeOrders : rows).length && <div className="empty">No work orders here.</div>}
              {section === 'overview' && <BayStrip d={d} />}
            </>}
            {section === 'bays' && <><h1>Service bays</h1><div className="lead">Occupancy comes from approved and in-progress orders.</div><BayStrip d={d} big /></>}
            {section === 'parts' && <Parts d={d} run={run} shopId={shopId} />}
            {section === 'team' && <Team d={d} run={run} shopId={shopId} sel={order} />}
            {section === 'history' && <History d={d} />}
          </main>
          {order && (section === 'orders' || section === 'overview') && <QuotePane o={order} d={d} busy={busy} run={run} shopId={shopId} />}
        </div>
      </div>
    </div>
  );
}

function BayStrip({ d, big }: { d: Data; big?: boolean }) {
  return (
    <>
      {!big && <div className="section-title">Service bays</div>}
      {d.bays.length === 0 && <div className="empty">This shop has no service bays configured.</div>}
      <div className="bays" style={big ? { flexDirection: 'column', gap: 12 } : undefined}>
        {d.bays.map((b) => (
          <div key={b.id} className="bay"><b>{b.id}</b>
            <span className={`status ${b.state === 'occupied' ? 'ok' : b.state === 'reserved' ? 'warn' : 'muted'}`}>{b.state === 'occupied' ? 'Occupied' : b.state === 'reserved' ? 'Reserved' : 'Available'}</span>
            {b.plate && <span style={{ color: 'var(--muted)' }}>#{b.orderId} · {b.plate}</span>}</div>
        ))}
      </div>
    </>
  );
}

function QuotePane({ o, d, busy, run, shopId }: { o: Order; d: Data; busy: boolean; run: (n: string, ...a: unknown[]) => Promise<boolean>; shopId: string }) {
  const mine = o.mechanicCid === d.me.cid;
  const can = d.me.onduty && (mine || d.me.manager);
  const open = ['draft', 'sent', 'approved', 'in_progress'].includes(o.status);
  return (
    <aside className="pane" aria-label={`Order ${o.id}`}>
      <div className="eyebrow">{o.kind === 'self' ? 'SELF-SERVICE' : 'QUOTE'} #{o.id}{o.version > 1 ? ` · V${o.version}` : ''}</div>
      <h2>{o.model.toUpperCase()}</h2>
      <div className="cust"><Icon name="user" size="0.95em" /> {o.customer} · {o.plate}</div>
      {o.note && <p className="note" style={{ marginTop: 0 }}>“{o.note}”</p>}
      <div className="scroll" style={{ flex: '0 1 auto' }}>
        {o.lines.map((l) => <div className="line" key={l.id}><span>{l.label}</span>{o.status === 'in_progress' || o.status === 'completed' ? <span className={`status ${l.installed ? 'ok' : 'muted'}`}>{l.installed ? 'Installed' : 'To do'}</span> : null}<b>{money(l.price)}</b></div>)}
        {!o.lines.length && <div className="empty">No items yet. Edit the order at the vehicle.</div>}
      </div>
      {o.labor > 0 && <div className="sum"><span>Labour</span><span>{money(o.labor)}</span></div>}
      {o.tax > 0 && <div className="sum"><span>Tax</span><span>{money(o.tax)}</span></div>}
      <div className="sum big"><span>Total</span><span>{money(o.total)}</span></div>
      {o.paid > 0 && <div className="sum"><span>Paid</span><span>{money(o.paid)}{o.refunded ? ` (refunded ${money(o.refunded)})` : ''}</span></div>}
      <div style={{ margin: '12px 0' }}><Status s={o.status} /></div>
      <span style={{ flex: 1 }} />
      {d.me.onduty && open && (
        <div className="actions">
          {!o.mechanicCid && <button className="btn small" disabled={busy} onClick={() => void run('orderAction', o.id, 'assign')}>Assign to me</button>}
          {can && (o.status === 'draft' || o.status === 'sent') && <button className="btn ghost" disabled={busy} onClick={() => void nui('editOrder', { shop: shopId, orderId: o.id, plate: o.plate })}>{o.status === 'sent' ? 'Edit (new version)' : 'Edit items'}</button>}
          {can && o.status === 'draft' && o.lines.length > 0 && <button className="btn primary" disabled={busy} onClick={() => void run('orderAction', o.id, 'send')}>Send quote</button>}
          {can && o.status === 'approved' && <button className="btn primary" disabled={busy} onClick={() => void run('orderAction', o.id, 'start')}>Start work</button>}
          {can && <button className="btn ghost danger" disabled={busy} onClick={() => void run('orderAction', o.id, 'cancel')}>Cancel order</button>}
        </div>
      )}
      {o.status === 'in_progress' && <p className="note">Install each item at the vehicle: target it and choose “Install approved work”.</p>}
      {o.status === 'sent' && <p className="note">Waiting for the customer to approve version {o.version} (they can type /customsquote).</p>}
    </aside>
  );
}

function Parts({ d, run, shopId }: { d: Data; run: (n: string, ...a: unknown[]) => Promise<boolean>; shopId: string }) {
  const [qty, setQty] = useState<Record<string, number>>({});
  if (!d.shop.stock) return <><h1>Parts</h1><div className="empty">This shop does not track parts.</div></>;
  return (
    <>
      <h1>Parts</h1>
      <div className="lead">{d.me.manager ? `Orders are paid from ${d.shop.business ? 'the business account' : 'your bank'}.` : 'Managers can order parts and set reorder thresholds.'}</div>
      <table>
        <thead><tr><th>PART</th><th>IN STOCK</th><th>RESERVED</th><th>AVAILABLE</th><th>REORDER AT</th><th>INCOMING</th><th></th></tr></thead>
        <tbody>{d.parts.map((p) => {
          const avail = p.qty - p.reserved;
          return (
            <tr key={p.part}>
              <td>{p.label}<small style={{ display: 'block', color: 'var(--muted)' }}>{money(p.cost)} · {p.delivery} min</small></td>
              <td>{p.qty}</td><td>{p.reserved}</td>
              <td>{avail <= p.reorderAt ? <span className="status warn">{avail} low</span> : avail}</td>
              <td>{d.me.manager ? <input className="input num" type="number" min={0} max={100} defaultValue={p.reorderAt} aria-label={`Reorder threshold for ${p.label}`}
                onBlur={(e) => { const v = Number(e.target.value); if (v !== p.reorderAt) void run('partsThreshold', shopId, p.part, v); }} /> : p.reorderAt}</td>
              <td>{p.incoming || '—'}</td>
              <td>{d.me.manager && <span style={{ display: 'flex', gap: 6 }}>
                <input className="input num" type="number" min={1} max={50} value={qty[p.part] ?? 5} aria-label={`Quantity of ${p.label}`} onChange={(e) => setQty({ ...qty, [p.part]: Number(e.target.value) })} />
                <button className="btn small" onClick={() => void run('partsOrder', shopId, p.part, qty[p.part] ?? 5)}>Order</button></span>}</td>
            </tr>
          );
        })}</tbody>
      </table>
      <div className="section-title">Recent part orders</div>
      {d.partOrders.length === 0 && <div className="empty">None yet.</div>}
      {d.partOrders.map((o) => (
        <div className="line" key={o.id}><span>{o.qty}× {d.parts.find((p) => p.part === o.part)?.label ?? o.part} · {o.ordered_by}</span>
          <span className={`status ${o.status === 'delivered' ? 'ok' : 'warn'}`}>{o.status === 'delivered' ? 'Delivered' : `Arrives ${when(o.arrives)}`}</span><b>{money(o.cost)}</b></div>
      ))}
    </>
  );
}

function Team({ d, run, shopId, sel }: { d: Data; run: (n: string, ...a: unknown[]) => Promise<boolean>; shopId: string; sel: Order | null }) {
  const [mult, setMult] = useState(d.pricing.multiplier);
  const [labor, setLabor] = useState(Math.round(d.pricing.laborRate * 100));
  return (
    <>
      <h1>Team</h1>
      <div className="lead">Staff online now. Grades and permissions come from the job.</div>
      <table>
        <thead><tr><th>NAME</th><th>GRADE</th><th>DUTY</th><th>ACTIVE JOBS</th><th></th></tr></thead>
        <tbody>{d.team.map((m) => (
          <tr key={m.cid}><td>{m.name}</td><td>{m.grade}</td><td><span className={`status ${m.onduty ? 'ok' : 'muted'}`}>{m.onduty ? 'On duty' : 'Off duty'}</span></td><td>{m.active}</td>
            <td>{d.me.manager && sel && ['draft', 'sent', 'approved', 'in_progress'].includes(sel.status) &&
              <button className="btn small" onClick={() => void run('orderAction', sel.id, 'assign', m.cid)}>Assign #{sel.id}</button>}</td></tr>
        ))}</tbody>
      </table>
      {d.me.manager && <>
        <div className="section-title">Pricing</div>
        <div className="field" style={{ maxWidth: 520 }}><label style={{ minWidth: '9em' }}>Price multiplier</label><input className="input" type="number" step={0.05} min={0.8} max={2} value={mult} onChange={(e) => setMult(Number(e.target.value))} /></div>
        <div className="field" style={{ maxWidth: 520 }}><label style={{ minWidth: '9em' }}>Labour %</label><input className="input" type="number" min={0} max={30} value={labor} onChange={(e) => setLabor(Number(e.target.value))} /></div>
        <button className="btn" onClick={() => void run('pricing', shopId, mult, labor / 100)}>Save pricing</button>
        <p className="note">Applies to new quotes. Existing quotes keep the price the customer saw.</p>
      </>}
    </>
  );
}

function History({ d }: { d: Data }) {
  return (
    <>
      <h1>History</h1>
      <div className="lead">Closed orders and receipts.</div>
      <table>
        <thead><tr><th>ORDER</th><th>VEHICLE</th><th>CUSTOMER</th><th>STATUS</th><th>TOTAL</th><th>WHEN</th></tr></thead>
        <tbody>{d.history.map((h) => (
          <tr key={h.id}><td>#{h.id}{h.kind === 'self' ? ' (self)' : ''}</td><td>{h.model.toUpperCase()} · {h.plate}</td><td>{h.customer_name}</td><td><Status s={h.status} /></td>
            <td>{money(h.paid - h.refunded)}{h.refunded ? <small style={{ color: 'var(--muted)' }}> (of {money(h.total)})</small> : null}</td><td>{when(h.at)}</td></tr>
        ))}</tbody>
      </table>
      {d.me.manager && <>
        <div className="section-title">Audit trail</div>
        {d.log.map((l, i) => <div className="line" key={i}><span>{l.order_id ? `#${l.order_id} · ` : ''}{l.action.replace(/_/g, ' ')}{l.detail ? ` · ${l.detail}` : ''}</span><span style={{ color: 'var(--muted)' }}>{l.actor} · {when(l.at)}</span></div>)}
      </>}
    </>
  );
}
