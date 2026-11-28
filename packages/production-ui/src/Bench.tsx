import { useState } from 'react';
import type { Bench } from './types';
import { nui } from '@veyl/ui';
import { Bar, Button, Chip, Confirm, Empty, Ico, ItemImg, mmss, useClock } from './ui';

/** One workstation: its recipes and its queue. `act` is false when read-only (the tablet away from the bench). */
export function BenchPanel({ bench, labels, act, run }: { bench: Bench; labels: Record<string, string>; act: boolean; run?: (name: string, ...a: unknown[]) => Promise<unknown> }) {
  const now = useClock(bench.serverTime);
  const [confirm, setConfirm] = useState<{ kind: 'cancel' | 'pack'; id?: number } | null>(null);
  const ready = bench.batches.filter((b) => b.endsAt <= now).length;
  return (
    <div className="pr-bench">
      <div className="pr-bench-head">
        <div><h3>{bench.label}</h3><span className="pr-sub">{bench.property ? 'Laboratory bench' : 'Portable'} · queue {bench.batches.length}/{bench.slots}</span></div>
        {act && run && (
          <div className="pr-head-actions">
            <Button kind="primary" disabled={ready === 0} onClick={() => void run('wsClaim', bench.id)}><Ico name="check" size={16} />Collect{ready > 0 ? ` (${ready})` : ''}</Button>
            <Button kind="ghost" onClick={() => setConfirm({ kind: 'pack' })}>Pack up</Button>
          </div>
        )}
      </div>

      <h4 className="pr-h">QUEUE</h4>
      {bench.batches.length === 0 ? <Empty icon="box" title="Nothing queued" text={act ? 'Start a recipe below.' : 'Go to the bench to start a batch.'} /> : (
        <ul className="pr-batches">
          {bench.batches.map((b) => {
            const left = b.endsAt - now;
            const state = left <= 0 ? 'done' : now >= b.startsAt ? 'running' : 'queued';
            const progress = state === 'done' ? 1 : state === 'running' ? (now - b.startsAt) / Math.max(1, b.endsAt - b.startsAt) : 0;
            return (
              <li key={b.id} className={state}>
                <ItemImg item={b.output?.item ?? 'prod_blend'} size={36} />
                <span className="pr-batch-main">
                  <strong>{b.label}</strong>
                  <em>{state === 'done' ? 'Ready to collect' : state === 'queued' ? `Starts in ${mmss(b.startsAt - now)}` : `${b.stage ?? 'Working'} · ${mmss(left)} left`}</em>
                  {b.tier && <Chip tone={b.quality >= 75 ? 'warn' : b.quality >= 50 ? 'ok' : 'mute'}>{b.tier} · {b.quality}</Chip>}
                  <Bar value={progress} label={`${b.label} progress`} />
                </span>
                {act && run && state !== 'done' && <Button kind="ghost" onClick={() => setConfirm({ kind: 'cancel', id: b.id })}>Cancel</Button>}
                {state === 'done' && <Chip tone="ok">Done</Chip>}
              </li>
            );
          })}
        </ul>
      )}

      <h4 className="pr-h">RECIPES</h4>
      <ul className="pr-recipes">
        {bench.recipes.map((r) => (
          <li key={r.id} className={r.locked ? 'locked' : ''}>
            <span className="pr-recipe-io">
              {r.inputs.map((i) => <span key={i.item} className="pr-io"><ItemImg item={i.item} size={30} /><b>{i.count}</b></span>)}
              <Ico name="arrow" size={16} />
              <span className="pr-io"><ItemImg item={r.output.item} size={30} /><b>{r.output.count}</b></span>
            </span>
            <span className="pr-recipe-main"><strong>{r.label}{r.skill ? <Chip tone="accent"><Ico name="bolt" size={11} />{r.skill} checks</Chip> : null}{r.hazard ? <Chip tone="warn"><Ico name="alert" size={11} />Hazard</Chip> : null}</strong><em>{r.inputs.map((i) => `${i.count} ${labels[i.item] ?? i.item}`).join(', ')} → {r.output.count} {labels[r.output.item] ?? r.output.item} · {mmss(r.seconds)}</em></span>
            {r.locked ? <Chip tone="warn"><Ico name="lock" size={12} />Level {r.level}</Chip>
              : act && run ? <Button kind="primary" disabled={bench.batches.length >= bench.slots} onClick={() => (r.skill ? void nui('skillStart', { id: bench.id, recipe: r.id }) : void run('wsStart', bench.id, r.id))}>{r.skill ? 'Start check' : 'Start'}</Button> : null}
          </li>
        ))}
      </ul>
      {confirm?.kind === 'cancel' && <Confirm danger title="Cancel this batch?" text="A batch that has not started gives everything back. One already running gives back half." confirm="Cancel batch" onCancel={() => setConfirm(null)} onConfirm={() => { const id = confirm.id; setConfirm(null); void run?.('wsCancel', bench.id, id); }} />}
      {confirm?.kind === 'pack' && <Confirm title="Pack up this workstation?" text="It goes back into your inventory. It must have no batches left." confirm="Pack up" onCancel={() => setConfirm(null)} onConfirm={() => { setConfirm(null); void run?.('wsPack', bench.id); }} />}
    </div>
  );
}
