import { useCallback, useEffect, useState } from 'react';
import type { Ctx } from './ctx';
import type { Property } from './types';
import { api, Bar, Button, Chip, Confirm, Empty, Ico, Modal, cx, usd } from './ui';

export function Properties({ c }: { c: Ctx }) {
  const { properties, owned, maxOwned } = c.s.properties;
  const [open, setOpen] = useState<string | null>(null);
  const [buy, setBuy] = useState<Property | null>(null);
  const mine = properties.filter((p) => p.role);
  const sale = properties.filter((p) => !p.role);
  const selected = properties.find((p) => p.id === open);
  return (
    <div className="pr-page">
      <div className="pr-page-head"><div><h2>Properties</h2><p>Laboratories: {owned}/{maxOwned} owned. Buy one, upgrade it, share it, lock it.</p></div></div>
      <h4 className="pr-h">YOURS</h4>
      {mine.length === 0 ? <Empty icon="home" title="No laboratory yet" text="Buy one below. You can also be added as staff by an owner." /> : (
        <div className="pr-props">{mine.map((p) => <PropCard key={p.id} p={p} onOpen={() => setOpen(p.id)} />)}</div>
      )}
      <h4 className="pr-h">ON THE MARKET</h4>
      <div className="pr-props">
        {sale.map((p) => <PropCard key={p.id} p={p} onBuy={() => setBuy(p)} />)}
      </div>
      {selected && <Manage c={c} p={selected} onClose={() => setOpen(null)} />}
      {buy && (
        <Confirm title={buy.buyback ? `Buy back ${buy.label}?` : `Buy ${buy.label}?`} confirm={`Pay ${usd(buy.buyback ? buy.buyback.price : buy.price)}`}
          text={buy.buyback ? 'You sold it recently: this is your buyback price, and your old storage comes back with it.' : 'The price is taken in cash. The laboratory starts locked and empty.'}
          onCancel={() => setBuy(null)} onConfirm={() => { const id = buy.id; setBuy(null); void c.run('propBuy', id); }} />
      )}
    </div>
  );
}

function PropCard({ p, onOpen, onBuy }: { p: Property; onOpen?: () => void; onBuy?: () => void }) {
  return (
    <article className={cx('pr-prop', !p.role && p.owned && 'taken')}>
      <div className="pr-prop-top"><strong>{p.label}</strong>{p.role ? <Chip tone="accent">{p.role}</Chip> : p.owned ? <Chip tone="mute">Owned</Chip> : p.buyback ? <Chip tone="warn">Buyback</Chip> : <Chip tone="ok">For sale</Chip>}</div>
      <p>{p.description}</p>
      {p.role ? (
        <>
          <div className="pr-prop-stats"><span><Ico name={p.locked ? 'lock' : 'unlock'} size={14} />{p.locked ? 'Locked' : 'Open'}</span>{p.storage && <span><Ico name="box" size={14} />{p.storage.slots} slots</span>}{p.benches && <span><Ico name="gear" size={14} />{p.benches.used}/{p.benches.max} benches</span>}</div>
          <Button kind="primary" onClick={onOpen}>Manage</Button>
        </>
      ) : (
        <>
          <div className="pr-prop-stats"><span className="pr-price">{usd(p.buyback ? p.buyback.price : p.price)}</span><span><Ico name="star" size={14} />Level {p.level}</span></div>
          {p.owned || p.reserved ? <span className="pr-mute">{p.reserved ? 'Reserved for its old owner' : 'Not available'}</span>
            : p.levelOk === false ? <Chip tone="warn"><Ico name="lock" size={12} />Needs level {p.level}</Chip>
            : <Button kind="primary" onClick={onBuy}>{p.buyback ? 'Buy back' : 'Buy'}</Button>}
        </>
      )}
    </article>
  );
}

