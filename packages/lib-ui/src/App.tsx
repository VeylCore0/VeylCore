import { useEffect, useState } from 'react';
import {
  announceReady, nui, useNuiMessage,
  type AlertOpen, type FormOpen, type MenuOpen, type TextUIMessage,
} from '@veyl/ui';
import { Menu } from './Menu';
import { Form } from './Form';
import { Alert } from './Alert';
import { Notifications, useNotifications, type Note } from './Notifications';
import { HoldCard, ProgressCard, type ActionStart, type ActionState } from './Progress';
import { themeVars, type UIConfig } from './glyphs';
import { TextUI } from './TextUI';

type Modal =
  | { kind: 'menu'; data: MenuOpen }
  | { kind: 'form'; data: FormOpen }
  | { kind: 'alert'; data: AlertOpen }
  | null;

export function App() {
  const [modal, setModal] = useState<Modal>(null);
  const [cfg, setCfg] = useState<UIConfig | undefined>(undefined);
  const notes = useNotifications(cfg?.Notifications);
  const [action, setAction] = useState<ActionState | null>(null);
  const [textUI, setTextUI] = useState<TextUIMessage | null>(null);

  useEffect(() => announceReady(), []);

  useNuiMessage<MenuOpen>('menu:open', (data) => setModal({ kind: 'menu', data }));
  useNuiMessage<FormOpen>('form:open', (data) => setModal({ kind: 'form', data }));
  useNuiMessage<AlertOpen>('alert:open', (data) => setModal({ kind: 'alert', data }));
  useNuiMessage('modal:close', () => setModal(null));

  useNuiMessage<UIConfig>('ui:config', setCfg);
  useNuiMessage<Note>('notify', notes.push);
  useNuiMessage<Partial<Note> & { id: string }>('notify:update', notes.update);
  useNuiMessage<{ id: string }>('notify:dismiss', (d) => notes.dismiss(d.id));
  useNuiMessage('notify:dismissNewest', notes.dismissNewest);
  useNuiMessage('notify:clear', notes.clear);

  // Actions: messages for an id that is no longer current are ignored.
  useNuiMessage<ActionStart>('progress:start', (a) => setAction({ ...a, kind: 'timed', startedAt: performance.now() }));
  useNuiMessage<ActionStart>('hold:start', (a) => setAction({ ...a, kind: 'hold', startedAt: performance.now(), progress: 0 }));
  useNuiMessage<{ id: string; progress: number }>('hold:update', (u) => setAction((a) => (a && a.id === u.id && !a.result ? { ...a, progress: Math.max(0, Math.min(1, u.progress)) } : a)));
  useNuiMessage<{ id: string; completed: boolean }>('progress:end', (e) => {
    setAction((a) => (a && a.id === e.id ? { ...a, result: e.completed ? 'completed' : 'cancelled' } : a));
    const keep = e.completed ? (cfg?.Progress.completeMs ?? 900) : 250;
    window.setTimeout(() => setAction((a) => (a && a.id === e.id ? null : a)), keep);
  });
  useNuiMessage<TextUIMessage>('textui:show', setTextUI);
  useNuiMessage('textui:hide', () => setTextUI(null));
  useNuiMessage('reset', () => {
    setModal(null);
    setAction(null);
    notes.clear();
    setTextUI(null);
  });

  return (
    <>
      <div className={`vn-root${cfg?.Theme.reducedMotion ? ' still' : ''}`} style={themeVars(cfg?.Theme)}>
        <Notifications cards={notes.cards} cfg={cfg?.Notifications} interactive={!!modal} onClose={notes.dismiss} />
        {action && (action.kind === 'hold' ? <HoldCard a={action} cfg={cfg?.Progress} /> : <ProgressCard a={action} cfg={cfg?.Progress} />)}
      </div>
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
