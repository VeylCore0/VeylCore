// Phone: keypad, recents, favourites. Calls themselves are driven by the server (see CallScreen).
import { useCallback, useEffect, useMemo, useState } from 'react';
import { api } from '../api';
import { startCall } from '../controller';
import { formatDigits, listTime, duration } from '../format';
import { Ico } from '../icons';
import { useRouteOnce } from '../nav';
import { useStore } from '../store';
import { Avatar, Empty, Header, Segmented, Spinner, cx } from '../ui';
import type { Contact, Recent } from '../types';

type Tab = 'recents' | 'keypad' | 'favorites';
const KEYS: [string, string][] = [['1', ''], ['2', 'ABC'], ['3', 'DEF'], ['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO'], ['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ']];

export function PhoneApp({ route }: { route?: string }) {
  const [tab, setTab] = useState<Tab>('keypad');
  const [digits, setDigits] = useState('');
  const voice = useStore((s) => s.hello?.voice);
  const call = useStore((s) => s.call);
  const [contacts, setContacts] = useState<Contact[] | null>(null);

  useEffect(() => { void api<Contact[]>('contacts').then((r) => setContacts(r.ok ? r.data ?? [] : [])); }, []);
  useRouteOnce(route, (r) => {
    if (r === 'recents') setTab('recents');
    const d = /^dial\/(\d{1,7})$/.exec(r);
    if (d) { setTab('keypad'); setDigits(d[1]); }
  });

  const canCall = !!voice?.available && !call;
  const dial = useCallback((n: string) => { if (canCall && n.length === 7) void startCall(n); }, [canCall]);
  const match = useMemo(() => contacts?.find((c) => c.number === digits), [contacts, digits]);

  // Physical keyboard on the keypad (only when no text field has focus).
  useEffect(() => {
    if (tab !== 'keypad') return;
    const onKey = (e: KeyboardEvent) => {
      if (document.activeElement && document.activeElement !== document.body) return;
      if (/^[0-9]$/.test(e.key)) setDigits((d) => (d.length < 7 ? d + e.key : d));
      else if (e.key === 'Backspace') setDigits((d) => d.slice(0, -1));
      else if (e.key === 'Enter') dial(digits);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [tab, digits, dial]);

  return (
    <div className="ph-app">
      {tab !== 'keypad' && <Header title={tab === 'recents' ? 'Recents' : 'Favorites'} />}
      {voice && !voice.available && (
        <div className="ph-notice"><Ico name="alert" size={16} /><span>{voice.reason ?? 'Calls are unavailable right now.'}</span></div>
      )}
      {tab === 'keypad' && (
        <div className="ph-keypad">
          <div className="ph-dialed">
            <div className="ph-dialed-name">{match ? match.name : digits.length === 7 ? 'Not in contacts' : ' '}</div>
            <div className={cx('ph-dialed-num', !digits && 'empty')}>{digits ? formatDigits(digits) : 'Enter a number'}</div>
          </div>
          <div className="ph-keys">
            {KEYS.map(([k, l]) => (
              <button key={k} className="ph-key" onClick={() => setDigits((d) => (d.length < 7 ? d + k : d))}><strong>{k}</strong><small>{l}</small></button>
            ))}
            <span />
            <button className="ph-key" onClick={() => setDigits((d) => (d.length < 7 ? d + '0' : d))}><strong>0</strong><small>+</small></button>
            <button className="ph-key k-ghost" onClick={() => setDigits((d) => d.slice(0, -1))} onDoubleClick={() => setDigits('')} aria-label="Delete" style={{ visibility: digits ? 'visible' : 'hidden' }}><Ico name="backspace" size={24} /></button>
          </div>
          <button className="ph-dial" onClick={() => dial(digits)} disabled={!canCall || digits.length !== 7} aria-label="Call"><Ico name="phone" size={28} /></button>
        </div>
      )}
      {tab === 'recents' && <Recents canCall={canCall} onCall={dial} />}
      {tab === 'favorites' && <Favorites contacts={contacts} canCall={canCall} onCall={dial} />}
      <nav className="ph-tabbar">
        {([['favorites', 'star', 'Favorites'], ['recents', 'clock', 'Recents'], ['keypad', 'phone', 'Keypad']] as const).map(([id, icon, label]) => (
          <button key={id} className={cx(tab === id && 'on')} onClick={() => setTab(id)}><Ico name={icon} size={22} /><span>{label}</span></button>
        ))}
      </nav>
    </div>
  );
}

function Recents({ canCall, onCall }: { canCall: boolean; onCall: (n: string) => void }) {
  const [list, setList] = useState<Recent[] | null>(null);
  const [filter, setFilter] = useState<'all' | 'missed'>('all');
  const call = useStore((s) => s.call);
  const load = useCallback(async () => { const r = await api<Recent[]>('recents'); setList(r.ok ? r.data ?? [] : []); }, []);
  useEffect(() => { void load(); }, [load, call?.state === 'ended']);
  const rows = (list ?? []).filter((r) => filter === 'all' || r.missed);
  return (
    <div className="ph-scroll">
      <div className="ph-pad"><Segmented options={[{ id: 'all', label: 'All' }, { id: 'missed', label: 'Missed' }]} value={filter} onChange={setFilter} /></div>
      {list === null && <Spinner />}
      {list && rows.length === 0 && <Empty icon="phone" title={filter === 'missed' ? 'No missed calls' : 'No recent calls'} />}
      <ul className="ph-list">
        {rows.map((r) => (
          <li key={r.id}>
            <button className="ph-conv" onClick={() => onCall(r.number)} disabled={!canCall}>
              <Avatar name={/^\d{3}-\d{4}$/.test(r.display) ? '' : r.display} id={r.number} size={42} />
              <span className="ph-conv-main">
                <strong className={cx(r.missed && 'missed')}>{r.display}</strong>
                <span className="ph-sub"><Ico name="phone" size={12} style={{ transform: r.direction === 'out' ? 'none' : 'rotate(135deg)', color: r.missed ? 'var(--ph-danger)' : undefined }} />
                  {r.missed ? 'Missed' : r.direction === 'out' ? 'Outgoing' : 'Incoming'}{r.duration > 0 ? ` · ${duration(r.duration)}` : ''}</span>
              </span>
              <time>{listTime(r.time)}</time>
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}

function Favorites({ contacts, canCall, onCall }: { contacts: Contact[] | null; canCall: boolean; onCall: (n: string) => void }) {
  const favs = (contacts ?? []).filter((c) => c.favorite);
  return (
    <div className="ph-scroll">
      {contacts === null && <Spinner />}
      {contacts && favs.length === 0 && <Empty icon="star" title="No favorites" text="Star a contact in Contacts to pin them here." />}
      <ul className="ph-list">
        {favs.map((c) => (
          <li key={c.id}>
            <button className="ph-conv" onClick={() => onCall(c.number)} disabled={!canCall}>
              <Avatar name={c.name} id={c.number} size={42} />
              <span className="ph-conv-main"><strong>{c.name}</strong><span className="ph-sub">{c.display}</span></span>
              <Ico name="phone" size={18} style={{ color: 'var(--ph-green)' }} />
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}
