// Jobs: clock in and out, switch main job, browse the city job board and apply; bosses read applications.
import { useState } from 'react';
import { api } from '../api';
import { openApp, startCall } from '../controller';
import { formatDigits } from '../format';
import { Ico } from '../icons';
import { Avatar, Button, Empty, Header, Segmented, Sheet, TextInput, cx, say } from '../ui';
import { Chip, Loaded, ago, usd, useLoad } from './kit';

type Mine = { name: string; label: string; grade: string; pay: number; primary: boolean };
type Board = { job: string; label: string; description?: string; open: boolean; apply?: boolean; member: boolean };
type AppRow = { id: number; job: string; status: string; at: number };
type Inbox = { id: number; name: string; number: string; message: string; status: string; at: number };
type Data = { mine: Mine[]; primary: string; onduty: boolean; jobLabel: string; board: Board[]; apps: AppRow[]; inbox?: Inbox[] };

export function JobsApp() {
  const load = useLoad(() => api<Data>('jobsData'));
  const [tab, setTab] = useState<'mine' | 'board' | 'inbox'>('mine');
  const [apply, setApply] = useState<Board | null>(null);
  const [read, setRead] = useState<Inbox | null>(null);
  const act = async (p: ReturnType<typeof api>) => { if (say(await p)) void load.reload(); };
  const labelOf = (id: string, d: Data) => d.board.find((b) => b.job === id)?.label ?? id;

  return (
    <div className="ph-app">
      <Header title="Jobs" />
      <Loaded {...load}>
        {(d) => (
          <>
            <div className="ph-pad">
              <div className={cx('ph-dutycard', d.onduty && 'on')}>
                <span className="ph-duty-ico"><Ico name="briefcase" size={22} /></span>
                <span className="ph-duty-main"><strong>{d.jobLabel || 'Unemployed'}</strong><em>{d.primary === 'unemployed' ? 'Find work on the job board' : d.onduty ? 'You are on duty' : 'You are off duty'}</em></span>
                {d.primary !== 'unemployed' && <button className="ph-duty-btn" onClick={() => void act(api('jobsDuty'))}>{d.onduty ? 'Clock out' : 'Clock in'}</button>}
              </div>
              <Segmented options={[{ id: 'mine', label: 'My jobs' }, { id: 'board', label: 'Job board' }, ...(d.inbox ? [{ id: 'inbox' as const, label: `Applicants${d.inbox.length ? ` (${d.inbox.length})` : ''}` }] : [])]} value={tab} onChange={setTab} />
            </div>
            <div className="ph-scroll ph-pad">
              {tab === 'mine' && (
                <>
                  {d.mine.length === 0 && <Empty icon="briefcase" title="No jobs" text="Apply for one on the job board." />}
                  {d.mine.map((j) => (
                    <div key={j.name} className="ph-jobrow">
                      <span className="ph-place-ico" style={{ background: j.primary ? '#8b63d6' : '#59607a' }}><Ico name="briefcase" size={16} /></span>
                      <span className="ph-jobrow-main"><strong>{j.label}</strong><em>{j.grade} · {usd(j.pay)} per paycheck</em></span>
                      {j.primary ? <Chip tone="accent">Main job</Chip> : <button className="ph-link" onClick={() => void act(api('jobsPrimary', j.name))}>Make main</button>}
                    </div>
                  ))}
                  {d.apps.length > 0 && (
                    <section className="ph-mine"><h4>Your applications</h4>
                      {d.apps.map((a) => (
                        <div key={a.id} className="ph-jobrow slim">
                          <span className="ph-jobrow-main"><strong>{labelOf(a.job, d)}</strong><em>{ago(a.at)} ago</em></span>
                          <Chip tone={a.status === 'accepted' ? 'ok' : a.status === 'closed' ? undefined : 'warn'}>{a.status === 'closed' ? 'Closed' : a.status === 'accepted' ? 'Accepted' : 'Pending'}</Chip>
                        </div>
                      ))}
                    </section>
                  )}
                </>
              )}
              {tab === 'board' && (
                <>
                  {d.board.length === 0 && <Empty icon="briefcase" title="Nothing listed" text="No jobs are advertised right now." />}
                  {d.board.map((b) => (
                    <div key={b.job} className="ph-boardcard">
                      <div className="ph-boardcard-top"><strong>{b.label}</strong><Chip tone={b.open ? 'ok' : undefined}>{b.open ? 'Hiring' : 'By application'}</Chip></div>
                      {b.description && <p>{b.description}</p>}
                      {b.member ? <Chip icon="check" tone="ok">You work here</Chip> : <Button kind="primary" block onClick={() => setApply(b)}>{b.open ? 'Apply now' : 'Send application'}</Button>}
                    </div>
                  ))}
                </>
              )}
              {tab === 'inbox' && d.inbox && (
                <>
                  {d.inbox.length === 0 && <Empty icon="mail" title="No applicants" text="Applications to your business show up here." />}
                  {d.inbox.map((i) => (
                    <button key={i.id} className="ph-applicant" onClick={() => setRead(i)}>
                      <Avatar name={i.name} id={i.number} size={42} />
                      <span><strong>{i.name}</strong><em>{i.message}</em></span><time>{ago(i.at)}</time>
                    </button>
                  ))}
                </>
              )}
            </div>
          </>
        )}
      </Loaded>
      {apply && <ApplySheet b={apply} onClose={() => setApply(null)} onDone={() => { setApply(null); void load.reload(); }} />}
      {read && (
        <Sheet title="Application" onClose={() => setRead(null)}>
          <div className="ph-info-head"><Avatar name={read.name} id={read.number} size={64} /><strong>{read.name}</strong><span className="ph-sub">{formatDigits(read.number)}</span></div>
          <div className="ph-vm-full"><Ico name="briefcase" size={16} /><p>{read.message}</p></div>
          <div className="ph-info-actions">
            <button onClick={() => { setRead(null); void startCall(read.number); }}><Ico name="phone" size={20} /><span>Call</span></button>
            <button onClick={() => { setRead(null); openApp('messages', `to/${read.number}`); }}><Ico name="chat" size={20} /><span>Message</span></button>
            <button onClick={async () => { if (say(await api('jobsAppClose', read.id))) { setRead(null); void load.reload(); } }}><Ico name="check" size={20} /><span>Close</span></button>
          </div>
        </Sheet>
      )}
    </div>
  );
}

function ApplySheet({ b, onClose, onDone }: { b: Board; onClose: () => void; onDone: () => void }) {
  const [msg, setMsg] = useState('');
  const [busy, setBusy] = useState(false);
  const send = async () => { setBusy(true); const r = await api('jobsApply', b.job, msg); setBusy(false); if (say(r)) onDone(); };
  return (
    <Sheet title={`Apply: ${b.label}`} onClose={onClose}>
      <div className="ph-form">
        <label>Tell them about yourself<TextInput multiline value={msg} onChange={setMsg} placeholder="Experience, availability, why you would be great" maxLength={400} autoFocus /></label>
        <Button kind="primary" block disabled={msg.trim().length < 10 || busy} onClick={send}>Send application</Button>
      </div>
    </Sheet>
  );
}
