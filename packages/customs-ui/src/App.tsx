import { useCallback, useEffect, useRef, useState } from 'react';
import { announceReady, nui, useNuiMessage } from '@veyl/ui';
import { Customize, type CustomizeData } from './Customize';
import { Dashboard } from './Dashboard';
import { Approval } from './Approval';

export type Toast = (msg: string, err?: boolean) => void;

/** Hidden by default; one of three views is shown when Lua opens the page. */
export function App() {
  const [state, setState] = useState<{ view: string; data: any; session?: string } | null>(null);
  const [toast, setToast] = useState<{ msg: string; err: boolean } | null>(null);
  const timer = useRef<number>();
  useEffect(() => announceReady(), []);

  useNuiMessage<any>('customs:open', (data, env) => setState({ view: data.view, data, session: env.session }));
  useNuiMessage('customs:close', () => setState(null));

  const say: Toast = useCallback((msg, err = false) => {
    if (!msg) return;
    setToast({ msg, err });
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setToast(null), 3200);
  }, []);
  const close = useCallback(() => { void nui('closeUi'); }, []);

  if (!state) return null;
  return (
    <div className={state.data?.reduced ? 'reduced' : ''}>
      {state.view === 'customize' && <Customize key={state.data.session} d={state.data as CustomizeData} say={say} close={close} />}
      {state.view === 'dashboard' && <Dashboard initial={state.data.data} shopId={state.data.shopId} say={say} close={close} />}
      {state.view === 'approval' && <Approval data={state.data.data} say={say} close={close} />}
      {toast && <div className={`toast${toast.err ? ' err' : ''}`} role="status">{toast.msg}</div>}
    </div>
  );
}
