import type { NuiResponse } from '@veyl/ui';
import type { TabletState } from './types';

export type Tab = 'dashboard' | 'contracts' | 'active' | 'vehicles' | 'reputation' | 'crew' | 'heat' | 'stats' | 'help';

/** What every screen gets: the server's state and the few things it may do. All of them go through the server. */
export interface Ctx {
  s: TabletState;
  go: (t: Tab) => void;
  /** Calls a server callback, shows its message, then refreshes the state. */
  run: (name: string, ...args: unknown[]) => Promise<NuiResponse<unknown>>;
  refresh: () => Promise<void>;
  waypoint: (x: number, y: number) => void;
  busy: boolean;
}
