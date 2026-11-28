// Services: ask police, EMS, mechanics, taxis and businesses for help. On duty? Your queue is a tab here.
import { useState } from 'react';
import { api, post } from '../api';
import { Ico } from '../icons';
import { useStore } from '../store';
import { Avatar, Button, Empty, Header, Segmented, Sheet, TextInput, cx, say, toast } from '../ui';
import { Chip, Loaded, ago, useLoad } from './kit';

type Service = { id: string; label: string; icon: string; onDuty: number };
type Mine = { id: number; service: string; message: string; status: 'open' | 'taken' | 'closed'; taken_by: string | null; at: number };
type Queue = { id: number; caller_name: string; caller_number: string; message: string; status: 'open' | 'taken'; taken_by: string | null; x: number; y: number; at: number };
type Data = { services: Service[]; mine: Mine[]; duty: string | null; queue: Queue[] | null };

const ICON: Record<string, string> = { shield: 'shield', heart: 'heart', wrench: 'wrench', car: 'car', burger: 'bag' };
const COLOR: Record<string, string> = { police: '#3a7bf0', ems: '#e0576a', mechanic: '#d08b4f', taxi: '#f2b443', beanmachine: '#8a5a2b', burgershot: '#ef7a3a' };
const colorOf = (id: string) => COLOR[id] ?? '#8b63d6';

export function ServicesApp() {
  const load = useLoad(() => api<Data>('servicesData'));
  const settings = useStore((s) => s.settings);
  const [ask, setAsk] = useState<Service | null>(null);
  const [tab, setTab] = useState<'request' | 'queue'>('request');
  const labelOf = (id: string) => load.data?.services.find((s) => s.id === id)?.label ?? id;

  const close = async (id: number) => { if (say(await api('serviceClose', id))) void load.reload(); };
  const take = async (q: Queue) => {
    const r = await api<{ x: number; y: number }>('serviceTake', q.id);
    if (!say(r) || !r.data) return;
    await post('waypoint', r.data); void load.reload();
  };

  return (
    <div className="ph-app">
      <Header title="Services" right={load.data?.duty ? <Chip tone="ok" icon="shield">On duty</Chip> : undefined} />
      {load.data?.duty && <div className="ph-pad"><Segmented options={[{ id: 'request', label: 'Request help' }, { id: 'queue', label: `Queue (${load.data.queue?.length ?? 0})` }]} value={tab} onChange={setTab} /></div>}
      <div className="ph-scroll ph-pad">
        <Loaded {...load}>
          {(d) => (tab === 'queue' && d.duty) ? (
            <>
              {(d.queue ?? []).length === 0 && <Empty icon="check" title="Queue is clear" text="New requests for your service show up here." />}
              {(d.queue ?? []).map((q) => (
                <div key={q.id} className={cx('ph-req', q.status)}>
                  <Avatar name={q.caller_name} id={q.caller_number} size={40} />
                  <div className="ph-req-main"><strong>{q.caller_name}</strong><p>{q.message}</p><em>{ago(q.at)} ago{q.status === 'taken' ? ` · ${q.taken_by ?? 'someone'} is on it` : ''}</em></div>
                  <div className="ph-req-act">{q.status === 'open' && <Button kind="primary" onClick={() => void take(q)}>Take</Button>}<button className="ph-iconmini" onClick={() => void close(q.id)} aria-label="Close request"><Ico name="check" size={15} /></button></div>
                </div>
              ))}
            </>
          ) : (
            <>
              <div className="ph-svcgrid">
                {d.services.map((s) => (
                  <button key={s.id} className="ph-svc" onClick={() => setAsk(s)}>
                    <span className="ph-svc-ico" style={{ background: colorOf(s.id) }}><Ico name={ICON[s.icon] ?? 'shield'} size={24} /></span>
                    <strong>{s.label}</strong>
                    <Chip tone={s.onDuty > 0 ? 'ok' : undefined}>{s.onDuty > 0 ? `${s.onDuty} on duty` : 'Nobody on duty'}</Chip>
                  </button>
                ))}
              </div>
              {d.mine.length > 0 && (
                <section className="ph-mine">
                  <h4>Your requests</h4>
                  {d.mine.map((m) => (
                    <div key={m.id} className="ph-minereq">
                      <span className="ph-place-ico" style={{ background: colorOf(m.service) }}><Ico name={ICON[d.services.find((s) => s.id === m.service)?.icon ?? 'shield'] ?? 'shield'} size={15} /></span>
                      <span><strong>{labelOf(m.service)}</strong><em>{m.message}</em></span>
                      <Chip tone={m.status === 'taken' ? 'ok' : 'warn'}>{m.status === 'taken' ? `${m.taken_by ?? 'On the way'}` : 'Waiting'}</Chip>
                      <button className="ph-iconmini" onClick={() => void close(m.id)} aria-label="Cancel request"><Ico name="x" size={14} /></button>
                    </div>
                  ))}
                </section>
              )}
              <p className="ph-hint center">{settings.dnd ? 'Do Not Disturb is on, but requests still go through.' : 'For real emergencies in the city, call a service. Misuse is logged.'}</p>
            </>
          )}
        </Loaded>
      </div>
      {ask && <RequestSheet s={ask} onClose={() => setAsk(null)} onSent={() => { setAsk(null); void load.reload(); }} />}
    </div>
  );
}

function RequestSheet({ s, onClose, onSent }: { s: Service; onClose: () => void; onSent: () => void }) {
  const [msg, setMsg] = useState('');
  const [busy, setBusy] = useState(false);
  const send = async () => {
    setBusy(true);
    const r = await api('serviceRequest', s.id, msg);
    setBusy(false);
    if (say(r)) { if (!r.message) toast('Request sent'); onSent(); }
  };
  return (
    <Sheet title={s.label} onClose={onClose}>
      <div className="ph-form">
        <div className="ph-svc-head"><span className="ph-svc-ico" style={{ background: colorOf(s.id) }}><Ico name={ICON[s.icon] ?? 'shield'} size={24} /></span><span><strong>{s.onDuty > 0 ? `${s.onDuty} on duty right now` : 'Nobody on duty right now'}</strong><em>{s.onDuty > 0 ? 'They get your message and location.' : 'It stays in the queue for when someone starts.'}</em></span></div>
        <label>What do you need?<TextInput multiline value={msg} onChange={setMsg} placeholder="Describe the situation and where you are" maxLength={240} autoFocus /></label>
        <Button kind="primary" block disabled={msg.trim().length < 3 || busy} onClick={send}>{busy ? 'Sending...' : 'Send request'}</Button>
        <p className="ph-hint">Your position is shared with them when you send.</p>
      </div>
    </Sheet>
  );
}
