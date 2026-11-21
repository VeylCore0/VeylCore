import { useEffect, useState } from 'react';
import { Icon } from '@veyl/ui';
import { api } from '../api';
import { AppHeader, usePhone } from '../App';
import { clock, fmtNumber, timeAgo, type Contact } from '../types';

interface Recent { id: number; number: string; display: string; outgoing: boolean; answered: boolean; missed: boolean; seconds?: number; at: number }

export function PhoneApp() {
  const { session, startCall, go, route } = usePhone();
  const [tab, setTab] = useState<'keypad' | 'recents' | 'contacts'>(route === 'recents' ? 'recents' : 'keypad');
  const voice = session.voice;
  const call = async (number: string) => { await startCall(number); go('phone', 'call'); };
  return (
    <div className="ph-appview">
      <AppHeader title="Phone" />
      {!voice.available && (
        <div className="ph-notice" role="note"><Icon name="alert" size="1rem" /><span>{voice.reason}</span></div>
      )}
      <div className="ph-body">
        {tab === 'keypad' && <Keypad disabled={!voice.available} onCall={call} />}
        {tab === 'recents' && <Recents disabled={!voice.available} onCall={call} />}
        {tab === 'contacts' && <ContactPicker disabled={!voice.available} onCall={call} />}
      </div>
      <nav className="ph-tabs" aria-label="Phone sections">
        {(['keypad', 'recents', 'contacts'] as const).map((t) => (
          <button key={t} className={tab === t ? 'on' : ''} onClick={() => setTab(t)}>
            <Icon name={t === 'keypad' ? 'dialpad' : t === 'recents' ? 'clock' : 'user'} size="1.1rem" />
            <span>{t === 'keypad' ? 'Keypad' : t === 'recents' ? 'Recents' : 'Contacts'}</span>
          </button>
        ))}
      </nav>
    </div>
  );
}

function Keypad({ disabled, onCall }: { disabled: boolean; onCall: (n: string) => void }) {
  const [digits, setDigits] = useState('');
  const press = (d: string) => setDigits((x) => (x.length < 7 ? x + d : x));
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.target as HTMLElement).tagName === 'INPUT') return;
      if (/^[0-9]$/.test(e.key)) press(e.key);
      else if (e.key === 'Backspace') setDigits((x) => x.slice(0, -1));
      else if (e.key === 'Enter' && digits.length === 7 && !disabled) onCall(digits);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [digits, disabled, onCall]);
  return (
    <div className="ph-keypad">
      <div className="ph-dial-display" aria-live="polite">{fmtNumber(digits) || <span className="muted">Enter a number</span>}</div>
      <div className="ph-keys">
        {['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'].map((k, i) => k === '' ? <span key={i} /> : (
          <button key={i} className="ph-key" onClick={() => (k === '⌫' ? setDigits((x) => x.slice(0, -1)) : press(k))} aria-label={k === '⌫' ? 'Delete' : k}>{k}</button>
        ))}
      </div>
      <button className="ph-round green" disabled={disabled || digits.length !== 7} onClick={() => onCall(digits)} aria-label="Call"><Icon name="call" size="1.4rem" /></button>
    </div>
  );
}

function Recents({ disabled, onCall }: { disabled: boolean; onCall: (n: string) => void }) {
  const [items, setItems] = useState<Recent[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<'all' | 'missed'>('all');
  useEffect(() => { void api<{ items: Recent[] }>('recents').then((r) => (r.ok && r.data ? setItems(r.data.items) : setError(r.message ?? 'Could not load'))); }, []);
  if (error) return <div className="ph-empty error">{error}</div>;
  if (!items) return <div className="ph-empty">Loading…</div>;
  const list = filter === 'missed' ? items.filter((r) => r.missed) : items;
  return (
    <>
      <div className="ph-seg"><button className={filter === 'all' ? 'on' : ''} onClick={() => setFilter('all')}>All</button><button className={filter === 'missed' ? 'on' : ''} onClick={() => setFilter('missed')}>Missed</button></div>
      {list.length === 0 && <div className="ph-empty">No calls yet.</div>}
      <ul className="ph-list">
        {list.map((r) => (
          <li key={r.id}>
            <button className="ph-row" disabled={disabled} onClick={() => onCall(r.number)}>
              <span className={`ph-row-icon${r.missed ? ' missed' : ''}`}><Icon name={r.missed ? 'alert' : 'call'} size="0.9rem" /></span>
              <span className="ph-row-main"><strong className={r.missed ? 'missed' : ''}>{r.display}</strong>
                <span className="muted">{r.outgoing ? 'Outgoing' : r.missed ? 'Missed' : 'Incoming'}{r.answered && r.seconds != null ? ` · ${Math.floor(r.seconds / 60)}:${String(r.seconds % 60).padStart(2, '0')}` : ''}</span></span>
              <span className="muted">{timeAgo(r.at)} · {clock(r.at)}</span>
            </button>
          </li>
        ))}
      </ul>
    </>
  );
}

function ContactPicker({ disabled, onCall }: { disabled: boolean; onCall: (n: string) => void }) {
  const [items, setItems] = useState<Contact[] | null>(null);
  useEffect(() => { void api<Contact[]>('contacts').then((r) => setItems(r.ok && r.data ? r.data : [])); }, []);
  if (!items) return <div className="ph-empty">Loading…</div>;
  if (items.length === 0) return <div className="ph-empty">No contacts yet. Add some in Contacts.</div>;
  return (
    <ul className="ph-list">
      {items.map((c) => (
        <li key={c.id}><button className="ph-row" disabled={disabled} onClick={() => onCall(c.number)}><span className="ph-row-main"><strong>{c.name}</strong><span className="muted">{c.display}</span></span><Icon name="call" size="1rem" /></button></li>
      ))}
    </ul>
  );
}
