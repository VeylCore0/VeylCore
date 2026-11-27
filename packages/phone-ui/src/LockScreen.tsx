// The lock screen: shown whenever a PIN is set and has not been entered. The server sends no personal data until
// `unlock` succeeds, so this is not just a curtain. Forgot PIN: the account password resets it.
import { useEffect, useState } from 'react';
import { api } from './api';
import { onSession } from './controller';
import { clockSuffix, clockText } from './format';
import { Ico } from './icons';
import { NewPin, PinPad } from './PinPad';
import { useStore } from './store';
import { Button, Sheet, TextInput, say } from './ui';
import type { Hello } from './types';

export function LockScreen() {
  const locked = useStore((s) => !!s.hello?.locked);
  const world = useStore((s) => s.world);
  const [error, setError] = useState('');
  const [wait, setWait] = useState(0);
  const [forgot, setForgot] = useState(false);

  useEffect(() => {
    if (wait <= 0) return;
    const t = window.setInterval(() => setWait((w) => Math.max(0, w - 1)), 1000);
    return () => window.clearInterval(t);
  }, [wait > 0]); // eslint-disable-line react-hooks/exhaustive-deps

  // Start clean every time the phone locks again (no stale error, no leftover Forgot PIN sheet).
  useEffect(() => { if (!locked) { setForgot(false); setError(''); setWait(0); } }, [locked]);

  if (!locked) return null;

  const unlock = async (pin: string) => {
    const r = await api<Hello & { seconds?: number; left?: number }>('unlock', pin);
    if (r.ok && r.data) { setError(''); onSession(r.data); return true; }
    const d = r.data as { seconds?: number; left?: number } | undefined;
    if (r.code === 'LOCKED_OUT' && d?.seconds) setWait(d.seconds);
    setError(r.code === 'WRONG_PIN' && d?.left !== undefined ? `Wrong PIN. ${d.left} ${d.left === 1 ? 'try' : 'tries'} left` : r.message ?? 'Could not unlock');
    return false;
  };
  const mmss = `${Math.floor(wait / 60)}:${String(wait % 60).padStart(2, '0')}`;

  return (
    <div className="ph-lock" role="dialog" aria-label="Phone locked">
      <div className="ph-lock-time">
        <Ico name="lock" size={18} />
        <strong>{world ? clockText(world.hour, world.minute) : '--:--'}<small>{world ? clockSuffix(world.hour) : ''}</small></strong>
      </div>
      <PinPad
        title={wait > 0 ? 'Try again later' : 'Enter PIN'}
        subtitle={wait > 0 ? `Too many attempts. Wait ${mmss}` : undefined}
        error={wait > 0 ? undefined : error}
        disabled={wait > 0}
        onComplete={unlock}
        footer={<button className="ph-link" onClick={() => setForgot(true)}>Forgot PIN?</button>}
      />
      {forgot && <ForgotPin onClose={() => setForgot(false)} />}
    </div>
  );
}

function ForgotPin({ onClose }: { onClose: () => void }) {
  const [password, setPassword] = useState('');
  const [step, setStep] = useState<'password' | 'pin'>('password');
  const [error, setError] = useState('');
  return (
    <Sheet title="Forgot PIN" onClose={onClose}>
      {step === 'password' ? (
        <div className="ph-form">
          <p className="ph-hint">Enter your account password to choose a new PIN. No account on this phone? Ask staff to reset it.</p>
          <label>Account password<TextInput type="password" value={password} onChange={setPassword} placeholder="Password" autoFocus onEnter={() => password && setStep('pin')} /></label>
          {error && <p className="ph-hint danger">{error}</p>}
          <Button kind="primary" block disabled={!password} onClick={() => { setError(''); setStep('pin'); }}>Continue</Button>
        </div>
      ) : (
        <NewPin
          title="New PIN"
          subtitle="Choose 4 digits"
          onSubmit={async (pin) => {
            const r = await api<Hello>('pinReset', { password, pin });
            if (r.ok && r.data) { say(r); onSession(r.data); return; }
            if (r.code === 'WRONG_PASSWORD' || r.code === 'LOCKED_OUT' || r.code === 'NO_ACCOUNT') { setStep('password'); setError(r.message ?? 'Could not reset'); return r.message; }
            return r.message ?? 'Could not reset your PIN';
          }}
        />
      )}
    </Sheet>
  );
}
