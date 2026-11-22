import { useCallback, useEffect, useRef, useState } from 'react';
import { Glyph, type UIConfig } from './glyphs';

export interface Note {
  id: string; type: 'info' | 'success' | 'warning' | 'error'; title?: string; description?: string; icon?: string; duration: number;
  layout: 'standard' | 'compact' | 'payment'; amount?: number | string; sound?: boolean; showDuration?: boolean; autoId?: boolean;
}
interface Card extends Note { count: number; startedAt: number; leaving?: boolean; key: number }

const TONE: Record<Note['type'], number[]> = { success: [660, 880], info: [620], warning: [520, 440], error: [330, 260] };
let audio: AudioContext | null = null;
function chime(type: Note['type'], volume: number) {
  if (volume <= 0) return;
  try {
    audio ??= new AudioContext();
    TONE[type].forEach((f, i) => {
      const o = audio!.createOscillator(), g = audio!.createGain(), t = audio!.currentTime + i * 0.09;
      o.type = 'sine'; o.frequency.value = f;
      g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(volume * 0.18, t + 0.015); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.22);
      o.connect(g).connect(audio!.destination); o.start(t); o.stop(t + 0.25);
    });
  } catch { /* audio unavailable: silent */ }
}
const sameContent = (a: Note, b: Note) => a.type === b.type && (a.title ?? '') === (b.title ?? '') && (a.description ?? '') === (b.description ?? '') && String(a.amount ?? '') === String(b.amount ?? '');
const money = (v: number | string) => (typeof v === 'number' ? `${v < 0 ? '−' : '+'}$${Math.abs(v).toLocaleString('en-US')}` : v);

/** Upper-right stack: at most maxVisible cards; the rest wait in a bounded queue. */
export function useNotifications(cfg: UIConfig['Notifications'] | undefined) {
  const [cards, setCards] = useState<Card[]>([]);
  const queue = useRef<Note[]>([]);
  const timers = useRef(new Map<string, number>());
  const seq = useRef(0);
  const max = cfg?.maxVisible ?? 4;

  const clearTimer = (id: string) => { const t = timers.current.get(id); if (t) window.clearTimeout(t); timers.current.delete(id); };
  const leave = useCallback((id: string) => {
    clearTimer(id);
    setCards((l) => l.map((c) => (c.id === id ? { ...c, leaving: true } : c)));
    window.setTimeout(() => setCards((l) => l.filter((c) => c.id !== id || !c.leaving)), 260);
  }, []);
  const arm = useCallback((id: string, ms: number) => { clearTimer(id); timers.current.set(id, window.setTimeout(() => leave(id), ms)); }, [leave]);

  // Pull queued messages into free slots.
  useEffect(() => {
    const live = cards.filter((c) => !c.leaving).length;
    if (live >= max || queue.current.length === 0) return;
    const add = queue.current.splice(0, max - live).map((n) => ({ ...n, count: 1, startedAt: performance.now(), key: ++seq.current }));
    add.forEach((n) => { arm(n.id, n.duration); if (n.sound !== false && cfg?.sound) chime(n.type, cfg.volume); });
    setCards((l) => [...l, ...add]);
  }, [cards, max, arm, cfg]);

  const push = useCallback((n: Note) => {
    setCards((l) => {
      // Merge: same id, or (duplicates = 'merge') identical content for auto ids.
      const hit = l.find((c) => !c.leaving && (c.id === n.id || (n.autoId && cfg?.duplicates !== 'stack' && sameContent(c, n))));
      if (hit) {
        const restart = cfg?.restartOnUpdate !== false;
        if (restart) arm(hit.id, n.duration);
        return l.map((c) => (c === hit ? { ...c, ...n, id: hit.id, count: c.count + 1, startedAt: restart ? performance.now() : c.startedAt, key: restart ? ++seq.current : c.key } : c));
      }
      const q = queue.current.find((x) => x.id === n.id || (n.autoId && cfg?.duplicates !== 'stack' && sameContent(x, n)));
      if (q) { Object.assign(q, n, { id: q.id }); return l; }
      queue.current.push(n);
      if (queue.current.length > (cfg?.maxQueue ?? 20)) queue.current.shift();
      return [...l]; // triggers the pull effect
    });
  }, [arm, cfg]);

  const update = useCallback((n: Partial<Note> & { id: string }) => {
    const clean = Object.fromEntries(Object.entries(n).filter(([, v]) => v !== undefined && v !== null)) as Partial<Note> & { id: string };
    setCards((l) => l.map((c) => {
      if (c.id !== n.id) return c;
      const restart = cfg?.restartOnUpdate !== false;
      if (restart) arm(c.id, clean.duration ?? c.duration);
      return { ...c, ...clean, startedAt: restart ? performance.now() : c.startedAt, key: restart ? ++seq.current : c.key };
    }));
    const q = queue.current.find((x) => x.id === n.id);
    if (q) Object.assign(q, clean);
  }, [arm, cfg]);

  const dismiss = useCallback((id: string) => { queue.current = queue.current.filter((x) => x.id !== id); leave(id); }, [leave]);
  const dismissNewest = useCallback(() => setCards((l) => { const last = [...l].reverse().find((c) => !c.leaving); if (last) leave(last.id); return l; }), [leave]);
  const clear = useCallback(() => { queue.current = []; timers.current.forEach((t) => window.clearTimeout(t)); timers.current.clear(); setCards([]); }, []);
  useEffect(() => () => { timers.current.forEach((t) => window.clearTimeout(t)); }, []);
  return { cards, push, update, dismiss, dismissNewest, clear };
}

