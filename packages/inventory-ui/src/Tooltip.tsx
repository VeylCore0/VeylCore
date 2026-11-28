import type { SlotItem } from '@veyl/ui';
import { kgText, type Def } from './types';

const LABELS: Record<string, string> = {
  quality: 'Quality', grade: 'Grade', varietyLabel: 'Variety', batch: 'Batch', serial: 'Serial', durability: 'Condition', ammo: 'Ammo', created: 'Made',
  firstname: 'First name', lastname: 'Last name', birthdate: 'Born', citizenid: 'Citizen ID', number: 'Number', label: 'For',
};
const HIDDEN = new Set(['branch', 'variety', 'sim', 'door', 'rev', 'issued', 'created']);

function metaLines(meta: Record<string, unknown> | undefined): [string, string][] {
  if (!meta) return [];
  const out: [string, string][] = [];
  for (const [k, v] of Object.entries(meta)) {
    if (HIDDEN.has(k) || k.startsWith('_')) continue;
    if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') out.push([LABELS[k] ?? k.replace(/([A-Z])/g, ' $1').replace(/^./, (c) => c.toUpperCase()), String(v)]);
  }
  return out.slice(0, 7);
}

export interface TipState { item: SlotItem; def?: Def; x: number; y: number }

/** Hover card for an item: what it is, what it weighs and whatever the server stored on it. Follows the pointer, never leaves the screen. */
export function Tooltip({ tip }: { tip: TipState }) {
  const { item, def } = tip;
  const lines = metaLines(item.metadata);
  const w = 17 * 16;
  const left = Math.min(tip.x + 18, window.innerWidth - w - 12);
  const top = Math.min(tip.y + 18, window.innerHeight - 240);
  const grade = typeof item.metadata?.grade === 'string' ? String(item.metadata.grade).toLowerCase() : '';
  return (
    <div className="itip" style={{ left, top, width: w }} role="tooltip">
      <div className="itip-top">
        <strong>{def?.label ?? item.name}</strong>
        {def?.category && def.category !== 'misc' && <span className="itip-cat">{def.category}</span>}
        {grade && <span className={`itip-grade ${grade}`}>{grade}</span>}
      </div>
      {def?.description && <p className="itip-desc">{def.description}</p>}
      {lines.length > 0 && <dl className="itip-meta">{lines.map(([k, v]) => <div key={k}><dt>{k}</dt><dd>{v}</dd></div>)}</dl>}
      <div className="itip-foot">
        <span>{def ? `${kgText(def.weight)} kg each` : ''}</span>
        <span>{item.count > 1 && def ? `${kgText(def.weight * item.count)} kg total` : ''}</span>
      </div>
      {def?.equip && <div className="itip-hint">Wear it in the {def.equip} slot</div>}
    </div>
  );
}
