import { useEffect, useState } from 'react';
import { Icon } from '@veyl/ui';
import { EYE_COLORS, FEATURE_GROUPS, PARENTS, type Category, type Slot } from './types';

type OnChange = (next: Slot) => void;

/** Prev / number / next with a slider underneath. `allowNone` adds index -1 shown as "None". */
export function IndexPicker({ label, value, min, max, onChange, format }: {
  label: string; value: number; min: number; max: number; onChange: (v: number) => void; format?: (v: number) => string;
}) {
  const [draft, setDraft] = useState('');
  const show = (v: number) => (format ? format(v) : v < 0 ? 'None' : String(v + 1));
  const count = max - Math.max(min, 0) + 1;
  const wrap = (v: number) => (v > max ? min : v < min ? max : v);
  useEffect(() => setDraft(''), [value]);

  const commit = () => {
    if (draft.trim() === '') return;
    const n = Number(draft);
    if (Number.isFinite(n)) onChange(Math.max(min, Math.min(max, Math.round(n) - 1)));
    setDraft('');
  };

  return (
    <div className="ap-picker">
      <div className="ap-picker-head">
        <span>{label}</span>
        <span className="v-muted">{max < 0 ? 'none available' : `${count} option${count === 1 ? '' : 's'}`}</span>
      </div>
      <div className="ap-picker-row">
        <button className="v-btn ap-arrow" aria-label={`Previous ${label}`} disabled={max <= min} onClick={() => onChange(wrap(value - 1))}>
          <Icon name="chevron" size="1rem" style={{ transform: 'rotate(180deg)' }} />
        </button>
        <input
          className="v-input ap-index" aria-label={`${label} number`} inputMode="numeric"
          value={draft !== '' ? draft : show(value)} onFocus={(e) => { setDraft(value < 0 ? '' : String(value + 1)); e.target.select(); }}
          onChange={(e) => setDraft(e.target.value.replace(/[^\d]/g, '').slice(0, 4))}
          onBlur={commit} onKeyDown={(e) => { if (e.key === 'Enter') { commit(); (e.target as HTMLInputElement).blur(); } }}
        />
        <button className="v-btn ap-arrow" aria-label={`Next ${label}`} disabled={max <= min} onClick={() => onChange(wrap(value + 1))}>
          <Icon name="chevron" size="1rem" />
        </button>
      </div>
      {max > min && (
        <input type="range" className="ap-range" min={min} max={max} value={value} aria-label={`${label} slider`}
          onChange={(e) => onChange(Number(e.target.value))} />
      )}
    </div>
  );
}

export function Slider({ label, value, min, max, onChange, low, high }: {
  label: string; value: number; min: number; max: number; onChange: (v: number) => void; low?: string; high?: string;
}) {
  return (
    <label className="ap-slider">
      <span className="ap-slider-head"><span>{label}</span><span className="v-muted">{value}</span></span>
      <input type="range" className="ap-range" min={min} max={max} value={value} onChange={(e) => onChange(Number(e.target.value))} />
      {(low || high) && <span className="ap-slider-ends v-muted"><span>{low}</span><span>{high}</span></span>}
    </label>
  );
}

export function Swatches({ label, colors, value, onChange }: { label: string; colors: string[]; value: number; onChange: (v: number) => void }) {
  return (
    <div className="ap-swatches-block">
      <div className="ap-picker-head"><span>{label}</span><span className="v-muted">#{value + 1}</span></div>
      <div className="ap-swatches" role="radiogroup" aria-label={label}>
        {colors.map((c, i) => (
          <button key={i} role="radio" aria-checked={i === value} aria-label={`${label} ${i + 1}`}
            className={`ap-swatch${i === value ? ' on' : ''}`} style={{ background: c }} onClick={() => onChange(i)} />
        ))}
      </div>
    </div>
  );
}

