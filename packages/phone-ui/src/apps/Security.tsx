// Account (email + password) and PIN: the create-account form, PIN sheets and the Account & Security page in Settings.
// The server does every check; this only collects input and shows what it said.
import { useEffect, useState } from 'react';
import { api } from '../api';
import { setSecurity } from '../controller';
import { Ico } from '../icons';
import { NewPin, PinPad } from '../PinPad';
import { useStore } from '../store';
import { Button, Group, Header, Row, Sheet, TextInput, cx, say, toast } from '../ui';

/** 0 to 4: a rough password strength for the meter (the server only enforces the minimum length). */
export function strength(pw: string) {
  let n = 0;
  if (pw.length >= 6) n++;
  if (pw.length >= 10) n++;
  if (/[a-z]/.test(pw) && /[A-Z]/.test(pw)) n++;
  if (/\d/.test(pw) && /[^a-zA-Z0-9]/.test(pw)) n++;
  return n;
}
const STRENGTH = ['Too short', 'Weak', 'Fair', 'Good', 'Strong'];

/** Create the phone account: an email name on the server's domain and a password. */
export function AccountForm({ onDone, submitLabel = 'Create account' }: { onDone: (email: string) => void; submitLabel?: string }) {
  const domain = useStore((s) => s.hello?.security.domain ?? 'veylid.com');
  const min = useStore((s) => s.hello?.security.passwordMin ?? 6);
  const [name, setName] = useState('');
  const [pw, setPw] = useState('');
  const [pw2, setPw2] = useState('');
  const [show, setShow] = useState(false);
  const [avail, setAvail] = useState<{ available: boolean; reason?: string } | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    setAvail(null);
    if (name.trim().length < 3) return;
    const t = window.setTimeout(async () => {
      const r = await api<{ available: boolean; reason?: string }>('accountCheck', name);
      if (r.ok && r.data) setAvail(r.data);
    }, 350);
    return () => window.clearTimeout(t);
  }, [name]);

  const score = pw ? Math.min(strength(pw), pw.length < min ? 0 : 4) : 0;
  const ready = !!avail?.available && pw.length >= min && pw === pw2 && !busy;
  const submit = async () => {
    if (!ready) return;
    setBusy(true);
    const r = await api<{ email: string }>('accountCreate', { username: name, password: pw });
    setBusy(false);
    if (say(r) && r.data) onDone(r.data.email);
  };

  return (
    <div className="ph-form">
      <label>
        Email
        <span className="ph-emailrow">
          <TextInput value={name} onChange={(v) => setName(v.toLowerCase().replace(/[^a-z0-9._]/g, '').slice(0, 24))} placeholder="yourname" autoFocus />
          <em>@{domain}</em>
        </span>
        <small className={cx('ph-avail', avail && (avail.available ? 'ok' : 'bad'))}>
          {!avail ? (name.length >= 3 ? 'Checking...' : 'Letters, numbers, dots and underscores') : avail.available ? <><Ico name="check" size={13} stroke={3} /> {name}@{domain} is available</> : avail.reason}
        </small>
      </label>
      <label>
        Password
        <span className="ph-pwrow">
          <TextInput type={show ? 'text' : 'password'} value={pw} onChange={setPw} placeholder={`At least ${min} characters`} maxLength={64} />
          <button type="button" className="ph-link" onClick={() => setShow((s) => !s)}>{show ? 'Hide' : 'Show'}</button>
        </span>
        <span className="ph-meter" aria-hidden="true">{[1, 2, 3, 4].map((i) => <i key={i} className={cx(i <= score && `s${score}`)} />)}<b>{pw ? STRENGTH[score] : ''}</b></span>
      </label>
      <label>
        Confirm password
        <TextInput type={show ? 'text' : 'password'} value={pw2} onChange={setPw2} placeholder="Type it again" maxLength={64} onEnter={submit} />
        {pw2 && pw !== pw2 && <small className="ph-avail bad">The passwords do not match</small>}
      </label>
      <Button kind="primary" block onClick={submit} disabled={!ready}>{submitLabel}</Button>
    </div>
  );
}

type PinMode = 'set' | 'change' | 'off';

