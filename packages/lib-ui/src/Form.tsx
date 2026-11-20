import { useEffect, useRef, useState } from 'react';
import { Panel, type FormField, type FormOpen } from '@veyl/ui';
import { sendResult } from './App';

type Values = Record<string, string | number | boolean | null>;

function initial(fields: FormField[]): Values {
  const v: Values = {};
  for (const f of fields) {
    if (f.type === 'checkbox') v[f.name] = Boolean(f.default);
    else if (f.default !== undefined) v[f.name] = f.default as string | number;
    else if (f.type === 'select') v[f.name] = f.options?.[0]?.value ?? '';
    else v[f.name] = '';
  }
  return v;
}

export function Form({ data }: { data: FormOpen }) {
  const [values, setValues] = useState<Values>(() => initial(data.fields));
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [pending, setPending] = useState(false);
  const firstRef = useRef<HTMLInputElement | HTMLSelectElement | null>(null);

  useEffect(() => {
    setValues(initial(data.fields));
    setErrors({});
    setPending(false);
    setTimeout(() => firstRef.current?.focus(), 30);
  }, [data]);

  const validate = (): Values | null => {
    const errs: Record<string, string> = {};
    const out: Values = {};
    for (const f of data.fields) {
      let v = values[f.name];
      if (f.type === 'number') {
        if (v === '' || v === null) v = null;
        else {
          const n = Number(v);
          if (!Number.isFinite(n)) errs[f.name] = 'Enter a number';
          else if (f.min !== undefined && n < f.min) errs[f.name] = `Minimum ${f.min}`;
          else if (f.max !== undefined && n > f.max) errs[f.name] = `Maximum ${f.max}`;
          v = n;
        }
      } else if (typeof v === 'string') {
        v = v.trim();
        if (f.maxLength && v.length > f.maxLength) errs[f.name] = `At most ${f.maxLength} characters`;
      }
      if (f.required && (v === null || v === '')) errs[f.name] = 'Required';
      out[f.name] = v;
    }
    setErrors(errs);
    return Object.keys(errs).length ? null : out;
  };

  const submit = () => {
    if (pending) return;
    const v = validate();
    if (!v) return;
    setPending(true); // submit once
    void sendResult(data.token, { type: 'submit', values: v });
  };
  const cancel = () => {
    if (pending) return;
    setPending(true);
    void sendResult(data.token, { type: 'cancel' });
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') cancel(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  return (
    <Panel
      title={data.title}
      width={420}
      onClose={cancel}
      footer={
        <>
          <button className="v-btn" onClick={cancel} disabled={pending}>Cancel</button>
          <button className="v-btn primary" onClick={submit} disabled={pending}>{data.submitLabel ?? 'Submit'}</button>
        </>
      }
    >
      <form onSubmit={(e) => { e.preventDefault(); submit(); }}>
        {data.fields.map((f, i) => (
          <label key={f.name} className="field">
            <span className="field-label">{f.label}{f.required ? ' *' : ''}</span>
            {f.type === 'select' ? (
              <select
                ref={i === 0 ? (el) => { firstRef.current = el; } : undefined}
                value={String(values[f.name] ?? '')}
                onChange={(e) => setValues({ ...values, [f.name]: e.target.value })}
              >
                {f.options?.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
              </select>
            ) : f.type === 'checkbox' ? (
              <input type="checkbox" checked={Boolean(values[f.name])} onChange={(e) => setValues({ ...values, [f.name]: e.target.checked })} />
            ) : (
              <input
                ref={i === 0 ? (el) => { firstRef.current = el; } : undefined}
                type={f.type === 'number' ? 'number' : f.type === 'date' ? 'date' : 'text'}
                min={f.min}
                max={f.max}
                maxLength={f.maxLength}
                placeholder={f.placeholder}
                value={String(values[f.name] ?? '')}
                onChange={(e) => setValues({ ...values, [f.name]: e.target.value })}
              />
            )}
            {errors[f.name] && <span className="field-error">✕ {errors[f.name]}</span>}
          </label>
        ))}
        <button type="submit" style={{ display: 'none' }} />
      </form>
    </Panel>
  );
}