function Manage({ c, p, onClose }: { c: Ctx; p: Property; onClose: () => void }) {
  const [tab, setTab] = useState<'overview' | 'upgrades' | 'security'>('overview');
  const owner = p.role === 'owner';
  const upgrades = c.s.properties.upgrades;
  const [confirm, setConfirm] = useState<{ kind: 'sell' | 'upgrade'; key?: string } | null>(null);
  return (
    <Modal title={p.label} onClose={onClose} wide>
      <div className="pr-tabs" role="tablist">
        {(['overview', 'upgrades', 'security'] as const).map((t) => <button key={t} role="tab" aria-selected={tab === t} className={cx(tab === t && 'on')} onClick={() => setTab(t)} disabled={!owner && t !== 'overview'}>{t[0].toUpperCase() + t.slice(1)}</button>)}
      </div>
      {tab === 'overview' && (
        <div className="pr-manage">
          <div className="pr-kv"><span>Your role</span><b>{p.role}</b></div>
          <div className="pr-kv"><span>Status</span><b>{p.locked ? 'Locked' : 'Unlocked'}{p.hasCode ? ' · has a code' : ''}</b></div>
          <div className="pr-kv"><span>Storage</span><b>{p.storage?.slots} slots · {Math.round((p.storage?.weight ?? 0) / 1000)} kg</b></div>
          <div className="pr-kv"><span>Workstation slots</span><b>{p.benches?.used} / {p.benches?.max}</b></div>
          {p.inside ? <Button kind="primary" onClick={() => void c.run('propStorage', p.id)}><Ico name="box" size={16} />Open storage</Button> : <p className="pr-mute"><Ico name="info" size={14} /> Go inside to open the storage and set up benches and plants.</p>}
          {owner && <div className="pr-danger"><Button kind="danger" onClick={() => setConfirm({ kind: 'sell' })}>Sell for {usd(p.sellFor ?? 0)}</Button><span className="pr-mute">Remove plants and benches first. You can buy it back for a day.</span></div>}
          {owner && <Transfer c={c} p={p} />}
        </div>
      )}
      {tab === 'upgrades' && owner && (
        <div className="pr-upgrades">
          {Object.entries(upgrades).map(([key, u]) => {
            const lv = p.upgrades?.[key] ?? 0;
            const next = u.levels[lv];
            return (
              <section key={key} className="pr-card">
                <div className="pr-up-top"><strong>{u.label}</strong><span className="pr-pips">{u.levels.map((_, i) => <i key={i} className={i < lv ? 'on' : ''} />)}</span></div>
                <p className="pr-mute">{describe(key, next)}</p>
                {next ? <Button kind="primary" disabled={c.busy} onClick={() => setConfirm({ kind: 'upgrade', key })}>Upgrade · {usd(next.price)}</Button> : <Chip tone="ok">Maxed</Chip>}
              </section>
            );
          })}
        </div>
      )}
      {tab === 'security' && owner && <Security c={c} p={p} />}
      {confirm?.kind === 'sell' && <Confirm danger title={`Sell ${p.label}?`} text={`You get ${usd(p.sellFor ?? 0)} now. Staff lose access. Anything left in its storage stays behind with the property.`} confirm="Sell" onCancel={() => setConfirm(null)} onConfirm={() => { setConfirm(null); onClose(); void c.run('propSell', p.id); }} />}
      {confirm?.kind === 'upgrade' && confirm.key && <Confirm title={`Upgrade ${upgrades[confirm.key].label}?`} text={`${usd(upgrades[confirm.key].levels[p.upgrades?.[confirm.key] ?? 0].price)} will be taken from your cash.`} confirm="Pay and upgrade" onCancel={() => setConfirm(null)} onConfirm={() => { const k = confirm.key; setConfirm(null); void c.run('propUpgrade', p.id, k); }} />}
    </Modal>
  );
}

