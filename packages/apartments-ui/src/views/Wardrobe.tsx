import { useState } from 'react';
import { Icon, StateView, nui, type NuiResponse } from '@veyl/ui';

interface Outfit { id: number; name: string }
type Say = (k: 'ok' | 'error', t: string) => void;

export function WardrobeView({ initial, toast }: { initial: { outfits: Outfit[]; max?: number }; toast: Say }) {
  const [outfits, setOutfits] = useState<Outfit[]>(initial.outfits ?? []);
  const [name, setName] = useState('');
  const [renaming, setRenaming] = useState<{ id: number; name: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const run = async (action: string, id?: number, n?: string) => {
    setBusy(true);
    const r = (await nui('wardrobeAction', { action, id, name: n })) as NuiResponse<{ outfits?: Outfit[] }>;
    setBusy(false);
    toast(r.ok ? 'ok' : 'error', r.message ?? (r.ok ? 'Done' : 'Failed'));
    if (r.ok && r.data?.outfits) setOutfits(r.data.outfits);
    return r.ok;
  };
  return (
    <div className="apt-wardrobe">
      <div className="apt-card">
        <div className="apt-card-title"><Icon name="hanger" size="1rem" /> Save what you are wearing</div>
        <div className="apt-target">
          <input className="v-input" maxLength={32} value={name} onChange={(e) => setName(e.target.value)} placeholder="Outfit name" aria-label="Outfit name" />
          <button className="v-btn primary" disabled={busy || !name.trim()} onClick={() => void run('save', undefined, name.trim()).then((ok) => ok && setName(''))}>Save</button>
        </div>
        <p className="v-muted small">Outfits are shared with clothing stores. New clothes are bought at a clothing store.</p>
      </div>
      <div className="apt-card">
        <div className="apt-card-title"><Icon name="shirt" size="1rem" /> Saved outfits {initial.max ? <span className="v-muted">({outfits.length}/{initial.max})</span> : null}</div>
        {outfits.length === 0 && <StateView kind="empty" message="No saved outfits yet." />}
        {outfits.map((o) => (
          <div key={o.id} className="apt-piece">
            {renaming?.id === o.id ? (
              <>
                <input className="v-input" autoFocus maxLength={32} value={renaming.name} onChange={(e) => setRenaming({ id: o.id, name: e.target.value })} aria-label="New name" />
                <button className="v-btn primary" disabled={busy || !renaming.name.trim()} onClick={() => void run('rename', o.id, renaming.name.trim()).then((ok) => ok && setRenaming(null))}>Save</button>
                <button className="v-btn" onClick={() => setRenaming(null)}>Cancel</button>
              </>
            ) : (
              <>
                <span>{o.name}</span>
                <button className="v-btn primary" disabled={busy} onClick={() => void run('wear', o.id)}>Wear</button>
                <button className="v-btn" disabled={busy} onClick={() => setRenaming({ id: o.id, name: o.name })}>Rename</button>
                <button className="v-icon-btn" disabled={busy} aria-label={`Delete ${o.name}`} onClick={() => void run('delete', o.id)}><Icon name="close" size="0.9rem" /></button>
              </>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
