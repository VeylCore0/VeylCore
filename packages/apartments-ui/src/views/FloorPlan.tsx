/**
 * Floor plan of the Starlite room, drawn from the MLO's own geometry (zydrec_sm_interior.ytyp):
 * room 8.95 m x 5.61 m, door on the front wall at y = -1.707, front window at y = 0.942, back window at y = 0.154.
 * Local +X (front, walkway) is drawn at the bottom.
 */
const B = { minX: -4.518, maxX: 4.436, minY: -2.65, maxY: 2.957 };
const S = 30; // px per metre
const W = (B.maxY - B.minY) * S;
const H = (B.maxX - B.minX) * S;
const px = (y: number) => (y - B.minY) * S;          // local Y -> svg x
const py = (x: number) => (B.maxX - x) * S;          // local X -> svg y (front at the bottom)

export function FloorPlan({ pieces = [], compact }: { pieces?: { x: number; y: number; label?: string }[]; compact?: boolean }) {
  return (
    <svg className={`apt-plan${compact ? ' compact' : ''}`} viewBox={`-16 -16 ${W + 32} ${H + 46}`} role="img" aria-label="Floor plan, 9 by 5.6 metres">
      <defs>
        <pattern id="apt-grid" width={S} height={S} patternUnits="userSpaceOnUse"><path d={`M ${S} 0 L 0 0 0 ${S}`} fill="none" stroke="rgba(255,255,255,0.05)" strokeWidth="1" /></pattern>
      </defs>
      <rect x="0" y="0" width={W} height={H} rx="4" fill="rgba(184,146,244,0.06)" />
      <rect x="0" y="0" width={W} height={H} rx="4" fill="url(#apt-grid)" />
      <rect x="0" y="0" width={W} height={H} rx="4" fill="none" stroke="rgba(244,241,250,0.75)" strokeWidth="3" />
      {/* back window */}
      <line x1={px(0.154) - 30} y1={0} x2={px(0.154) + 30} y2={0} stroke="#8fc7ff" strokeWidth="5" />
      {/* front window */}
      <line x1={px(0.942) - 32} y1={H} x2={px(0.942) + 32} y2={H} stroke="#8fc7ff" strokeWidth="5" />
      {/* door + swing */}
      <line x1={px(-1.707) - 14} y1={H} x2={px(-1.707) + 14} y2={H} stroke="#1a1624" strokeWidth="6" />
      <path d={`M ${px(-1.707) - 14} ${H} A 28 28 0 0 1 ${px(-1.707) + 14} ${H - 28}`} fill="none" stroke="#b892f4" strokeWidth="1.5" strokeDasharray="3 3" />
      {pieces.map((p, i) => <circle key={i} cx={px(p.y)} cy={py(p.x)} r="6" fill="#b892f4" opacity="0.85"><title>{p.label}</title></circle>)}
      <text x={W / 2} y={H + 22} textAnchor="middle" fill="rgba(244,241,250,0.6)" fontSize="11">Door · walkway</text>
      <text x={W / 2} y={-5} textAnchor="middle" fill="rgba(244,241,250,0.45)" fontSize="10">5.6 m</text>
      <text x={W + 6} y={H / 2} fill="rgba(244,241,250,0.45)" fontSize="10" transform={`rotate(90 ${W + 6} ${H / 2})`} textAnchor="middle">9.0 m</text>
    </svg>
  );
}
