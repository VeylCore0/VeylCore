import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Icon, StateView, Stepper, newOpId, nui } from '@veyl/ui';
import type { BatchMeta, EquipmentView, RecipeView } from './types';

type Phase = { kind: 'idle' } | { kind: 'working'; token: string; durationMs: number; challenge: 'timing' | 'calibration' | 'steady'; startedAt: number }
  | { kind: 'finishing' };

/** How many units the player can afford for a recipe (with the chosen batch). */
function affordable(r: RecipeView, batch: { count: number } | null, max: number) {
  let n = max;
  for (const i of r.inputs) n = Math.min(n, Math.floor((i.batch ? batch?.count ?? 0 : i.have) / i.count));
  return Math.max(0, n);
}

function fmt(ms: number) { const s = Math.round(ms / 1000); return s >= 60 ? `${Math.floor(s / 60)}m ${s % 60}s` : `${s}s`; }

export function Equipment({ data, onData }: { data: EquipmentView; onData: (d: EquipmentView) => void }) {
  const [recipeId, setRecipeId] = useState(data.recipes[0]?.id ?? '');
  const [batchIdx, setBatchIdx] = useState(0);
  const [units, setUnits] = useState(1);
  const [steady, setSteady] = useState(false);
  const [phase, setPhase] = useState<Phase>({ kind: 'idle' });
  const [toast, setToast] = useState<{ kind: 'error' | 'success'; text: string } | null>(null);
  const recipe = data.recipes.find((r) => r.id === recipeId) ?? data.recipes[0];
  const hasBatch = recipe?.inputs.some((i) => i.batch) ?? false;
  const batch = hasBatch ? recipe.batches[batchIdx] ?? null : null;
  const maxUnits = recipe ? affordable(recipe, batch, data.maxUnits) : 0;
  const working = phase.kind !== 'idle';

  useEffect(() => { setBatchIdx(0); setUnits(1); }, [recipeId]);
  useEffect(() => { if (units > Math.max(1, maxUnits)) setUnits(Math.max(1, maxUnits)); }, [maxUnits, units]);

  const say = useCallback((kind: 'error' | 'success', text: string) => {
    setToast({ kind, text });
    window.setTimeout(() => setToast(null), 3500);
  }, []);

  const start = async () => {
    if (!recipe || working || maxUnits < 1) return;
    const res = await nui<{ token: string; durationMs: number; challenge: 'timing' | 'calibration' }>('craftStart', {
      recipe: recipe.id, units, batch: batch?.metadata ?? null, opId: newOpId(),
    });
    if (!res.ok || !res.data) { say('error', res.message ?? res.code ?? 'Could not start'); return; }
    setPhase({ kind: 'working', token: res.data.token, durationMs: res.data.durationMs, challenge: steady ? 'steady' : res.data.challenge, startedAt: Date.now() });
  };

  const complete = useCallback(async (score: number) => {
    setPhase({ kind: 'finishing' });
    let res = await nui<{ state: string; view: EquipmentView }>('craftComplete', { score });
    for (let tries = 0; !res.ok && res.code === 'PENDING' && tries < 3; tries++) {
      await new Promise((r) => setTimeout(r, 1500));
      res = await nui('craftComplete', { score });
    }
    setPhase({ kind: 'idle' });
    if (res.ok && res.data) { onData(res.data.view); say(res.data.state === 'tray' ? 'error' : 'success', res.message ?? 'Done'); }
    else say('error', res.message ?? res.code ?? 'Could not finish');
  }, [onData, say]);

  const cancel = async () => {
    const res = await nui<{ view: EquipmentView }>('craftCancel');
    setPhase({ kind: 'idle' });
    if (res.data?.view) onData(res.data.view);
    say('success', res.message ?? 'Cancelled');
  };

  const collect = async () => {
    const res = await nui<{ view: EquipmentView }>('collectTray');
    if (res.data?.view) onData(res.data.view);
    say(res.ok ? 'success' : 'error', res.message ?? res.code ?? '');
  };

  // Escape: cancel a running job first (supplies come back), otherwise close.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      if (phase.kind === 'working') void cancel(); else if (phase.kind === 'idle') void nui('close');
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  return (
    <div className="dr-journal-wrap">
      <div className="dr-equip" role="dialog" aria-label={data.label}>
        <header className="dr-equip-head">
          <span className="dr-row-icon"><Icon name="box" size="1.3rem" /></span>
          <div>
            <div className="dr-title">{data.label}</div>
            <div className="dr-cond"><span className="v-muted">Condition</span><span className="track"><span style={{ width: `${data.condition}%` }} /></span><span>{data.condition}%</span></div>
          </div>
          <button className="dr-rail-btn" title="Close (Esc)" onClick={() => void nui('close')} disabled={working}><Icon name="close" size="1.2rem" /></button>
        </header>

        {data.tray.length > 0 && (
          <div className="dr-tray">
            <Icon name="hand" size="1rem" />
            <span>On the table: {data.tray.map((t) => `${t.count}x ${t.label}${t.grade ? ` (${t.grade})` : ''}`).join(', ')}</span>
            <button className="v-btn" onClick={() => void collect()} disabled={working}>Collect</button>
          </div>
        )}

        <div className="dr-equip-body">
          <nav className="dr-recipes" aria-label="Recipes">
            {data.recipes.map((r) => (
              <button key={r.id} className={`dr-recipe${r.id === recipe?.id ? ' on' : ''}`} disabled={working} onClick={() => setRecipeId(r.id)}>
                <Icon name={r.icon} size="1.1rem" /><span>{r.label}</span>
              </button>
            ))}
          </nav>

          {!recipe ? <StateView kind="empty" /> : phase.kind === 'idle' ? (
            <section className="dr-recipe-detail">
              <div className="dr-section-title">{recipe.label}</div>
              <div className="dr-io">
                <div>
                  <div className="v-muted dr-io-title">Uses (per unit)</div>
                  {recipe.inputs.map((i) => {
                    const have = i.batch ? batch?.count ?? 0 : i.have;
                    const ok = have >= i.count * units;
                    return <div key={i.item} className={`dr-io-row ${ok ? 'ok' : 'bad'}`}><span>{i.count}x {i.label}</span><span>{have} / {i.count * units}</span></div>;
                  })}
                </div>
                <Icon name="chevron" size="1.4rem" />
                <div>
                  <div className="v-muted dr-io-title">Makes</div>
                  <div className="dr-io-row ok"><span>{recipe.output.count * units}x {recipe.output.label}</span></div>
                  {hasBatch && <div className="v-muted dr-io-note">Keeps the batch, variety and grade. The challenge can move quality by up to ±{data.challengeQuality}.</div>}
                </div>
              </div>

              {hasBatch && (
                <div className="dr-batches" role="radiogroup" aria-label="Batch">
                  <div className="v-muted dr-io-title">Batch</div>
                  {recipe.batches.length === 0 && <div className="v-muted">You have nothing to use for this.</div>}
                  {recipe.batches.map((b, i) => (
                    <button key={b.metadata.batch + b.metadata.quality} role="radio" aria-checked={i === batchIdx} className={`dr-batch${i === batchIdx ? ' on' : ''}`} onClick={() => setBatchIdx(i)}>
                      <span>{b.metadata.varietyLabel}</span>
                      <span className={`dr-grade ${b.metadata.grade.toLowerCase()}`}>{b.metadata.grade}</span>
                      <span className="v-muted">Q{b.metadata.quality} · {b.metadata.batch} · {b.count} owned</span>
                    </button>
                  ))}
                </div>
              )}

              <div className="dr-run">
                <div className="dr-units"><span className="v-muted">Units</span><Stepper value={units} min={1} max={Math.max(1, maxUnits)} onChange={setUnits} disabled={maxUnits < 1} /></div>
                <span className="v-muted">Takes {fmt(recipe.msPerUnit * units)}</span>
                <label className="dr-toggle"><input type="checkbox" checked={steady} onChange={(e) => setSteady(e.target.checked)} /><span>Steady hands (skip the challenge)</span></label>
                <button className="v-btn primary" disabled={maxUnits < 1} onClick={() => void start()}>
                  {maxUnits < 1 ? 'Missing supplies' : `Start · ${recipe.output.count * units}x ${recipe.output.label}`}
                </button>
              </div>
            </section>
          ) : (
            <section className="dr-recipe-detail dr-working">
              {phase.kind === 'working' && (phase.challenge === 'timing' ? <TimingChallenge phase={phase} onDone={complete} />
                : phase.challenge === 'calibration' ? <CalibrationChallenge phase={phase} onDone={complete} />
                : <SteadyHands phase={phase} onDone={complete} />)}
              {phase.kind === 'finishing' && <StateView kind="loading" message="Finishing up…" />}
              {phase.kind === 'working' && <button className="v-btn" onClick={() => void cancel()}>Cancel (supplies come back)</button>}
            </section>
          )}
        </div>
      </div>
      {toast && <div className={`v-toast-inline ${toast.kind}`} role="status"><Icon name={toast.kind === 'error' ? 'alert' : 'check'} size="1rem" />{toast.text}</div>}
    </div>
  );
}

