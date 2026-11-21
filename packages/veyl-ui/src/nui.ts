// NUI messaging shared by every VeylCore app.
// Envelope (Lua -> NUI):  { action: string, session?: string, data?: any }
// Requests (NUI -> Lua):  POST https://<parent resource>/<action> with { v, requestId, session?, ...payload }
// Lua always resolves the callback with { ok, code?, message?, data? }.
import { useEffect, useRef } from 'react';

declare global {
  interface Window { GetParentResourceName?: () => string }
}

export const PROTOCOL_VERSION = 1;

/** True only in a normal browser (the development preview), never inside FiveM. */
export const isBrowserDev = (): boolean => typeof window.GetParentResourceName !== 'function';

export const resourceName = (): string => (isBrowserDev() ? 'veyl_dev' : window.GetParentResourceName!());

export interface NuiResponse<T = unknown> { ok: boolean; code?: string; message?: string; data?: T }
export interface Envelope<T = unknown> { action: string; session?: string; data?: T }

type DevHandler = (action: string, payload: Record<string, unknown>) => Promise<NuiResponse> | NuiResponse;
let devHandler: DevHandler | null = null;

/** Preview-only: route NUI requests to local fixtures. Ignored inside FiveM, so it can never fake success in production. */
export function setDevNuiHandler(handler: DevHandler | null) {
  if (isBrowserDev()) devHandler = handler;
}

/** Preview-only: deliver a Lua-style message to the app. */
export function devEmit<T>(action: string, data?: T, session?: string) {
  if (isBrowserDev()) window.postMessage({ action, data, session } satisfies Envelope<T>, '*');
}

let requestSeq = 0;
export const newRequestId = () => `${Date.now().toString(36)}-${(++requestSeq).toString(36)}`;
export const newOpId = () =>
  (typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`)
    .replace(/[^\w-]/g, '').slice(0, 64);

/** POST to a registered NUI callback of THIS resource. The browser names an action; Lua decides what it means. */
export async function nui<T = unknown>(action: string, payload: Record<string, unknown> = {}): Promise<NuiResponse<T>> {
  const body = { v: PROTOCOL_VERSION, requestId: newRequestId(), ...payload };
  if (isBrowserDev()) {
    if (!devHandler) return { ok: false, code: 'NO_BACKEND', message: 'Not running in FiveM' };
    return (await devHandler(action, body)) as NuiResponse<T>;
  }
  try {
    const res = await fetch(`https://${resourceName()}/${action}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body),
    });
    const text = await res.text();
    return text ? (JSON.parse(text) as NuiResponse<T>) : { ok: true };
  } catch (err) {
    return { ok: false, code: 'NUI_ERROR', message: String(err) };
  }
}

/** Subscribe to Lua messages of one action. Malformed envelopes are ignored. */
export function useNuiMessage<T = unknown>(action: string, handler: (data: T, envelope: Envelope<T>) => void): void {
  const ref = useRef(handler);
  ref.current = handler;
  useEffect(() => {
    const listener = (event: MessageEvent<Envelope<T>>) => {
      const env = event.data;
      if (!env || typeof env !== 'object' || typeof env.action !== 'string' || env.action !== action) return;
      if (env.session !== undefined && typeof env.session !== 'string') return;
      ref.current(env.data as T, env);
    };
    window.addEventListener('message', listener);
    return () => window.removeEventListener('message', listener);
  }, [action]);
}

/** Tell Lua the page booted, so a failed asset load is detected with a bounded timeout. */
export function announceReady(): void { void nui('ui:ready', {}); }