/** Set, change or turn off the PIN. Changing and turning off ask for the current PIN first. */
export function PinSheet({ mode, onClose }: { mode: PinMode; onClose: () => void }) {
  const hasAccount = useStore((s) => !!s.hello?.security.email);
  const [current, setCurrent] = useState<string | null>(null);
  const [error, setError] = useState('');

  const finish = (hasPin: boolean) => { setSecurity({ hasPin }); onClose(); };

  if (mode === 'set') {
    return (
      <Sheet title="Set a PIN" onClose={onClose}>
        <NewPin
          footer={!hasAccount ? <p className="ph-hint">No account yet: if you forget this PIN, only staff can reset it.</p> : undefined}
          onSubmit={async (pin) => { const r = await api('pinSet', { pin }); if (!r.ok) return r.message ?? 'Could not save the PIN'; toast('PIN saved'); finish(true); }}
        />
      </Sheet>
    );
  }
  if (current === null) {
    return (
      <Sheet title={mode === 'off' ? 'Turn off PIN' : 'Change PIN'} onClose={onClose}>
        <PinPad
          title="Enter your current PIN"
          error={error}
          onComplete={async (pin) => {
            if (mode === 'off') {
              const r = await api('pinRemove', pin);
              if (r.ok) { toast('PIN turned off'); finish(false); return; }
              setError(r.message ?? 'Wrong PIN'); return false;
            }
            setError(''); setCurrent(pin);
          }}
        />
      </Sheet>
    );
  }
  return (
    <Sheet title="Change PIN" onClose={onClose}>
      <NewPin
        title="Choose a new PIN"
        onSubmit={async (pin) => {
          const r = await api('pinSet', { pin, current });
          if (r.ok) { toast('PIN changed'); finish(true); return; }
          if (r.code === 'WRONG_PIN' || r.code === 'LOCKED_OUT') { setCurrent(null); setError(r.message ?? 'Wrong PIN'); }
          return r.message ?? 'Could not change the PIN';
        }}
      />
    </Sheet>
  );
}

function PasswordSheet({ onClose }: { onClose: () => void }) {
  const min = useStore((s) => s.hello?.security.passwordMin ?? 6);
  const [cur, setCur] = useState('');
  const [pw, setPw] = useState('');
  const [pw2, setPw2] = useState('');
  const [busy, setBusy] = useState(false);
  const ok = cur.length > 0 && pw.length >= min && pw === pw2 && !busy;
  const save = async () => {
    if (!ok) return;
    setBusy(true);
    const r = await api('passwordChange', { current: cur, new: pw });
    setBusy(false);
    if (say(r)) onClose();
  };
  return (
    <Sheet title="Change password" onClose={onClose}>
      <div className="ph-form">
        <label>Current password<TextInput type="password" value={cur} onChange={setCur} autoFocus /></label>
        <label>New password<TextInput type="password" value={pw} onChange={setPw} placeholder={`At least ${min} characters`} maxLength={64} /></label>
        <label>Confirm new password<TextInput type="password" value={pw2} onChange={setPw2} maxLength={64} onEnter={save} /></label>
        {pw2 && pw !== pw2 && <p className="ph-hint danger">The passwords do not match</p>}
        <Button kind="primary" block onClick={save} disabled={!ok}>Change password</Button>
      </div>
    </Sheet>
  );
}

export function AccountPage({ onBack }: { onBack: () => void }) {
  const sec = useStore((s) => s.hello?.security);
  const [sheet, setSheet] = useState<'create' | 'password' | PinMode | null>(null);
  if (!sec) return null;
  return (
    <div className="ph-app">
      <Header title="Account" onBack={onBack} backLabel="Settings" />
      <div className="ph-scroll ph-pad">
        <div className="ph-acct-hero">
          <span><Ico name="shield" size={30} /></span>
          <strong>{sec.email ?? 'No account yet'}</strong>
          <em>{sec.email ? 'Your Veyl ID' : 'Create one to recover a forgotten PIN'}</em>
        </div>
        <Group title="Account" footer={sec.email ? undefined : 'An account is an email and a password. It lets you reset your PIN without asking staff.'}>
          {sec.email
            ? <Row icon="key" iconColor="#6a6cf0" title="Change password" onClick={() => setSheet('password')} chevron />
            : <Row icon="userplus" iconColor="var(--ph-accent)" title="Create account" onClick={() => setSheet('create')} chevron />}
        </Group>
        <Group title="PIN lock" footer="With a PIN on, your phone asks for it every time you open it. Five wrong tries lock it for 5 minutes.">
          <Row icon="lock" iconColor="#2fc473" title="PIN lock" right={<span className="ph-sub">{sec.hasPin ? 'On' : 'Off'}</span>} />
          {sec.hasPin ? (
            <>
              <Row title="Change PIN" onClick={() => setSheet('change')} chevron />
              <Row title="Turn off PIN" danger onClick={() => setSheet('off')} />
            </>
          ) : <Row title="Set a PIN" onClick={() => setSheet('set')} chevron />}
        </Group>
      </div>
      {sheet === 'create' && (
        <Sheet title="Create account" onClose={() => setSheet(null)}>
          <AccountForm onDone={(email) => { setSecurity({ email }); setSheet(null); }} />
        </Sheet>
      )}
      {sheet === 'password' && <PasswordSheet onClose={() => setSheet(null)} />}
      {(sheet === 'set' || sheet === 'change' || sheet === 'off') && <PinSheet mode={sheet} onClose={() => setSheet(null)} />}
    </div>
  );
}
