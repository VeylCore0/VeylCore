import { useMemo } from 'react';
import { useStore } from './store';
import { openApp } from './controller';
import { clockSuffix, clockText } from './format';
import { Ico } from './icons';
import { APP_LOOK, AppIcon } from './ui';
import { VIEWS } from './apps';
import type { Hello, ExternalApp, Settings } from './types';

export type Tile = { id: string; label: string; icon: string; color: string };

/** Built-in apps this UI implements and the character has installed, plus apps other resources registered. */
export function buildTiles(hello: Hello | null, settings: Settings, external: ExternalApp[]) {
  const dock: Tile[] = [], rest: Tile[] = [];
  for (const a of hello?.apps ?? []) {
    if (!a.installed || !VIEWS[a.id]) continue;
    const look = APP_LOOK[a.id] ?? { icon: 'box', color: '#555a6a' };
    (a.dock ? dock : rest).push({ id: a.id, label: a.label, icon: look.icon, color: look.color });
  }
  for (const e of external) rest.push({ id: e.id, label: e.label, icon: e.icon, color: e.color });
  const order = new Map(settings.home.map((id, i) => [id, i] as const));
  rest.sort((a, b) => (order.get(a.id) ?? 999) - (order.get(b.id) ?? 999));
  return { dock, grid: rest };
}

const WEATHER: Record<string, { text: string; icon: string }> = {
  CLEAR: { text: 'Clear', icon: 'sun' }, EXTRASUNNY: { text: 'Sunny', icon: 'sun' },
  CLOUDS: { text: 'Cloudy', icon: 'cloud' }, OVERCAST: { text: 'Overcast', icon: 'cloud' },
  RAIN: { text: 'Rain', icon: 'rain' }, CLEARING: { text: 'Clearing', icon: 'rain' }, THUNDER: { text: 'Thunderstorm', icon: 'rain' },
  SMOG: { text: 'Smog', icon: 'cloud' }, FOGGY: { text: 'Foggy', icon: 'cloud' },
  SNOW: { text: 'Snow', icon: 'cloud' }, BLIZZARD: { text: 'Blizzard', icon: 'cloud' }, SNOWLIGHT: { text: 'Light snow', icon: 'cloud' }, XMAS: { text: 'Snow', icon: 'cloud' },
};

export function Home() {
  const hello = useStore((s) => s.hello);
  const settings = useStore((s) => s.settings);
  const external = useStore((s) => s.external);
  const unread = useStore((s) => s.unread);
  const badges = useStore((s) => s.badges);
  const world = useStore((s) => s.world);
  const locked = useStore((s) => !!s.hello?.locked);
  const { dock, grid } = useMemo(() => buildTiles(hello, settings, external), [hello, settings, external]);
  const w = world?.weather ? WEATHER[world.weather.toUpperCase()] ?? { text: world.weather, icon: 'cloud' } : null;
  const badgeOf = (id: string) => (id === 'messages' ? unread.messages : id === 'mail' ? unread.mail : badges[id] ?? 0);

  if (locked) return null; // a locked phone shows nothing of itself behind the PIN screen
  return (
    <div className="ph-home">
      <div className="ph-home-scroll">
        <section className="ph-w ph-w-time" aria-label="Time and weather">
          <div>
            <div className="ph-w-clock">{world ? clockText(world.hour, world.minute) : '--:--'}<small>{world ? clockSuffix(world.hour) : ''}</small></div>
            <div className="ph-w-sub">{hello ? `Hi, ${hello.name.split(' ')[0]}` : 'Los Santos'}</div>
          </div>
          {w && <div className="ph-w-weather"><Ico name={w.icon} size={30} stroke={1.5} /><span>{w.text}</span></div>}
        </section>
        <div className="ph-w-row">
          <button className="ph-w ph-w-mini" onClick={() => openApp('messages')}>
            <span className="ph-w-ico" style={{ background: APP_LOOK.messages.color }}><Ico name="chat" size={16} /></span>
            <strong>{unread.messages}</strong><span>unread {unread.messages === 1 ? 'message' : 'messages'}</span>
          </button>
          <button className="ph-w ph-w-mini" onClick={() => openApp('mail')}>
            <span className="ph-w-ico" style={{ background: APP_LOOK.mail.color }}><Ico name="mail" size={16} /></span>
            <strong>{unread.mail}</strong><span>unread {unread.mail === 1 ? 'mail' : 'mails'}</span>
          </button>
        </div>
        <div className="ph-grid">
          {grid.map((t) => (
            <button key={t.id} className="ph-tile" onClick={() => openApp(t.id)}>
              <AppIcon icon={t.icon} color={t.color} badge={badgeOf(t.id)} />
              <span>{t.label}</span>
            </button>
          ))}
        </div>
      </div>
      <nav className="ph-dock" aria-label="Dock">
        {dock.map((t) => (
          <button key={t.id} className="ph-dock-btn" onClick={() => openApp(t.id)} aria-label={t.label}>
            <AppIcon icon={t.icon} color={t.color} badge={badgeOf(t.id)} />
          </button>
        ))}
      </nav>
    </div>
  );
}
