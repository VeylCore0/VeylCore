import { useEffect, useRef, useState, type CSSProperties } from 'react';
import { useNuiMessage } from '@veyl/ui';

// ---------------------------------------------------------------------------
// The death screen. Passive: it never takes focus; the game keeps the keys (G / E). Lua pushes the state every
// ~500 ms (resources/[veyl]/veyl_medical/client/main.lua: pushScreen) and this page counts down smoothly between.
// ---------------------------------------------------------------------------
interface Push {
  visible: boolean; state?: 'down' | 'dead'; remainingMs?: number; totalMs?: number; callMs?: number;
  helpedMs?: number; helpedTotalMs?: number; ems?: number; alerted?: number; fee?: number; respawning?: boolean;
  firstAid?: boolean; hospital?: string;
}
interface Live extends Push { at: number }

const clock = (ms: number) => {
  const s = Math.max(0, Math.ceil(ms / 1000));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
};

export function App() {
  const [live, setLive] = useState<Live | null>(null);
  const [now, setNow] = useState(() => performance.now());
  const [leaving, setLeaving] = useState(false);
  const hideTimer = useRef<number>();

  useNuiMessage<Push>('medical:state', (d) => {
    if (!d || !d.visible) {
      if (live && !leaving) { setLeaving(true); hideTimer.current = window.setTimeout(() => { setLive(null); setLeaving(false); }, 700); }
      return;
    }
    window.clearTimeout(hideTimer.current);
    setLeaving(false);
    setLive({ ...d, at: performance.now() });
  });

  useEffect(() => {
    if (!live) return;
    const id = window.setInterval(() => setNow(performance.now()), 100);
    return () => window.clearInterval(id);
  }, [live]);

  if (!live) return null;
  const since = now - live.at;
  const remaining = Math.max(0, (live.remainingMs ?? 0) - since);
  const total = Math.max(1, live.totalMs ?? 1);
  const frac = Math.min(1, remaining / total);
  const callIn = Math.max(0, (live.callMs ?? 0) - since);
  const helped = Math.max(0, (live.helpedMs ?? 0) - since);
  const helpFrac = live.helpedTotalMs ? 1 - helped / live.helpedTotalMs : 0;
  const down = live.state === 'down';
  const ready = !down && remaining <= 0;
  // The heartbeat speeds up in a few steps as you bleed out (changing it every tick would restart the animations).
  const beat = !down ? 2.6 : frac > 0.6 ? 1.0 : frac > 0.35 ? 0.85 : frac > 0.2 ? 0.7 : 0.55;
  const style = { '--beat': `${beat}s` } as CSSProperties;

  return (
    <div className={`ds ${down ? 'down' : 'dead'}${helped > 0 ? ' helped' : ''}${leaving ? ' leaving' : ''}${down && frac < 0.2 ? ' critical' : ''}`} style={style} aria-live="polite">
      <div className="ds-vignette" />
      <div className="ds-grain" />

      <div className="ds-stack">
        <Ecg flat={!down && helped <= 0} steady={helped > 0} />

        <h1 className="ds-title" data-text={down ? "YOU'RE DOWN" : 'UNCONSCIOUS'}>{down ? "YOU'RE DOWN" : 'UNCONSCIOUS'}</h1>
        <div className="ds-sub">
          {helped > 0 ? 'Hold on. Someone is working on you.'
            : down ? 'You are bleeding out'
            : ready ? 'You can be taken to hospital' : 'Your vision fades to black'}
        </div>

        {helped > 0 ? (
          <div className="ds-help">
            <div className="ds-help-bar"><span style={{ width: `${Math.min(100, helpFrac * 100)}%` }} /></div>
            <div className="ds-help-label">{down ? 'Being helped up' : 'Being revived'} · {clock(helped)}</div>
          </div>
        ) : (
          <div className="ds-timer">
            <Ring frac={ready ? 1 : frac} />
            <div className="ds-timer-text">
              <strong>{ready ? 'READY' : clock(remaining)}</strong>
              <span>{down ? 'until you pass out' : ready ? 'respawn available' : 'until you can respawn'}</span>
            </div>
          </div>
        )}

        <div className="ds-chips">
          {(live.ems ?? 0) > 0
            ? <span className="ds-chip ok"><i />{live.ems} EMS on duty{(live.alerted ?? 0) > 0 ? ' · alerted' : ''}</span>
            : <span className="ds-chip warn"><i />No EMS on duty</span>}
          {down && live.firstAid && <span className="ds-chip">A first aid kit can get you back up</span>}
          {!down && !ready && (live.ems ?? 0) > 0 && <span className="ds-chip">EMS can still revive you</span>}
        </div>

        {helped <= 0 && (
          <div className="ds-prompt">
            {down && (callIn > 0
              ? <span className="ds-key muted"><kbd>G</kbd>Call for help again in {clock(callIn)}</span>
              : <span className="ds-key"><kbd>G</kbd>Call for help</span>)}
            {!down && ready && (live.respawning
              ? <span className="ds-key big muted">Checking you in…</span>
              : <span className="ds-key big"><kbd>E</kbd>Respawn at {live.hospital ?? 'the hospital'}{(live.fee ?? 0) > 0 && <em>${live.fee}</em>}</span>)}
          </div>
        )}
      </div>
    </div>
  );
}

function Ring({ frac }: { frac: number }) {
  const r = 46, c = 2 * Math.PI * r;
  return (
    <svg className="ds-ring" viewBox="0 0 108 108" aria-hidden="true">
      <circle cx="54" cy="54" r={r} className="track" />
      <circle cx="54" cy="54" r={r} className="fill" strokeDasharray={c} strokeDashoffset={c * (1 - frac)} transform="rotate(-90 54 54)" />
    </svg>
  );
}

/** A scrolling heart monitor trace; flat while unconscious, calm while someone is helping. */
function Ecg({ flat, steady }: { flat: boolean; steady: boolean }) {
  const beat = 'l 30 0 l 6 -6 l 6 6 l 8 0 l 5 10 l 8 -46 l 8 50 l 6 -14 l 10 0 l 8 -8 l 8 8 l 27 0';
  const path = flat ? 'M 0 40 l 520 0' : `M 0 40 ${beat} ${beat} ${beat} ${beat}`;
  return (
    <div className={`ds-ecg${flat ? ' flat' : ''}${steady ? ' steady' : ''}`} aria-hidden="true">
      <svg viewBox="0 0 260 70" preserveAspectRatio="none">
        <path d={path} className="trace" />
      </svg>
    </div>
  );
}
