// App Store: install and remove the optional built-in apps (the server stores the choice per character).
import { useState } from 'react';
import { api } from '../api';
import { Ico } from '../icons';
import { setState, useStore } from '../store';
import { APP_LOOK, AppIcon, Button, Empty, Group, Header, say } from '../ui';
import { VIEWS } from './index';
import type { App } from '../types';

export function StoreApp() {
  const hello = useStore((s) => s.hello);
  const [busy, setBusy] = useState<string | null>(null);
  const apps = (hello?.apps ?? []).filter((a) => !a.core && VIEWS[a.id]);

  const toggle = async (a: App) => {
    setBusy(a.id);
    const res = await api<{ apps: App[] }>('appInstall', a.id, !a.installed);
    setBusy(null);
    if (say(res) && res.data && hello) {
      setState({ hello: { ...hello, apps: res.data.apps } });
      if (a.installed) setState((s) => ({ app: s.app })); // stays here; the home screen updates from hello.apps
    }
  };

  return (
    <div className="ph-app">
      <Header title="App Store" />
      <div className="ph-scroll ph-pad">
        <div className="ph-hero">
          <Ico name="bag" size={26} />
          <div><strong>Make it yours</strong><span>Install what you use. Apps from the city, like Apartments, appear on their own.</span></div>
        </div>
        {apps.length === 0 && <Empty icon="bag" title="Nothing to install" text="Every available app is already part of your phone." />}
        {apps.length > 0 && (
          <Group title="Apps">
            {apps.map((a) => {
              const look = APP_LOOK[a.id] ?? { icon: 'box', color: '#555a6a' };
              return (
                <div key={a.id} className="ph-storeapp">
                  <AppIcon icon={look.icon} color={look.color} size={50} />
                  <span className="ph-storeapp-text"><strong>{a.label}</strong><span>{a.description}</span></span>
                  <Button kind={a.installed ? 'ghost' : 'primary'} onClick={() => toggle(a)} disabled={busy === a.id}>{a.installed ? 'Remove' : 'Get'}</Button>
                </div>
              );
            })}
          </Group>
        )}
      </div>
    </div>
  );
}
