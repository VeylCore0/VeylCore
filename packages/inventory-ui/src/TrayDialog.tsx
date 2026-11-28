import { CloseHint, Icon, type ItemDef, type SlotItem } from '@veyl/ui';

export interface TrayState {
  title: string; hint?: string; accepts: string; insertLabel?: string; removeLabel?: string; emptyLabel?: string;
  current?: { label: string; detail?: string; image?: string } | null;
}

/** A small box opened from an item's right-click menu (for example the phone's SIM card tray). */
export function TrayDialog(props: {
  state: TrayState | null; error?: string; busy: boolean; candidates: SlotItem[]; defs: Record<string, ItemDef>; imagePath: string;
  onClose: () => void; onInsert: (slot: number) => void; onRemove: () => void;
}) {
  const { state, candidates, defs, imagePath } = props;
  const accepted = state ? defs[state.accepts] : undefined;
  const img = (name: string, image?: string) => `${imagePath}/${image ?? defs[name]?.image ?? name + '.png'}`;
  return (
    <div className="v-dialog-backdrop" onMouseDown={props.onClose}>
      <div className="v-panel dialog tray" onMouseDown={(e) => e.stopPropagation()} role="dialog" aria-label={state?.title ?? 'Tray'}>
        <div className="dialog-head"><span className="dialog-title">{state?.title ?? '...'}</span><CloseHint onClose={props.onClose} /></div>
        {props.error && <div className="tray-error" role="alert"><Icon name="alert" size="1rem" />{props.error}</div>}
        {state && (
          <>
            <div className={`tray-slot${state.current ? ' filled' : ''}`}>
              {state.current ? (
                <>
                  <img src={img(state.accepts, state.current.image)} alt="" />
                  <span className="tray-slot-text"><strong>{state.current.label}</strong>{state.current.detail && <em>{state.current.detail}</em>}</span>
                  <button className="v-btn danger" disabled={props.busy} onClick={props.onRemove}>{state.removeLabel ?? 'Remove'}</button>
                </>
              ) : (
                <span className="tray-empty"><Icon name="plus" size="1.1rem" />{state.emptyLabel ?? 'Empty'}</span>
              )}
            </div>
            {state.hint && <p className="tray-hint v-muted">{state.hint}</p>}
            {!state.current && (
              <div className="tray-list">
                <div className="tray-list-title v-muted">{accepted?.label ?? state.accepts} in your inventory</div>
                {candidates.length === 0 && <div className="tray-none v-muted">You do not have any.</div>}
                {candidates.map((c) => (
                  <div key={c.slot} className="tray-item">
                    <img src={img(c.name)} alt="" />
                    <span className="tray-slot-text"><strong>{accepted?.label ?? c.name}</strong><em>{typeof c.metadata?.number === 'string' ? String(c.metadata.number).replace(/^(\d{3})(\d{4})$/, '$1-$2') : 'New card'}</em></span>
                    <button className="v-btn primary" disabled={props.busy} onClick={() => props.onInsert(c.slot)}>{state.insertLabel ?? 'Insert'}</button>
                  </div>
                ))}
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
