import { useEffect, useRef, useState } from 'react';
import { Panel, type AlertOpen } from '@veyl/ui';
import { sendResult } from './App';

export function Alert({ data }: { data: AlertOpen }) {
  const [pending, setPending] = useState(false);
  const confirmRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    setPending(false);
    setTimeout(() => confirmRef.current?.focus(), 30);
  }, [data]);

  const answer = (confirmed: boolean) => {
    if (pending) return;
    setPending(true);
    void sendResult(data.token, { type: confirmed ? 'confirm' : 'cancel' });
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') answer(false); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  return (
    <Panel
      title={data.title}
      width={400}
      footer={
        <>
          <button className="v-btn" onClick={() => answer(false)} disabled={pending}>{data.cancelLabel ?? 'Cancel'}</button>
          <button ref={confirmRef} className={`v-btn ${data.destructive ? 'danger' : 'primary'}`} onClick={() => answer(true)} disabled={pending}>
            {data.confirmLabel ?? 'Confirm'}
          </button>
        </>
      }
    >
      <p style={{ margin: '4px 0 8px', lineHeight: 1.5 }}>{data.message}</p>
    </Panel>
  );
}
