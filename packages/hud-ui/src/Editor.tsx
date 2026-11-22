import { useEffect, useRef, useState } from 'react';
import { Icon } from '@veyl/ui';
import type { GroupKey, Layout, Settings } from './types';

// Position editor: drag the HUD groups (and the minimap). Positions are stored as fractions of the screen, so they
// survive resolution changes; everything is clamped to the safe area. The minimap moves the native GTA radar.
const LABELS: Record<GroupKey | 'minimap', string> = {
  minimap: 'Minimap', status: 'Status', voice: 'Voice', vehicle: 'Vehicle instruments', info: 'Top-right info', location: 'Location strip',
};
const GRID = 0.005; // snap step (0.5 % of the screen)

export function Editor({ s, layout, onPreview, onDone }: { s: Settings; layout: Layout; onPreview: (d: Settings) => void; onDone: (next: Settings | null) => void }) {
  const [draft, setDraft] = useState<Settings>(() => JSON.parse(JSON.stringify(s)));
  const [snap, setSnap] = useState(s.snap);
  const [selected, setSelected] = useState<GroupKey | 'minimap' | null>(null);
  const drag = useRef<{ key: GroupKey | 'minimap'; dx: number; dy: number; startX: number; startY: number; base: { x: number; y: number } } | null>(null);
  const [, force] = useState(0);
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
  };

  const onMove = (e: React.PointerEvent) => {
    const d = drag.current;
    if (!d) return;
    const W = window.innerWidth, H = window.innerHeight;
    if (d.key === 'minimap') {
      // Native radar offsets are in 16:9 screen units horizontally; vertical offset moves up.
      const xk = (16 / 9) / (W / H);
      const ox = d.base.x + (e.clientX - d.startX) / W / xk;
      const oy = d.base.y - (e.clientY - d.startY) / H;
      const r = (v: number) => (snap ? Math.round(v / GRID) * GRID : v);
      setDraft((cur) => ({ ...cur, minimap: { ...cur.minimap, offsetX: Math.max(-0.3, Math.min(0.6, r(ox))), offsetY: Math.max(-0.6, Math.min(0.3, r(oy))) } }));
      return;
    }
    const b = box(d.key);
    const p = clampSnap((e.clientX - d.dx) / W, (e.clientY - d.dy) / H, b?.width ?? 0, b?.height ?? 0);
    setDraft((cur) => ({ ...cur, positions: { ...cur.positions, [d.key]: p } }));
  };

  const onUp = () => { drag.current = null; force((n) => n + 1); };

  // Apply the draft live to the HUD underneath (and the native minimap, through the preview callback).
  const first = useRef(true);
  useEffect(() => {
    if (first.current) { first.current = false; return; }
    onPreview(draft);
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
        const b = box(k);
        if (!b) return null;
        return (
          <div key={k} className={`handle${selected === k ? ' sel' : ''}`} style={{ left: b.left, top: b.top, width: Math.max(b.width, 40), height: Math.max(b.height, 24) }}
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
