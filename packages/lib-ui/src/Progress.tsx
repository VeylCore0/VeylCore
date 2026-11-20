import { useEffect, useState } from 'react';
import type { ProgressMessage } from '@veyl/ui';

export function Progress({ label, duration, canCancel }: ProgressMessage) {
  const [started, setStarted] = useState(false);
  useEffect(() => {
    setStarted(false);
    const raf = requestAnimationFrame(() => setStarted(true));
    return () => cancelAnimationFrame(raf);
  }, [label, duration]);
  return (
    <div className="progress">
      <div className="progress-label">{label}</div>
      <div className="progress-track">
        <div className="progress-fill" style={{ width: started ? '100%' : '0%', transition: started ? `width ${duration}ms linear` : 'none' }} />
      </div>
      {canCancel && <div className="progress-hint v-muted"><span className="v-key">X</span> cancel</div>}
    </div>
  );
}
