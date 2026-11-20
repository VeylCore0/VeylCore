import type { ItemDef, SlotItem } from '@veyl/ui';

export function Details({ item, def, imagePath }: { item?: SlotItem; def?: ItemDef; imagePath: string }) {
  return (
    <aside className="inv-details v-panel">
      {!item || !def ? (
        <div className="v-muted empty-details">Hover or select an item to see its details.</div>
      ) : (
        <>
          <img className="details-img" src={`${imagePath}/${def.image ?? item.name + '.svg'}`} alt="" />
          <div className="details-name">{def.label}</div>
          {def.description && <p className="v-muted details-desc">{def.description}</p>}
          <dl className="details-meta">
            <dt>Quantity</dt><dd>{item.count}{def.stack ? ` / ${def.maxStack}` : ''}</dd>
            <dt>Weight</dt><dd>{((def.weight * item.count) / 1000).toFixed(2)} kg</dd>
            {def.usable && (<><dt>Action</dt><dd>Usable (Enter / double-click)</dd></>)}
            {item.metadata && Object.entries(item.metadata).map(([k, v]) => (
              <span key={k} style={{ display: 'contents' }}>
                <dt>{k}</dt><dd>{typeof v === 'object' ? JSON.stringify(v) : String(v)}</dd>
              </span>
            ))}
          </dl>
        </>
      )}
    </aside>
  );
}
