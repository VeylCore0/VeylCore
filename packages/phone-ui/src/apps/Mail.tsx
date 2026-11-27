// Mail: one-way mail from the city and businesses (receipts, bills, offers).
import { useCallback, useEffect, useState } from 'react';
import { api } from '../api';
import { onPush } from '../controller';
import { listTime, timeOfDay } from '../format';
import { useBack, useRouteOnce } from '../nav';
import { setState, useStore } from '../store';
import { Avatar, Button, Empty, Header, IconButton, Spinner, cx, say } from '../ui';
import type { MailFull, MailItem } from '../types';

export function MailApp({ route }: { route?: string }) {
  const [items, setItems] = useState<MailItem[] | null>(null);
  const [more, setMore] = useState(false);
  const [failed, setFailed] = useState(false);
  const [open, setOpen] = useState<MailFull | null>(null);
  const unread = useStore((s) => s.unread.mail);

  const load = useCallback(async () => {
    const r = await api<{ items: MailItem[]; unread: number; more: boolean }>('mailList');
    if (!r.ok || !r.data) { setFailed(true); return; }
    setFailed(false); setItems(r.data.items); setMore(r.data.more);
    setState((s) => ({ unread: { ...s.unread, mail: r.data!.unread } }));
  }, []);
  useEffect(() => { void load(); }, [load]);
  useEffect(() => onPush((e) => { if (e.event === 'mail') setItems((l) => (l ? [e.data.mail, ...l.filter((m) => m.id !== e.data.mail.id)] : l)); }), []);
  useRouteOnce(route, () => undefined);
  useBack(!!open, () => { setOpen(null); return true; });

  const loadMore = async () => {
    const last = items?.[items.length - 1];
    if (!last) return;
    const r = await api<{ items: MailItem[]; more: boolean }>('mailList', last.id);
    if (r.ok && r.data) { setItems((l) => [...(l ?? []), ...r.data!.items]); setMore(r.data.more); }
  };
  const read = async (m: MailItem) => {
    const r = await api<MailFull>('mailRead', m.id);
    if (!say(r) || !r.data) return;
    setOpen(r.data);
    setItems((l) => l?.map((x) => (x.id === m.id ? { ...x, read: true } : x)) ?? null);
    if (r.data.unread !== undefined) setState((s) => ({ unread: { ...s.unread, mail: r.data!.unread! } }));
  };
  const del = async (id: number) => {
    const r = await api<{ unread: number }>('mailDelete', id);
    if (!say(r)) return;
    setOpen(null);
    setItems((l) => l?.filter((x) => x.id !== id) ?? null);
    if (r.data) setState((s) => ({ unread: { ...s.unread, mail: r.data!.unread } }));
  };

  if (open) {
    return (
      <div className="ph-app">
        <Header onBack={() => setOpen(null)} backLabel="Inbox" right={<IconButton icon="trash" label="Delete" tone="danger" onClick={() => del(open.id)} />} large={false} />
        <div className="ph-scroll ph-mail-open">
          <h2>{open.subject}</h2>
          <div className="ph-mail-from"><Avatar name={open.from} id={open.from} size={38} /><span><strong>{open.from}</strong><em>{listTime(open.time)} · {timeOfDay(open.time)}</em></span></div>
          <p className="ph-mail-body">{open.body}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="ph-app">
      <Header title="Mail" right={unread > 0 ? <span className="ph-pill">{unread} unread</span> : undefined} />
      <div className="ph-scroll">
        {items === null && !failed && <Spinner />}
        {failed && !items && <Empty icon="x" title="Could not load mail" action={<Button onClick={load}>Try again</Button>} />}
        {items?.length === 0 && <Empty icon="mail" title="Inbox is empty" text="Receipts, bills and job offers will land here." />}
        <ul className="ph-list">
          {items?.map((m) => (
            <li key={m.id}>
              <button className="ph-mail" onClick={() => read(m)}>
                <i className={cx('ph-udot', !m.read && 'on')} />
                <span className="ph-mail-main">
                  <span className="ph-conv-top"><strong>{m.from}</strong><time>{listTime(m.time)}</time></span>
                  <span className={cx('ph-mail-subj', !m.read && 'unread')}>{m.subject}</span>
                  <span className="ph-mail-prev">{m.preview.replace(/\s+/g, ' ')}</span>
                </span>
              </button>
            </li>
          ))}
        </ul>
        {more && <button className="ph-more" onClick={loadMore}>Load older mail</button>}
      </div>
    </div>
  );
}
