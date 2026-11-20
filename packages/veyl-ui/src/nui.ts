// NUI messaging helpers shared by every VeylCore app.
import { useEffect, useRef } from 'react';

declare global {
  interface Window {
    GetParentResourceName?: () => string;
  }
}

export const resourceName = (): string =>
  typeof window.GetParentResourceName === 'function' ? window.GetParentResourceName() : 'veyl_dev';

export const isBrowserDev = (): boolean => typeof window.GetParentResourceName !== 'function';

let requestSeq = 0;

/** Versioned message protocol: every request carries a request id; Lua always resolves the callback. */
export const PROTOCOL_VERSION = 1;

export interface NuiResponse<T = unknown> {
  ok: boolean;
  code?: string;
  message?: string;
  data?: T;
}

/** POST to a registered NUI callback. The browser only names an action id; Lua decides what it means. */
export async function nui<T = unknown>(action: string, payload: Record<string, unknown> = {}): Promise<NuiResponse<T>> {
  if (isBrowserDev()) return { ok: false, code: 'DEV', message: 'not running in FiveM' };
  requestSeq += 1;
  try {
    const res = await fetch(`https://${resourceName()}/${action}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify({ v: PROTOCOL_VERSION, requestId: `${Date.now().toString(36)}-${requestSeq}`, ...payload }),
    });
    const text = await res.text();
    return text ? (JSON.parse(text) as NuiResponse<T>) : { ok: true };
  } catch (err) {
    return { ok: false, code: 'NUI_ERROR', message: String(err) };
  }
}

export interface NuiMessage<T = unknown> {
  action: string;
  data?: T;
}

/** Subscribe to `SendNUIMessage({ action, data })` messages from Lua. */
export function useNuiMessage<T = unknown>(action: string, handler: (data: T) => void): void {
  const ref = useRef(handler);
  ref.current = handler;
  useEffect(() => {
    const listener = (event: MessageEvent<NuiMessage<T>>) => {
      if (event.data && event.data.action === action) ref.current(event.data.data as T);
    };
    window.addEventListener('message', listener);
    return () => window.removeEventListener('message', listener);
  }, [action]);
}

/** Tell Lua the page booted, so a failed asset load can be detected with a bounded timeout. */
export function announceReady(): void {
  void nui('ui:ready', {});
}
