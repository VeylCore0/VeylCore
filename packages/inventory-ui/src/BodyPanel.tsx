import type { SlotItem } from '@veyl/ui';
import { SlotTile, countText, type SlotHandlers } from './Grid';
import { Figure } from './Figure';
import { key, kgText, type Def, type EquipSlot, type Profile, type SlotAddress, type View } from './types';

const ICONS: Record<string, string> = {
  headset: 'M4 13v-1a8 8 0 0 1 16 0v1M4 13h3v5H5a1 1 0 0 1-1-1zM20 13h-3v5h2a1 1 0 0 0 1-1z',
  mask: 'M4 9c3-2 5-2 8 0 3-2 5-2 8 0v4c0 4-3 7-8 7s-8-3-8-7zM8 12h2M14 12h2',
  glasses: 'M3 12a4 4 0 1 0 8 0 4 4 0 0 0-8 0zM13 12a4 4 0 1 0 8 0 4 4 0 0 0-8 0zM11 12h2',
  shield: 'M12 3l7 3v5c0 5-3 8-7 10-4-2-7-5-7-10V6z',
  hat: 'M4 15c0-4 3-8 8-8s8 4 8 8zM2 15h20v2H2z',
  id: 'M4 6h16v12H4zM8 10a2 2 0 1 0 4 0 2 2 0 0 0-4 0zM7 16c0-2 2-3 3-3s3 1 3 3M15 10h3M15 13h3',
  phone: 'M8 3h8a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM11 18h2',
  tablet: 'M5 4h14a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1zM11 17h2',
  key: 'M7 14a4 4 0 1 1 3.9-5H21v3h-2v2h-3v-2h-5.1A4 4 0 0 1 7 14z',
  backpack: 'M8 8V6a4 4 0 0 1 8 0v2M6 8h12l1 12H5zM9 14h6M9 11h6',
  sim: 'M7 3h7l4 4v14H7zM10 12h6v6h-6zM10 15h6M13 12v6',
};

export function SlotIcon({ name }: { name: string }) {
  return <svg className="slot-ghost" viewBox="0 0 24 24" aria-hidden="true"><path d={ICONS[name] ?? ICONS.shield} /></svg>;
}

export function BodyPanel(props: {
  equip?: View; slots: EquipSlot[]; defs: Record<string, Def>; imagePath: string; profile?: Profile; cash: number; carried: number; carryMax: number;
  pending: Set<string>; selected: SlotAddress | null; handlers: SlotHandlers; matches: (item: SlotItem | undefined) => boolean;
}) {
  const bySlot = new Map((props.equip?.items ?? []).map((i) => [i.slot, i] as const));
  const slotEl = (s: EquipSlot) => {
    const addr: SlotAddress = { ref: 'equip', slot: s.slot };
    const item = bySlot.get(s.slot);
    return (
      <SlotTile key={s.slot} addr={addr} item={item} def={item ? props.defs[item.name] : undefined} imagePath={props.imagePath}
        selected={props.selected?.ref === 'equip' && props.selected.slot === s.slot} pending={props.pending.has(key(addr))} dim={!props.matches(item)}
        className="eq" placeholder={<SlotIcon name={s.icon} />} handlers={props.handlers} />
    );
  };
  const left = props.slots.filter((s) => s.side === 'left');
  const right = props.slots.filter((s) => s.side === 'right');
  const p = props.profile;
  return (
    <section className="ipanel body-panel" aria-label="Body">
      <header className="ipanel-head">
        <span className="idiamond"><svg viewBox="0 0 24 24"><circle cx="12" cy="5" r="2.2" /><path d="M12 8v6M7 10l5 1 5-1M9 21l3-7 3 7" /></svg></span>
        <div><h3>Body</h3><p>Player Body</p></div>
      </header>
      <div className="body-grid">
        <div className="ieq-col">{left.map(slotEl)}</div>
        <Figure />
        <div className="ieq-col">
          {right.map(slotEl)}
          <div className="cash-tile" title="Cash">
            <span className="slot-count">{countText(props.cash)}</span>
            <img className="slot-img" draggable={false} src={`${props.imagePath}/money.png`} alt="Cash" onError={(e) => { (e.target as HTMLImageElement).style.visibility = 'hidden'; }} />
          </div>
        </div>
      </div>
      <div className="info-title"><i />Personal information</div>
      <dl className="iinfo">
        <div className="green"><dt>{p?.job ?? 'Unemployed'}</dt><dd>{p?.name ?? '—'}</dd></div>
        <div className="blue"><dt>CID</dt><dd>{p?.cid ?? '—'}</dd></div>
        <div className="purple"><dt>Phone number</dt><dd>{p?.phone ?? 'None'}</dd></div>
        <div className="orange"><dt>Carrying</dt><dd>{kgText(props.carried)}/{kgText(props.carryMax)} kg</dd></div>
      </dl>
    </section>
  );
}
