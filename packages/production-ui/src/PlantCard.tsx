// Floating stat card over a plant: health, growth, water and nutrients as rings. Positioned by the game (screen fractions); the numbers come from the server.
import type { CSSProperties } from 'react';

export interface PlantCard { id: number; x: number; y: number; label: string; stage: number; stages: number; state: 'growing' | 'ready' | 'dead'; health: number; growth: number; water: number; nutrient: number }

const R = 26, CIRC = 2 * Math.PI * R;

function Dial({ value, color, label }: { value: number; color: string; label: string }) {
  const pct = Math.max(0, Math.min(100, Math.round(value)));
  return (
    <div className="pc-dial" style={{ '--c': color } as CSSProperties}>
      <svg viewBox="0 0 64 64" width="64" height="64" aria-hidden="true">
        <circle cx="32" cy="32" r={R} className="pc-track" />
        <circle cx="32" cy="32" r={R} className="pc-arc" strokeDasharray={CIRC} strokeDashoffset={CIRC * (1 - pct / 100)} transform="rotate(-90 32 32)" />
      </svg>
      <b>{pct}%</b>
      <small>{label}</small>
    </div>
  );
}

export function PlantCardView({ c }: { c: PlantCard }) {
  const style = { left: `${c.x * 100}%`, top: `${c.y * 100}%` } as CSSProperties;
  return (
    <div className={`pc-card ${c.state}`} style={style} role="status" aria-label={`${c.label} stats`}>
      <header><strong>{c.label}</strong><em>STAGE {c.stage}</em></header>
      {c.state === 'dead' ? (
        <div className="pc-note bad"><span>✕</span>Dead</div>
      ) : c.state === 'ready' ? (
        <div className="pc-note ok"><span>✓</span>Ready to harvest</div>
      ) : (
        <div className="pc-grid">
          <Dial value={c.health} color="#ff4d5a" label="HEALTH" />
          <Dial value={c.growth * 100} color="#37d39a" label="GROWTH" />
          <Dial value={c.water} color="#4a8dff" label="WATER" />
          <Dial value={c.nutrient} color="#f2b443" label="FERT" />
        </div>
      )}
    </div>
  );
}