type Working = Extract<Phase, { kind: 'working' }>;

function useRemaining(phase: Working) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => { const t = window.setInterval(() => setNow(Date.now()), 100); return () => window.clearInterval(t); }, []);
  return Math.max(0, phase.durationMs - (now - phase.startedAt));
}

function TimeBar({ phase }: { phase: Working }) {
  const left = useRemaining(phase);
  return (
    <div className="dr-timebar"><span style={{ width: `${100 - (left / phase.durationMs) * 100}%` }} /><em>{fmt(left)}</em></div>
  );
}

/** Wait for the job's time, then complete with the given score (the server checks the time itself). */
function useFinishAt(phase: Working, score: () => number, onDone: (s: number) => void) {
  const scoreRef = useRef(score);
  scoreRef.current = score;
  useEffect(() => {
    const t = window.setTimeout(() => onDone(scoreRef.current()), Math.max(0, phase.durationMs - (Date.now() - phase.startedAt)) + 150);
    return () => window.clearTimeout(t);
  }, [phase, onDone]);
}

function SteadyHands({ phase, onDone }: { phase: Working; onDone: (s: number) => void }) {
  useFinishAt(phase, () => 0.6, onDone);
  return (<><div className="dr-section-title">Working steadily…</div><TimeBar phase={phase} /></>);
}

