import { CloseHint, Icon, StateView, t, type NearbyPlayer } from '@veyl/ui';

/** Nearby-player selector. The server re-validates distance and the recipient when the give is submitted. */
export function GiveDialog({ players, error, onCancel, onPick }: { players: NearbyPlayer[] | null; error?: string; onCancel: () => void; onPick: (id: number) => void }) {
  return (
    <div className="v-dialog-backdrop" onMouseDown={onCancel}>
      <div className="v-panel dialog" onMouseDown={(e) => e.stopPropagation()} role="dialog" aria-label={t('inv.giveTitle')}>
        <div className="dialog-head"><span className="dialog-title">{t('inv.giveTitle')}</span><CloseHint onClose={onCancel} /></div>
        {players === null ? <StateView kind="loading" />
          : error ? <StateView kind="error" message={error} />
          : players.length === 0 ? <StateView kind="empty" message={t('inv.noNearby')} />
          : (
            <div className="player-list">
              {players.map((p) => (
                <button key={p.id} className="player-row" onClick={() => onPick(p.id)}>
                  <Icon name="user" size="1rem" />
                  <span className="player-name">{p.name}</span>
                  <span className="v-muted">#{p.id} · {p.distance.toFixed(1)} m</span>
                </button>
              ))}
            </div>
          )}
      </div>
    </div>
  );
}
