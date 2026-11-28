import type { NuiResponse } from '@veyl/ui';
import type { TabletState } from './types';

export type Page = 'dashboard' | 'botanical' | 'production' | 'properties' | 'progression' | 'stats';

/** What every page gets: the server's state and the few things it may do. All of them go through the server. */
export interface Ctx {
  s: TabletState;
  go: (p: Page) => void;
  /** Calls a server callback, shows its message, then refreshes the state. */
  run: (name: string, ...args: unknown[]) => Promise<NuiResponse<unknown>>;
  refresh: () => Promise<void>;
  waypoint: (x: number, y: number) => void;
  busy: boolean;
}
