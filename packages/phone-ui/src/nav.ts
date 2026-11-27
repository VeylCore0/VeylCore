// Back handling: Escape (and the home bar) first closes the innermost thing that is open (a sheet, a thread, a
// dialog); only when nothing is left does Escape go home, then close the phone.
import { useEffect, useRef } from 'react';
import { setState } from './store';

type Handler = () => boolean | void;
const stack: Handler[] = [];

/** Registers a back handler while `active`. Return false to let the next handler (or the shell) have it. */
export function useBack(active: boolean, fn: Handler) {
  const ref = useRef(fn);
  ref.current = fn;
  useEffect(() => {
    if (!active) return;
    const h: Handler = () => ref.current();
    stack.push(h);
    return () => { const i = stack.lastIndexOf(h); if (i >= 0) stack.splice(i, 1); };
  }, [active]);
}

/** Deep links: an app receives `route` once (from a notification tap or another app); this runs `fn` and clears it. */
export function useRouteOnce(route: string | undefined, fn: (route: string) => void) {
  const ref = useRef(fn);
  ref.current = fn;
  useEffect(() => {
    if (!route) return;
    ref.current(route);
    setState({ route: undefined });
  }, [route]);
}

/** Runs the innermost handler. Returns true when something consumed it. */
export function goBack(): boolean {
  for (let i = stack.length - 1; i >= 0; i--) {
    if (stack[i]() !== false) return true;
  }
  return false;
}
