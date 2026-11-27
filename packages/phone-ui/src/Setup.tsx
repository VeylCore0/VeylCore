// First-run setup: welcome, create an account (email + password), set a PIN. Every step can be skipped, and it can all
// be done later in Settings. Finishing (or skipping) is remembered on the server so it is only shown once.
import { useState } from 'react';
import { api } from './api';
import { setSecurity } from './controller';
import { Ico } from './icons';
import { NewPin } from './PinPad';
import { AccountForm } from './apps/Security';
import { useStore } from './store';
import { Button, cx, say } from './ui';

type Step = 'welcome' | 'account' | 'pin' | 'done';
const ORDER: Step[] = ['welcome', 'account', 'pin', 'done'];

export function Setup() {
  const sec = useStore((s) => s.hello?.security);
  const locked = useStore((s) => !!s.hello?.locked);
  const number = useStore((s) => s.hello?.display);
  const [step, setStep] = useState<Step>('welcome');
  const [skipped, setSkipped] = useState<{ account?: boolean; pin?: boolean }>({});
  if (!sec || locked || sec.setupDone) return null;

  const finish = async () => { say(await api('setupFinish')); setSecurity({ setupDone: true }); };
  const idx = ORDER.indexOf(step);

  return (
    <div className="ph-setup" role="dialog" aria-label="Set up your phone">
      <div className="ph-setup-dots">{ORDER.map((s, i) => <i key={s} className={cx(i <= idx && 'on')} />)}</div>

      {step === 'welcome' && (
        <div className="ph-setup-body center">
          <span className="ph-setup-logo"><Ico name="phone" size={44} stroke={1.6} /></span>
          <h1>Welcome</h1>
          <p>Let us set up your phone. It takes a minute.</p>
          <ul className="ph-setup-list">
            <li><Ico name="user" size={18} /><span><b>Your number</b> {number}</span></li>
            <li><Ico name="mail" size={18} /><span><b>An account</b> an email and password</span></li>
            <li><Ico name="lock" size={18} /><span><b>A PIN</b> to keep it private</span></li>
          </ul>
          <div className="ph-setup-actions">
            <Button kind="primary" block onClick={() => setStep('account')}>Continue</Button>
            <button className="ph-link" onClick={finish}>Set up later</button>
          </div>
        </div>
      )}

      {step === 'account' && (
        <div className="ph-setup-body">
          <h1>Create your account</h1>
          <p>Choose an email and a password. If you ever forget your PIN, your password gets you back in.</p>
          <AccountForm submitLabel="Create account" onDone={(email) => { setSecurity({ email }); setStep('pin'); }} />
          <button className="ph-link ph-setup-skip" onClick={() => { setSkipped((s) => ({ ...s, account: true })); setStep('pin'); }}>Skip for now</button>
        </div>
      )}

      {step === 'pin' && (
        <div className="ph-setup-body center">
          <NewPin
            title="Create a PIN"
            subtitle="Your phone will ask for it each time you open it"
            onSubmit={async (pin) => {
              const r = await api('pinSet', { pin });
              if (!r.ok) return r.message ?? 'Could not save the PIN';
              setSecurity({ hasPin: true });
              setStep('done');
            }}
            footer={(
              <>
                {!sec.email && <p className="ph-hint">No account: if you forget this PIN, only staff can reset it.</p>}
                <button className="ph-link" onClick={() => { setSkipped((s) => ({ ...s, pin: true })); setStep('done'); }}>Skip for now</button>
              </>
            )}
          />
        </div>
      )}

      {step === 'done' && (
        <div className="ph-setup-body center">
          <span className="ph-setup-logo ok"><Ico name="check" size={44} stroke={2.4} /></span>
          <h1>All set</h1>
          <ul className="ph-setup-list">
            <li><Ico name="user" size={18} /><span><b>Number</b> {number}</span></li>
            <li><Ico name="mail" size={18} /><span><b>Account</b> {sec.email ?? (skipped.account ? 'Not set up' : 'Not set up')}</span></li>
            <li><Ico name="lock" size={18} /><span><b>PIN</b> {sec.hasPin ? 'On' : 'Off'}</span></li>
          </ul>
          <p className="ph-setup-note">You can change any of this in Settings, under Account.</p>
          <div className="ph-setup-actions"><Button kind="primary" block onClick={finish}>Get started</Button></div>
        </div>
      )}
    </div>
  );
}