function describe(key: string, next?: { [k: string]: number }) {
  if (!next) return 'Fully upgraded.';
  if (key === 'storage') return `+${next.slots} slots and +${Math.round(next.maxWeight / 1000)} kg of storage.`;
  if (key === 'benches') return `+${next.slots} workstation slot.`;
  if (key === 'equipment') return `+${next.quality} quality on everything made here, ${Math.round((1 - next.speed) * 100)}% faster stages.`;
  if (key === 'security') return `Doors take ${next.breachSeconds}s longer to breach. Visitors are reported to you.`;
  return '';
}

function Transfer({ c, p }: { c: Ctx; p: Property }) {
  const [list, setList] = useState<{ id: number; name: string }[] | null>(null);
  const scan = useCallback(async () => { const r = await api<{ id: number; name: string }[]>('nearbyPlayers'); setList(r.ok ? r.data ?? [] : []); }, []);
  return (
    <div className="pr-transfer">
      <Button kind="ghost" onClick={() => void scan()}><Ico name="users" size={15} />Give to a nearby player</Button>
      {list && (list.length === 0 ? <span className="pr-mute">Nobody close by.</span> : list.map((n) => <Button key={n.id} onClick={() => { setList(null); void c.run('propTransfer', p.id, n.id); }}>{n.name}</Button>))}
    </div>
  );
}

function Security({ c, p }: { c: Ctx; p: Property }) {
  const [code, setCode] = useState('');
  const [nearby, setNearby] = useState<{ id: number; name: string }[] | null>(null);
  const [role, setRole] = useState<'employee' | 'guest'>('employee');
  useEffect(() => { setCode(''); }, [p.id]);
  const scan = useCallback(async () => { const r = await api<{ id: number; name: string }[]>('nearbyPlayers'); setNearby(r.ok ? r.data ?? [] : []); }, []);
  return (
    <div className="pr-security">
      <section className="pr-card">
        <h4 className="pr-h"><Ico name="lock" size={15} />DOOR</h4>
        <div className="pr-row"><span>{p.locked ? 'Locked: only staff and people with the code get in.' : 'Unlocked: anyone can walk in.'}</span><Button kind={p.locked ? 'ghost' : 'primary'} onClick={() => void c.run('propLock', p.id, !p.locked)}>{p.locked ? 'Unlock' : 'Lock'}</Button></div>
        <div className="pr-row">
          <input className="pr-input" inputMode="numeric" maxLength={8} placeholder={p.hasCode ? 'New access code (4-8 digits)' : 'Set an access code (4-8 digits)'} value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))} aria-label="Access code" />
          <Button kind="primary" disabled={code.length < 4} onClick={async () => { await c.run('propCode', p.id, code); setCode(''); }}>Set code</Button>
          {p.hasCode && <Button kind="danger" onClick={() => void c.run('propCode', p.id, '')}>Remove code</Button>}
        </div>
      </section>
      <section className="pr-card">
        <h4 className="pr-h"><Ico name="users" size={15} />STAFF</h4>
        {(p.members ?? []).length === 0 ? <p className="pr-mute">Nobody has access besides you.</p> : (
          <ul className="pr-members">{(p.members ?? []).map((m) => <li key={m.id}><Ico name="users" size={15} /><span>{m.name}</span><Chip tone={m.role === 'employee' ? 'accent' : 'mute'}>{m.role}</Chip><Button kind="ghost" onClick={() => void c.run('propMemberRemove', p.id, m.id)}>Remove</Button></li>)}</ul>
        )}
        <div className="pr-row">
          <select className="pr-input" value={role} onChange={(e) => setRole(e.target.value as 'employee' | 'guest')} aria-label="Role"><option value="employee">Employee: storage, benches, plants</option><option value="guest">Guest: can enter only</option></select>
          <Button onClick={() => void scan()}>Find nearby</Button>
        </div>
        {nearby && (nearby.length === 0 ? <p className="pr-mute">Nobody close by.</p> : <div className="pr-row wrap">{nearby.map((n) => <Button key={n.id} kind="primary" onClick={() => { setNearby(null); void c.run('propMemberAdd', p.id, n.id, role); }}>Add {n.name}</Button>)}</div>)}
      </section>
    </div>
  );
}
