import { useEffect, useState } from 'react';
import {
  announceReady, nui, useNuiMessage,
  type AlertOpen, type FormOpen, type MenuOpen, type NotifyMessage, type ProgressMessage, type TextUIMessage,
} from '@veyl/ui';
import { Menu } from './Menu';
import { Form } from './Form';
import { Alert } from './Alert';
import { Notifications } from './Notifications';
import { Progress } from './Progress';
import { TextUI } from './TextUI';

type Modal =
  | { kind: 'menu'; data: MenuOpen }
  | { kind: 'form'; data: FormOpen }
  | { kind: 'alert'; data: AlertOpen }
  | null;

export function App() {
  const [modal, setModal] = useState<Modal>(null);
  const [notifications, setNotifications] = useState<NotifyMessage[]>([]);
  const [progress, setProgress] = useState<ProgressMessage | null>(null);
  const [textUI, setTextUI] = useState<TextUIMessage | null>(null);

  useEffect(() => announceReady(), []);

  useNuiMessage<MenuOpen>('menu:open', (data) => setModal({ kind: 'menu', data }));
  useNuiMessage<FormOpen>('form:open', (data) => setModal({ kind: 'form', data }));
  useNuiMessage<AlertOpen>('alert:open', (data) => setModal({ kind: 'alert', data }));
  useNuiMessage('modal:close', () => setModal(null));

  useNuiMessage<NotifyMessage>('notify', (n) => {
    setNotifications((list) => {
      // Merge an identical message that is still visible instead of stacking duplicates.
      const dup = list.find((x) => x.message === n.message && x.type === n.type);
      const next = dup ? list.map((x) => (x === dup ? { ...n, id: dup.id + '+' } : x)) : [...list, n];
      return next.slice(-5);
    });
  });
  const dismiss = (id: string) => setNotifications((list) => list.filter((x) => x.id !== id));

  useNuiMessage<ProgressMessage>('progress:start', setProgress);
  useNuiMessage('progress:stop', () => setProgress(null));
  useNuiMessage<TextUIMessage>('textui:show', setTextUI);
  useNuiMessage('textui:hide', () => setTextUI(null));
  useNuiMessage('reset', () => {
    setModal(null);
    setProgress(null);
    setTextUI(null);
  });

  return (
    <>
      <Notifications items={notifications} onDone={dismiss} />
      {progress && <Progress {...progress} />}
      {textUI && <TextUI data={textUI} />}
      {modal && (
        <div className="backdrop">
          {modal.kind === 'menu' && <Menu data={modal.data} />}
          {modal.kind === 'form' && <Form data={modal.data} />}
          {modal.kind === 'alert' && <Alert data={modal.data} />}
        </div>
      )}
    </>
  );
}

/** Every modal result goes through one callback with its ownership token. */
export function sendResult(token: string, result: Record<string, unknown>) {
  return nui('modal:result', { token, ...result });
}
