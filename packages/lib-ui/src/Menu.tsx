import { useEffect, useRef, useState } from 'react';
import type { MenuOpen } from '@veyl/ui';
import { sendResult } from './App';

export function Menu({ data }: { data: MenuOpen }) {
  const firstEnabled = data.options.findIndex((o) => !o.disabled);
  const [index, setIndex] = useState(Math.max(0, firstEnabled));
  const [pending, setPending] = useState(false);
  const listRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setIndex(Math.max(0, data.options.findIndex((o) => !o.disabled)));
    setPending(false);
  }, [data]);

  const select = (i: number) => {
    const opt = data.options[i];
    if (!opt || opt.disabled || pending) return;
    setPending(true);
    void sendResult(data.token, { type: 'select', optionId: opt.id });
  };
  const close = () => { if (!pending) { setPending(true); void sendResult(data.token, { type: 'close' }); } };
  const back = () => { if (!pending) { setPending(true); void sendResult(data.token, { type: 'back' }); } };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        const dir = e.key === 'ArrowDown' ? 1 : -1;
        setIndex((cur) => {
          for (let step = 1; step <= data.options.length; step++) {
            const next = (cur + dir * step + data.options.length) % data.options.length;
            if (!data.options[next].disabled) return next;
          }
          return cur;
        });
      } else if (e.key === 'Enter') {
        select(index);
      } else if (e.key === 'Escape' || e.key === 'Backspace') {
        if (data.canGoBack) back(); else close();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  useEffect(() => {
    listRef.current?.querySelector<HTMLElement>(`[data-i="${index}"]`)?.scrollIntoView({ block: 'nearest' });
  }, [index]);

  return (
    <div className="v-panel menu" role="menu">
      <div className="menu-head">
        <div>
          {data.breadcrumb && data.breadcrumb.length > 0 && <div className="crumb">{data.breadcrumb.join(' › ')}</div>}
          <div className="menu-title">{data.title}</div>
          {data.subtitle && <div className="v-muted menu-sub">{data.subtitle}</div>}
        </div>
      </div>
      <div className="menu-list" ref={listRef}>
        {data.options.length === 0 && <div className="v-muted empty">Nothing here yet.</div>}
        {data.options.map((o, i) => (
          <button
            key={o.id}
            data-i={i}
            role="menuitem"
            className={`menu-row${i === index ? ' active' : ''}`}
            disabled={o.disabled}
            title={o.disabled ? o.disabledReason : undefined}
            onMouseEnter={() => !o.disabled && setIndex(i)}
            onClick={() => select(i)}
          >
            {o.icon && <span className="menu-icon">{o.icon}</span>}
            <span className="menu-text">
              <span className="menu-label">{o.label}</span>
              {(o.description || (o.disabled && o.disabledReason)) && (
                <span className="v-muted menu-desc">{o.disabled && o.disabledReason ? o.disabledReason : o.description}</span>
              )}
            </span>
            {o.right && <span className="menu-right">{o.right}</span>}
            {o.hasChildren && <span className="menu-right">›</span>}
          </button>
        ))}
      </div>
      <div className="menu-foot v-muted">
        <span><span className="v-key">↑↓</span> navigate</span>
        <span><span className="v-key">Enter</span> select</span>
        <span><span className="v-key">Esc</span> {data.canGoBack ? 'back' : 'close'}</span>
      </div>
    </div>
  );
}