export function Notifications({ cards, cfg, interactive, onClose }: { cards: Card[]; cfg?: UIConfig['Notifications']; interactive: boolean; onClose: (id: string) => void }) {
  if (!cards.length) return null;
  const pos = cfg?.position ?? 'top-right';
  const style: React.CSSProperties = { top: `${cfg?.offsetY ?? 3}vh`, width: `${cfg?.width ?? 23}rem` };
  if (pos === 'center-right' || pos === 'center-left') {
    // Vertically centred on the screen edge (offsetY nudges it up / down from the middle).
    style.top = `calc(50% + ${cfg?.offsetY ?? 0}vh)`;
    style.transform = 'translateY(-50%)';
    if (pos === 'center-left') style.left = `${cfg?.offsetX ?? 1.6}vw`; else style.right = `${cfg?.offsetX ?? 1.6}vw`;
  } else if (pos === 'top-left') style.left = `${cfg?.offsetX ?? 1.6}vw`;
  else if (pos === 'top-center') { style.left = '50%'; style.transform = 'translateX(-50%)'; }
  else style.right = `${cfg?.offsetX ?? 1.6}vw`;
  return (
    <div className="vn-stack" style={style} aria-live="polite">
      {cards.map((c) => (
        <div key={c.id} className={`vn-card ${c.type} ${c.layout}${c.leaving ? ' out' : ''}`} role={c.type === 'error' ? 'alert' : 'status'}>
          <span className="vn-icon" aria-hidden><Glyph name={c.icon ?? c.type} /></span>
          <div className="vn-body">
            {c.layout === 'payment' ? (
              <div className="vn-row"><span className="vn-title">{c.title ?? c.description}</span>{c.amount !== undefined && <span className="vn-amount">{money(c.amount)}</span>}</div>
            ) : c.layout === 'compact' ? (
              <div className="vn-row"><span className="vn-title one">{c.title ?? c.description}</span>{c.count > 1 && <span className="vn-count">×{c.count}</span>}</div>
            ) : (
              <>
                <div className="vn-row"><span className="vn-title">{c.title}</span>{c.count > 1 && <span className="vn-count">×{c.count}</span>}<span className="vn-time">Now</span></div>
                {c.description && <div className="vn-desc">{c.description}</div>}
              </>
            )}
            {c.layout !== 'payment' && c.showDuration !== false && (
              <div className="vn-line"><i key={c.key} style={{ animationDuration: `${c.duration}ms` }} /></div>
            )}
          </div>
          {interactive && <button className="vn-close" aria-label="Dismiss" onClick={() => onClose(c.id)}><Glyph name="close" /></button>}
        </div>
      ))}
    </div>
  );
}
