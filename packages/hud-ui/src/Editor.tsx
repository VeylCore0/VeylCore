import { useEffect, useRef, useState } from 'react';

type Live = { key: GroupKey | 'minimap'; left0: number; top0: number; left: number; top: number; w: number; h: number };
import { Icon } from '@veyl/ui';
import type { GroupKey, Layout, Settings } from './types';

// Position editor: drag the HUD groups (and the minimap). Positions are stored as fractions of the screen, so they
// survive resolution changes; everything is clamped to the safe area. The minimap moves the native GTA radar.
const LABELS: Record<GroupKey | 'minimap', string> = {
  minimap: 'Minimap', status: 'Status', voice: 'Voice', vehicle: 'Vehicle instruments', info: 'Top-right info', location: 'Location strip',
};
const GRID = 0.005; // snap step (0.5 % of the screen)

export function Editor({ s, layout, onPreview, onDone }: { s: Settings; layout: Layout; onPreview: (d: Settings, moving?: boolean) => void; onDone: (next: Settings | null) => void }) {
  const [draft, setDraft] = useState<Settings>(() => JSON.parse(JSON.stringify(s)));
  const [snap, setSnap] = useState(s.snap);
  const [selected, setSelected] = useState<GroupKey | 'minimap' | null>(null);
  const drag = useRef<{ key: GroupKey | 'minimap'; dx: number; dy: number; startX: number; startY: number; base: { x: number; y: number } } | null>(null);
  const [, force] = useState(0);
  const [live, setLive] = useState<Live | null>(null);
  const frameReq = useRef<number | null>(null);
  const lastEv = useRef<{ x: number; y: number } | null>(null);
  const moving = useRef(false);
  const safe = layout.safe;

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); onDone(null); } };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, [onDone]);

  // Current box of each group from the live DOM (the HUD keeps rendering underneath).
  const box = (key: GroupKey | 'minimap') => {
    const el = document.querySelector(key === 'minimap' ? '.mm-frame' : `[data-group="${key}"]`) as HTMLElement | null;
    return el ? el.getBoundingClientRect() : null;
  };

  const clampSnap = (x: number, y: number, w: number, h: number) => {
    const W = window.innerWidth, H = window.innerHeight;
    let nx = Math.max(safe, Math.min(1 - safe - w / W, x));
    let ny = Math.max(safe, Math.min(1 - safe - h / H, y));
    if (snap) { nx = Math.round(nx / GRID) * GRID; ny = Math.round(ny / GRID) * GRID; }
    return { x: nx, y: ny };
  };

  const onDown = (key: GroupKey | 'minimap', e: React.PointerEvent) => {
    const b = box(key);
    if (!b) return;
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
    setSelected(key);
    drag.current = { key, dx: e.clientX - b.left, dy: e.clientY - b.top, startX: e.clientX, startY: e.clientY,
      base: key === 'minimap' ? { x: draft.minimap.offsetX, y: draft.minimap.offsetY } : { x: b.left / window.innerWidth, y: b.top / window.innerHeight } };
    setLive({ key, left0: b.left, top0: b.top, left: b.left, top: b.top, w: b.width, h: b.height });
  };

  // Pointer moves are coalesced to one update per animation frame; the dragged handle follows the pointer directly.
  const step = () => {
    frameReq.current = null;
    const d = drag.current, ev = lastEv.current, l = live;
    if (!d || !ev || !l) return;
    const W = window.innerWidth, H = window.innerHeight;
    moving.current = true;
    if (d.key === 'minimap') {
      // Native radar offsets are in 16:9 screen units horizontally; vertical offset moves up.
      const xk = (16 / 9) / (W / H);
      const r = (v: number) => (snap ? Math.round(v / GRID) * GRID : v);
      const ox = Math.max(-0.3, Math.min(0.6, r(d.base.x + (ev.x - d.startX) / W / xk)));
      const oy = Math.max(-0.6, Math.min(0.3, r(d.base.y - (ev.y - d.startY) / H)));
      setLive({ ...l, left: l.left0 + (ox - d.base.x) * xk * W, top: l.top0 - (oy - d.base.y) * H });
      setDraft((cur) => ({ ...cur, minimap: { ...cur.minimap, offsetX: ox, offsetY: oy } }));
      return;
    }
    const p = clampSnap((ev.x - d.dx) / W, (ev.y - d.dy) / H, l.w, l.h);
    setLive({ ...l, left: p.x * W, top: p.y * H });
    setDraft((cur) => ({ ...cur, positions: { ...cur.positions, [d.key]: p } }));
  };
  const stepRef = useRef(step);
  stepRef.current = step;

  const onMove = (e: React.PointerEvent) => {
    if (!drag.current) return;
    lastEv.current = { x: e.clientX, y: e.clientY };
    if (frameReq.current === null) frameReq.current = window.requestAnimationFrame(() => stepRef.current());
  };

  const onUp = () => {
    if (!drag.current) return;
    if (frameReq.current !== null) { window.cancelAnimationFrame(frameReq.current); stepRef.current(); }
    drag.current = null;
    lastEv.current = null;
    moving.current = false;
    setLive(null);
    setDraft((cur) => ({ ...cur })); // one last preview that is not "moving": GTA does a full refresh at the resting place
    force((n) => n + 1);
  };
  useEffect(() => () => { if (frameReq.current !== null) window.cancelAnimationFrame(frameReq.current); }, []);

  // Apply the draft live to the HUD underneath (and the native minimap, through the preview callback).
  const first = useRef(true);
  useEffect(() => {
    if (first.current) { first.current = false; return; }
    onPreview(draft, moving.current);
  }, [draft, onPreview]);

  const resetSelected = () => {
    if (!selected) return;
    if (selected === 'minimap') setDraft((cur) => ({ ...cur, minimap: { ...cur.minimap, offsetX: 0, offsetY: 0 } }));
    else setDraft((cur) => { const positions = { ...cur.positions }; delete positions[selected]; return { ...cur, positions }; });
  };

  const keys: (GroupKey | 'minimap')[] = ['minimap', 'location', 'status', 'voice', 'info', 'vehicle'];
  return (
    <div className="editor" onPointerMove={onMove} onPointerUp={onUp}>
      <div className="safe-guide" style={{ inset: `${safe * 100}vh ${safe * 100}vw` }} />
      {keys.map((k) => {
        const dom = box(k);
        if (!dom) return null;
        const b = live && live.key === k ? { left: live.left, top: live.top, width: live.w, height: live.h } : dom;
        return (
          <div key={k} className={`handle${selected === k ? ' sel' : ''}${live?.key === k ? ' dragging' : ''}`} style={{ left: b.left, top: b.top, width: Math.max(b.width, 40), height: Math.max(b.height, 24) }}
            onPointerDown={(e) => onDown(k, e)}>
            <span>{LABELS[k]}</span>
          </div>
        );
      })}
      <div className="editor-bar">
        <b><Icon name="hand" size="1rem" /> Drag to move</b>
        <label className="snap"><input type="checkbox" checked={snap} onChange={(e) => { setSnap(e.target.checked); setDraft((c) => ({ ...c, snap: e.target.checked })); }} /> Snap</label>
        <button className="ghost" disabled={!selected} onClick={resetSelected}>Reset {selected ? LABELS[selected] : 'position'}</button>
        <button className="ghost" onClick={() => onDone(null)}>Cancel</button>
        <button className="primary" onClick={() => onDone(draft)}>Save positions</button>
      </div>
    </div>
  );
}
