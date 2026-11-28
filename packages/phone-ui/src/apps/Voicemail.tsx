// Voicemail: messages people left when you could not answer, and leaving your own.
import { useState } from 'react';
import { api } from '../api';
import { openApp, startCall } from '../controller';
import { formatDigits, listTime } from '../format';
import { Ico } from '../icons';
import { Avatar, Button, Empty, Header, IconButton, Sheet, TextInput, cx, say } from '../ui';
import { Loaded, useLoad } from './kit';

type VM = { id: number; from_number: string; from_name: string | null; body: string; is_read: number; at: number };

export function VoicemailApp() {
  const load = useLoad(() => api<VM[]>('voicemailList'));
  const [open, setOpen] = useState<VM | null>(null);
  const [leave, setLeave] = useState(false);
  const unread = load.data?.filter((v) => !v.is_read).length ?? 0;
  const nameOf = (v: VM) => v.from_name || formatDigits(v.from_number);

  const view = async (v: VM) => {
    setOpen(v);
    if (!v.is_read) { await api('voicemailRead', v.id); load.setData((l) => l?.map((x) => (x.id === v.id ? { ...x, is_read: 1 } : x)) ?? null); }
  };
  const remove = async (v: VM) => { if (say(await api('voicemailDelete', v.id))) { setOpen(null); load.setData((l) => l?.filter((x) => x.id !== v.id) ?? null); } };

  return (
    <div className="ph-app">
      <Header title="Voicemail" right={<><IconButton icon="mic" label="Leave a voicemail" tone="accent" onClick={() => setLeave(true)} /></>} />
      <div className="ph-scroll">
        <Loaded {...load}>
          {(list) => list.length === 0
            ? <Empty icon="mic" title="No voicemail" text="When you miss a call, people can leave you a message here." />
            : (
              <>
                {unread > 0 && <p className="ph-vmcount">{unread} new</p>}
                <ul className="ph-list">
                  {list.map((v) => (
                    <li key={v.id}>
                      <button className={cx('ph-vm', !v.is_read && 'unread')} onClick={() => void view(v)}>
                        <i className="ph-udot on" style={{ visibility: v.is_read ? 'hidden' : 'visible' }} />
                        <Avatar name={v.from_name ?? ''} id={v.from_number} size={42} />
                        <span className="ph-vm-main"><span className="ph-conv-top"><strong>{nameOf(v)}</strong><time>{listTime(v.at)}</time></span><span className="ph-vm-body">{v.body}</span></span>
                      </button>
                    </li>
                  ))}
                </ul>
              </>
            )}
        </Loaded>
      </div>
      {open && (
        <Sheet title="Voicemail" onClose={() => setOpen(null)}>
          <div className="ph-info-head"><Avatar name={open.from_name ?? ''} id={open.from_number} size={64} /><strong>{nameOf(open)}</strong><span className="ph-sub">{formatDigits(open.from_number)} · {listTime(open.at)}</span></div>
          <div className="ph-vm-full"><Ico name="mic" size={16} /><p>{open.body}</p></div>
          <div className="ph-info-actions">
            <button onClick={() => { setOpen(null); void startCall(open.from_number); }}><Ico name="phone" size={20} /><span>Call back</span></button>
            <button onClick={() => { setOpen(null); openApp('messages', `to/${open.from_number}`); }}><Ico name="chat" size={20} /><span>Message</span></button>
            <button onClick={() => void remove(open)}><Ico name="trash" size={20} style={{ color: 'var(--ph-red)' }} /><span>Delete</span></button>
          </div>
        </Sheet>
      )}
      {leave && <LeaveSheet onClose={() => setLeave(false)} />}
    </div>
  );
}

function LeaveSheet({ onClose }: { onClose: () => void }) {
  const [number, setNumber] = useState('');
  const [body, setBody] = useState('');
  const [busy, setBusy] = useState(false);
  const ok = number.replace(/\D/g, '').length === 7 && body.trim().length >= 2 && !busy;
  const send = async () => { setBusy(true); const r = await api('voicemailLeave', number, body); setBusy(false); if (say(r)) onClose(); };
  return (
    <Sheet title="Leave a voicemail" onClose={onClose}>
      <div className="ph-form">
        <label>To<TextInput value={formatDigits(number)} onChange={setNumber} placeholder="555-1234" inputMode="tel" autoFocus /></label>
        <label>Message<TextInput multiline value={body} onChange={setBody} placeholder="Say what you would say after the beep" maxLength={500} /></label>
        <Button kind="primary" block onClick={send} disabled={!ok}>Send voicemail</Button>
      </div>
    </Sheet>
  );
}
