// An original X-ray style figure for the body panel: a glassy silhouette with a skeleton inside it. Drawn as vector paths (no image).
type P = [number, number];

/** Catmull-Rom through the points, as one smooth cubic path. */
const smooth = (p: P[]) => {
  let d = `M${p[0][0]} ${p[0][1]}`;
  for (let i = 0; i < p.length - 1; i++) {
    const p0 = p[i - 1] ?? p[i], p1 = p[i], p2 = p[i + 1], p3 = p[i + 2] ?? p2;
    const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6];
    const c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6];
    d += ` C${c1[0].toFixed(1)} ${c1[1].toFixed(1)} ${c2[0].toFixed(1)} ${c2[1].toFixed(1)} ${p2[0]} ${p2[1]}`;
  }
  return d;
};

// The right half of the outline from the top of the head to the crotch; the left half is its mirror.
const HALF: P[] = [
  [100, 3], [112, 7], [118, 19], [118, 36], [113, 50], [108, 58], [107, 67], [108, 78],
  [124, 84], [142, 88], [158, 94], [168, 106],
  [171, 126], [175, 152], [179, 176], [183, 204], [187, 236], [191, 258], [190, 270], [183, 270], [179, 252],
  [174, 228], [168, 200], [162, 172], [158, 148], [153, 130],
  [147, 138], [143, 162], [139, 190], [138, 214], [145, 238], [148, 262], [148, 296], [145, 330], [141, 358], [140, 380], [139, 410], [140, 440], [136, 470], [134, 492], [140, 506], [139, 514],
  [121, 514], [113, 507], [112, 490], [112, 462], [110, 430], [108, 400], [108, 372], [108, 340], [106, 300], [104, 272], [100, 262],
];
const FULL: P[] = [...HALF, ...HALF.slice(0, -1).reverse().map(([x, y]): P => [200 - x, y]).slice(0, -1)];
const OUTLINE = smooth(FULL) + ' Z';

const SPINE = Array.from({ length: 20 }, (_, i) => 70 + i * 8.6);
const RIBS = Array.from({ length: 9 }, (_, i) => ({ y: 98 + i * 8.2, reach: 25 + 15 * Math.sin((i / 8) * Math.PI * 0.85) }));

/** The skeleton parts that sit on the right side; drawn again mirrored for the left. */
function Side() {
  return (
    <g>
      {RIBS.map((r, i) => (
        <path key={i} d={`M101 ${r.y} q ${r.reach * 0.55} -9 ${r.reach} 6 q ${-r.reach * 0.2} 12 ${-r.reach * 0.88} 15`} />
      ))}
      <path d="M100 90 Q122 82 150 96" strokeWidth="2.4" />
      <ellipse cx="146" cy="116" rx="9" ry="16" transform="rotate(-12 146 116)" opacity=".4" />
      <circle cx="152" cy="100" r="5.5" />
      <path className="bone" d="M152 104 L173 176" />
      <path className="bone thin" d="M174 180 L187 246" /><path className="bone thin" d="M177 178 L191 242" />
      <circle cx="174" cy="178" r="4" />
      <path d="M187 248 L190 270 M190 247 L195 266 M184 248 L184 268 M193 244 L199 258" strokeWidth="1.3" />
      <path d="M104 226 C118 218 134 222 140 236 C144 250 132 262 116 258 L106 268" />
      <circle cx="126" cy="256" r="7.5" />
      <path className="bone" d="M128 262 L132 356" />
      <circle cx="132" cy="364" r="5.5" opacity=".7" />
      <path className="bone" d="M130 372 L128 474" />
      <path className="bone thin" d="M139 378 L136 468" />
      <circle cx="129" cy="478" r="4.5" />
      <path d="M126 482 L132 512 M130 482 L140 510 M134 480 L144 506" strokeWidth="1.4" />
    </g>
  );
}

export function Figure() {
  return (
    <svg className="body-figure" viewBox="0 0 200 520" preserveAspectRatio="xMidYMid meet" aria-hidden="true">
      <defs>
        <linearGradient id="fig-skin" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#e6efec" stopOpacity=".5" /><stop offset=".55" stopColor="#9fb0ac" stopOpacity=".3" /><stop offset="1" stopColor="#53615e" stopOpacity=".22" />
        </linearGradient>
        <radialGradient id="fig-core" cx=".5" cy=".35" r=".6"><stop offset="0" stopColor="#ffffff" stopOpacity=".16" /><stop offset="1" stopColor="#ffffff" stopOpacity="0" /></radialGradient>
        <filter id="fig-glow" x="-20%" y="-10%" width="140%" height="120%"><feGaussianBlur stdDeviation="3" result="b" /><feMerge><feMergeNode in="b" /><feMergeNode in="SourceGraphic" /></feMerge></filter>
      </defs>
      <g transform="rotate(-1.5 100 260)">
        <path d={OUTLINE} fill="url(#fig-skin)" stroke="#cfdcd8" strokeOpacity=".9" strokeWidth="2" filter="url(#fig-glow)" />
        <path d={OUTLINE} fill="url(#fig-core)" stroke="none" />
        <g fill="none" stroke="#dbe7e4" strokeOpacity=".62" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className="bones">
          {/* skull */}
          <ellipse cx="100" cy="30" rx="14" ry="18" />
          <ellipse cx="94" cy="28" rx="4" ry="3.4" /><ellipse cx="106" cy="28" rx="4" ry="3.4" />
          <path d="M100 32 L98 40 L102 40 Z M92 46 Q100 51 108 46 M94 50 Q100 56 106 50" />
          <path d="M104 44 Q104 56 100 58 Q96 56 96 44" opacity=".6" />
          <path d="M96 62 L96 80 M104 62 L104 80" opacity=".5" />
          {/* spine and sternum */}
          {SPINE.map((y, i) => <rect key={i} x={100 - 3.4 - (i > 9 ? 0.4 : 0)} y={y} width={6.8 + (i > 9 ? 0.8 : 0)} height="5.6" rx="2" />)}
          <path d="M100 98 L100 148" strokeWidth="5" strokeOpacity=".4" />
          <path d="M96 150 L100 158 L104 150" />
          <Side />
          <g transform="translate(200 0) scale(-1 1)"><Side /></g>
          <path d="M94 238 L100 250 L106 238 M97 252 L100 262 L103 252" />
        </g>
      </g>
    </svg>
  );
}