/** Editor for one clothing / prop / overlay / hair category. */
export function SlotEditor({ cat, value, palettes, onChange }: {
  cat: Category; value: Slot; palettes: { hair: string[]; makeup: string[] }; onChange: OnChange;
}) {
  const d = value.d ?? 0;
  const allowNone = cat.kind === 'prop' || cat.kind === 'overlay';
  const palette = cat.color ? palettes[cat.color] : null;
  return (
    <div className="ap-editor-body">
      <IndexPicker label="Style" value={d} min={allowNone ? -1 : 0} max={cat.max ?? 0}
        onChange={(v) => onChange({ ...value, d: v, t: 0 })} />
      {cat.kind !== 'overlay' && (cat.textures ?? 1) > 1 && d >= 0 && (
        <IndexPicker label="Colour variant" value={value.t ?? 0} min={0} max={(cat.textures ?? 1) - 1}
          onChange={(v) => onChange({ ...value, t: v })} />
      )}
      {allowNone && d >= 0 && (
        <button className="v-btn ap-none" onClick={() => onChange({ ...value, d: -1, t: 0 })}>Remove ({cat.kind === 'prop' ? 'none' : 'clean'})</button>
      )}
      {cat.kind === 'overlay' && d >= 0 && (
        <Slider label="Opacity" value={value.opacity ?? 100} min={0} max={100} onChange={(v) => onChange({ ...value, opacity: v })} />
      )}
      {palette && (cat.kind !== 'overlay' || d >= 0) && (
        <Swatches label={cat.color2 ? 'Main colour' : 'Colour'} colors={palette} value={value.color ?? 0} onChange={(v) => onChange({ ...value, color: v })} />
      )}
      {palette && cat.color2 && (
        <Swatches label="Highlights" colors={palette} value={value.color2 ?? 0} onChange={(v) => onChange({ ...value, color2: v })} />
      )}
    </div>
  );
}

export function HeritageEditor({ value, onChange }: { value: Slot; onChange: OnChange }) {
  const name = (v: number) => PARENTS[v] ?? `Face ${v + 1}`;
  return (
    <div className="ap-editor-body">
      <IndexPicker label="Mother" value={value.mother ?? 21} min={0} max={45} format={name} onChange={(v) => onChange({ ...value, mother: v })} />
      <IndexPicker label="Father" value={value.father ?? 0} min={0} max={45} format={name} onChange={(v) => onChange({ ...value, father: v })} />
      <Slider label="Resemblance" value={value.shapeMix ?? 50} min={0} max={100} low="Mother" high="Father" onChange={(v) => onChange({ ...value, shapeMix: v })} />
      <Slider label="Skin tone" value={value.skinMix ?? 50} min={0} max={100} low="Mother" high="Father" onChange={(v) => onChange({ ...value, skinMix: v })} />
    </div>
  );
}

export function FeaturesEditor({ value, onChange }: { value: Slot; onChange: OnChange }) {
  const values = value.values ?? new Array(20).fill(0);
  const set = (i: number, v: number) => { const next = [...values]; next[i] = v; onChange({ values: next }); };
  return (
    <div className="ap-editor-body">
      <button className="v-btn ap-none" onClick={() => onChange({ values: new Array(20).fill(0) })}><Icon name="reset" size="0.95rem" /> Neutral face</button>
      {FEATURE_GROUPS.map((g) => (
        <div key={g.label} className="ap-feature-group">
          <div className="ap-group-title">{g.label}</div>
          {g.items.map((it) => (
            <Slider key={it.index} label={it.label} value={values[it.index] ?? 0} min={-100} max={100} low={it.low} high={it.high} onChange={(v) => set(it.index, v)} />
          ))}
        </div>
      ))}
    </div>
  );
}

export function EyesEditor({ value, onChange }: { value: Slot; onChange: OnChange }) {
  return (
    <div className="ap-editor-body">
      <div className="ap-eyes" role="radiogroup" aria-label="Eye colour">
        {EYE_COLORS.map((c, i) => (
          <button key={i} role="radio" aria-checked={value.d === i} className={`ap-eye${value.d === i ? ' on' : ''}`} onClick={() => onChange({ d: i })}>
            <span className="dot" style={{ background: c.hex }} />{c.label}
          </button>
        ))}
      </div>
    </div>
  );
}