/** Timing ring: press Space (or click) while the marker is inside the violet zone. Score = average accuracy. */
function TimingChallenge({ phase, onDone }: { phase: Working; onDone: (s: number) => void }) {
  const [angle, setAngle] = useState(0);
  const [zone, setZone] = useState(() => 60 + Math.random() * 240);
  const [hits, setHits] = useState<number[]>([]);
  const [flash, setFlash] = useState<'hit' | 'miss' | null>(null);
  const reduced = typeof document !== 'undefined' && document.documentElement.classList.contains('dr-reduced');
  const speed = reduced ? 120 : 200; // degrees per second
  useEffect(() => {
    let raf = 0; let last = performance.now();
    const tick = (t: number) => { setAngle((a) => (a + ((t - last) / 1000) * speed) % 360); last = t; raf = requestAnimationFrame(tick); };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [speed]);
  const ZONE = 50;
  const press = useCallback(() => {
    const diff = Math.abs(((angle - zone + 540) % 360) - 180);
    const inZone = diff <= ZONE / 2;
    const acc = inZone ? 1 - diff / (ZONE / 2) * 0.5 : 0;
    setHits((h) => [...h.slice(-9), acc]);
    setFlash(inZone ? 'hit' : 'miss');
    window.setTimeout(() => setFlash(null), 250);
    setZone(60 + Math.random() * 240);
  }, [angle, zone]);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.code === 'Space') { e.preventDefault(); press(); } };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [press]);
  const score = useMemo(() => () => (hits.length === 0 ? 0.5 : hits.reduce((a, b) => a + b, 0) / hits.length), [hits]);
  useFinishAt(phase, score, onDone);
  const r = 70, c = 2 * Math.PI * r;
  return (
    <>
      <div className="dr-section-title">Stop the marker in the zone</div>
      <button className={`dr-ring ${flash ?? ''}`} onClick={press} aria-label="Press to stop the marker (Space)">
        <svg viewBox="0 0 180 180" width="180" height="180" aria-hidden="true">
          <circle cx="90" cy="90" r={r} className="track" />
          <circle cx="90" cy="90" r={r} className="zone" strokeDasharray={`${(ZONE / 360) * c} ${c}`} transform={`rotate(${zone - ZONE / 2 - 90} 90 90)`} />
          <line x1="90" y1="90" x2="90" y2="16" className="marker" transform={`rotate(${angle} 90 90)`} />
        </svg>
        <span className="dr-ring-label">Space</span>
      </button>
      <div className="v-muted">Accuracy so far: {Math.round(score() * 100)}% · {hits.length} tries</div>
      <TimeBar phase={phase} />
    </>
  );
}

/** Calibration: hold Space (or the button) to push the needle up; keep it inside the band as it drifts. */
function CalibrationChallenge({ phase, onDone }: { phase: Working; onDone: (s: number) => void }) {
  const [value, setValue] = useState(50);
  const [band, setBand] = useState(55);
  const held = useRef(false);
  const inside = useRef(0); const total = useRef(0);
  useEffect(() => {
    let raf = 0; let last = performance.now(); let t0 = last;
    const tick = (t: number) => {
      const dt = (t - last) / 1000; last = t;
      setValue((v) => Math.max(0, Math.min(100, v + (held.current ? 45 : -35) * dt)));
      setBand(50 + Math.sin((t - t0) / 1600) * 25);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    const down = (e: KeyboardEvent) => { if (e.code === 'Space') { e.preventDefault(); held.current = true; } };
    const up = (e: KeyboardEvent) => { if (e.code === 'Space') held.current = false; };
    window.addEventListener('keydown', down); window.addEventListener('keyup', up);
    return () => { cancelAnimationFrame(raf); window.removeEventListener('keydown', down); window.removeEventListener('keyup', up); };
  }, []);
  useEffect(() => { total.current += 1; if (Math.abs(value - band) <= 10) inside.current += 1; }, [value, band]);
  useFinishAt(phase, () => (total.current ? inside.current / total.current : 0.5), onDone);
  return (
    <>
      <div className="dr-section-title">Keep the needle in the band</div>
      <div className="dr-gauge" role="img" aria-label="Calibration gauge">
        <span className="band" style={{ bottom: `${band - 10}%` }} />
        <span className={`needle${Math.abs(value - band) <= 10 ? ' in' : ''}`} style={{ bottom: `${value}%` }} />
      </div>
      <button className="v-btn" onMouseDown={() => { held.current = true; }} onMouseUp={() => { held.current = false; }} onMouseLeave={() => { held.current = false; }}>
        Hold Space (or this button) to raise
      </button>
      <TimeBar phase={phase} />
    </>
  );
}
