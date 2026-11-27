import { nui, type NuiResponse } from '@veyl/ui';

export type Res<T = unknown> = NuiResponse<T>;

/** Call a server callback through the client's whitelist (`api` NUI callback). */
export const api = <T = unknown>(name: string, ...args: unknown[]): Promise<Res<T>> => nui<T>('api', { name, args });

/** A unique id for one send: the server never posts the same clientOp twice, so retries are safe. */
export const newOp = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`;

export const post = <T = unknown>(name: string, body: Record<string, unknown> = {}) => nui<T>(name, body);
