import { useCallback, useEffect, useState } from 'react';
import { Icon, nui } from '@veyl/ui';
import { api } from '../api';
import { AppHeader, usePhone } from '../App';
import { timeAgo } from '../types';

interface Service { id: string; label: string; icon: string; onDuty: number }
interface Request { id: number; service?: string; message: string; status: string; taken_by?: string; at: number; caller_name?: string; caller_number?: string; x?: number; y?: number }
interface Data { services: Service[]; mine: Request[]; duty: string | null; queue: Request[] | null }

export function ServicesApp() {
  const { toast } = usePhone();
  const [data, setData] = useState<Data | null>(null);
  const [pick, setPick] = useState<Service | null>(null);
  const [text, setText] = useState('');
  const [tab, setTab] = useState<'call' | 'queue'>('call');
  const load = useCallback(async () => {
    const r = await api<Data>('servicesData');
    if (r.ok && r.data) setData(r.data); else toast(r.message ?? 'Could not load', 'error');
  }, [toast]);
  useEffect(() => { void load(); const t = window.setInterval(() => void load(), 15000); return () => window.clearInterval(t); }, [load]);

  const send = async () => {
    if (!pick) return;
    const r = await api('serviceRequest', pick.id, text);
    toast(r.message ?? (r.ok ? 'Sent' : 'Could not send'), r.ok ? undefined : 'error');
    if (r.ok) { setPick(null); setText(''); void load(); }
  };

  if (pick) {
    return (
      <div className="ph-appview">
        <AppHeader title={pick.label} onBack={() => setPick(null)} />
        <div className="ph-body ph-form">
          <div className="ph-help">{pick.onDuty > 0 ? `${pick.onDuty} on duty. They see your message and location.` : 'Nobody is on duty right now. Your request waits in their queue.'}</div>
          <label>What do you need?<textarea maxLength={240} rows={5} value={text} onChange={(e) => setText(e.target.value)} placeholder="e.g. My car broke down on Route 68" /></label>
          <button className="ph-btn wide" disabled={text.trim().length < 3} onClick={() => void send()}><Icon name="send" size="0.9rem" /> Send request</button>
        </div>
      </div>
    );
  }
  return (
    <div className="ph-appview">
      <AppHeader title="Services" />
      <div className="ph-body">
        {data?.duty && (
          <div className="ph-seg">
            <button className={tab === 'call' ? 'on' : ''} onClick={() => setTab('call')}>Call a service</button>
            <button className={tab === 'queue' ? 'on' : ''} onClick={() => setTab('queue')}>Queue ({data.queue?.filter((q) => q.status === 'open').length ?? 0})</button>
          </div>
        )}
        {!data && <div className="ph-empty">Loading…</div>}
        {data && tab === 'call' && (
          <>
            <ul className="ph-list">
              {data.services.map((s) => (
                <li key={s.id}><button className="ph-row" onClick={() => setPick(s)}>
                  <span className="sv-ico"><Icon name={s.icon} size="1rem" /></span>
                  <span className="ph-row-main"><strong>{s.label}</strong><span className="muted">{s.onDuty > 0 ? `${s.onDuty} on duty` : 'Nobody on duty'}</span></span>
                  <span className={`sv-dot${s.onDuty > 0 ? ' on' : ''}`} />
                </button></li>
              ))}
            </ul>
            {data.mine.length > 0 && <div className="ph-section">Your requests</div>}
            <ul className="ph-list">
              {data.mine.map((m) => (
                <li key={m.id} className="ph-row-wrap">
                  <div className="ph-row static"><span className="ph-row-main"><strong>{data.services.find((s) => s.id === m.service)?.label ?? m.service}</strong>
                    <span className="muted">{m.status === 'taken' ? `${m.taken_by} is on the way` : 'Waiting'} · {timeAgo(m.at)}</span></span></div>
                  <button className="ph-icon-btn" aria-label="Cancel request" onClick={async () => { await api('serviceClose', m.id); void load(); }}><Icon name="close" size="0.9rem" /></button>
                </li>
              ))}
            </ul>
          </>
        )}
        {data && tab === 'queue' && (
          <ul className="ph-list">
            {(data.queue ?? []).length === 0 && <div className="ph-empty">No open requests.</div>}
            {(data.queue ?? []).map((q) => (
              <li key={q.id} className="sv-req">
                <div><strong>#{q.id} {q.caller_name}</strong> <span className="muted">{q.caller_number} · {timeAgo(q.at)}</span></div>
                <p>{q.message}</p>
                <div className="sv-actions">
                  {q.status === 'open'
                    ? <button className="ph-btn" onClick={async () => { const r = await api<{ x: number; y: number }>('serviceTake', q.id); if (r.ok && r.data) void nui('waypoint', r.data); toast(r.message ?? '', r.ok ? undefined : 'error'); void load(); }}>Take it</button>
                    : <span className="muted">Taken by {q.taken_by}</span>}
                  {q.x !== undefined && <button className="ph-btn ghost" onClick={() => void nui('waypoint', { x: q.x, y: q.y })}>GPS</button>}
                  <button className="ph-btn ghost" onClick={async () => { await api('serviceClose', q.id); void load(); }}>Close</button>
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
