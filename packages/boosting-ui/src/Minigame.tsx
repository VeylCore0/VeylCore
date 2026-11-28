// The access puzzle ("signal sync"): watch the symbols, repeat them. The server holds the sequences and checks every answer and its
// timing; this page only shows them and sends back what the player typed.
import { useCallback, useEffect, useRef, useState } from 'react';
import { nui } from '@veyl/ui';
import type { MinigameStage } from './types';
import { Bar, Ico, api, cx } from './ui';

const SHAPES: Record<number, JSX.Element> = {
  1: <path d="M12 4l9 15H3z" />,
  2: <rect x="5" y="5" width="14" height="14" rx="2" />,
  3: <circle cx="12" cy="12" r="7.5" />,
  4: <path d="M12 3l9 9-9 9-9-9z" />,
  5: <path d="M12 3l8 4.5v9L12 21l-8-4.5v-9z" />,
  6: <path d="M13 3L5 13h6l-1 8 8-10h-6z" />,
};
const COLORS = ['#8b5fd6', '#3f8bff', '#34d27b', '#f2b443', '#ef7a3a', '#e05fb0'];

function Glyph({ n, size = 44, active }: { n: number; size?: number; active?: boolean }) {
  return (
    <svg className={cx('bst-glyph', active && 'on')} width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={COLORS[(n - 1) % COLORS.length]} strokeWidth="1.8" strokeLinejoin="round" aria-hidden="true">
      {SHAPES[n] ?? SHAPES[3]}
    </svg>
  );
}

type Phase = 'show' | 'input' | 'sending';

export function Minigame({ first }: { first: MinigameStage }) {
  const [st, setSt] = useState(first);
  const [phase, setPhase] = useState<Phase>('show');
  const [shown, setShown] = useState(-1);
  const [input, setInput] = useState<number[]>([]);
  const [left, setLeft] = useState(1);
  const [flash, setFlash] = useState<'good' | 'bad' | null>(null);
  const [text, setText] = useState('Watch the signal');
  const busy = useRef(false);
  const startedAt = useRef(0);
  const sentAt = useRef(0);

  const finish = useCallback((result: 'success' | 'failed' | 'cancel', message?: string) => {
    void nui('minigameDone', { result, message });
  }, []);

  // Show the sequence one symbol at a time, then open the input.
  useEffect(() => {
    setPhase('show'); setInput([]); setShown(-1); setText('Watch the signal'); busy.current = false;
    const step = st.showMs / st.seq.length;
    const timers: number[] = [];
    st.seq.forEach((_, i) => timers.push(window.setTimeout(() => setShown(i), 250 + i * step * 0.9)));
    timers.push(window.setTimeout(() => setShown(-1), 250 + st.seq.length * step * 0.9 + 80));
    timers.push(window.setTimeout(() => { setPhase('input'); setText('Repeat the sequence'); startedAt.current = Date.now(); }, Math.max(st.showMs, 250 + st.seq.length * step * 0.9 + 200)));
    return () => timers.forEach((t) => window.clearTimeout(t));
  }, [st]);

  // Time to answer.
  useEffect(() => {
    if (phase !== 'input') return;
    const t = window.setInterval(() => {
      const used = Date.now() - startedAt.current;
      setLeft(Math.max(0, 1 - used / st.maxInputMs));
    }, 100);
    return () => window.clearInterval(t);
  }, [phase, st]);

  const submit = useCallback(async (answer: number[]) => {
    if (busy.current) return;
    busy.current = true;
    setPhase('sending');
    sentAt.current = Date.now();
    const r = await api<{ result: 'next' | 'retry' | 'success' | 'failed'; stage?: MinigameStage }>('accessSubmit', st.token, answer);
    if (!r.ok || !r.data) { setFlash('bad'); setText(r.message ?? 'Lost the signal'); window.setTimeout(() => finish('failed', r.message ?? 'Lost the signal'), 700); return; }
    const d = r.data;
    if (d.result === 'success') { setFlash('good'); setText('Access granted'); window.setTimeout(() => finish('success', r.message ?? 'Unlocked'), 700); return; }
    if (d.result === 'failed') { setFlash('bad'); setText('Signal lost'); window.setTimeout(() => finish('failed', r.message ?? 'The signal dropped'), 800); return; }
    setFlash(d.result === 'next' ? 'good' : 'bad');
    window.setTimeout(() => setFlash(null), 450);
    if (d.stage) window.setTimeout(() => setSt(d.stage as MinigameStage), 500);
  }, [st, finish]);

  // Out of time counts as a wrong answer (sending nothing useful).
  useEffect(() => {
    if (phase === 'input' && left <= 0) void submit(Array(st.seq.length).fill(0));
  }, [left, phase, st, submit]);

  const press = useCallback((n: number) => {
    if (phase !== 'input') return;
    setInput((cur) => {
      if (cur.length >= st.seq.length) return cur;
      const next = [...cur, n];
      if (next.length === st.seq.length) window.setTimeout(() => void submit(next), 120);
      return next;
    });
  }, [phase, st, submit]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') { e.preventDefault(); finish('cancel'); return; }
      if (e.key === 'Backspace') { setInput((cur) => cur.slice(0, -1)); return; }
      const n = Number(e.key);
      if (n >= 1 && n <= st.glyphs) press(n);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [finish, press, st.glyphs]);

  return (
    <div className="bst-mg-bg">
      <div className={cx('bst-mg', flash)} role="dialog" aria-label="Signal sync">
        <header>
          <span className="bst-mg-title"><Ico name="lock" size={16} />SIGNAL SYNC</span>
          <span className="bst-mg-stage">Stage {st.stage} / {st.stages}</span>
          <span className="bst-mg-strikes" aria-label={`${st.strikes} of ${st.maxStrikes} strikes`}>{Array.from({ length: st.maxStrikes }, (_, i) => <i key={i} className={i < st.strikes ? 'on' : ''} />)}</span>
        </header>
        <div className="bst-mg-screen">
          {st.seq.map((n, i) => (
            <span key={i} className={cx('bst-mg-slot', shown === i && 'lit', input[i] !== undefined && 'filled')}>
              {phase === 'show' ? (shown === i ? <Glyph n={n} size={52} active /> : <span className="dot" />) : input[i] !== undefined ? <Glyph n={input[i]} size={46} /> : <span className="dot" />}
            </span>
          ))}
        </div>
        <p className="bst-mg-text">{text}</p>
        {phase === 'input' && <Bar value={left} className="bst-mg-time" label="Time to answer" />}
        <div className={cx('bst-mg-pad', phase !== 'input' && 'off')}>
          {Array.from({ length: st.glyphs }, (_, i) => i + 1).map((n) => (
            <button key={n} onClick={() => press(n)} disabled={phase !== 'input'} aria-label={`Symbol ${n}`}><Glyph n={n} /><kbd>{n}</kbd></button>
          ))}
        </div>
        <footer><span>Backspace undoes · ESC leaves</span></footer>
      </div>
    </div>
  );
}
