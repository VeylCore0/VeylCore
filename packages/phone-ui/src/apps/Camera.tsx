// Camera and gallery. The shutter asks the game client for a screenshot; photos are small JPEGs stored on the server.
import { useCallback, useEffect, useState } from 'react';
import { api, post } from '../api';
import { listTime } from '../format';
import { Ico } from '../icons';
import { Empty, Header, Segmented, Sheet, cx, say } from '../ui';
import { Loaded, useLoad } from './kit';

type Photo = { id: number; at: number };
const cache = new Map<number, string>();

function useImage(id: number) {
  const [src, setSrc] = useState<string | null>(cache.get(id) ?? null);
  useEffect(() => {
    if (id < 0 || cache.has(id)) { setSrc(cache.get(id) ?? null); return; }
    let live = true;
    void api<{ image: string }>('photoGet', id).then((r) => { if (r.ok && r.data && live) { cache.set(id, r.data.image); setSrc(r.data.image); } });
    return () => { live = false; };
  }, [id]);
  return src;
}

function Thumb({ photo, onOpen }: { photo: Photo; onOpen: () => void }) {
  const src = useImage(photo.id);
  return <button className="ph-thumb" onClick={onOpen} aria-label={`Photo from ${listTime(photo.at)}`}>{src ? <img src={src} alt="" /> : <span className="ph-thumb-load" />}</button>;
}

export function CameraApp() {
  const [tab, setTab] = useState<'camera' | 'gallery'>('camera');
  const load = useLoad(() => api<Photo[]>('photoList'));
  const [flash, setFlash] = useState(false);
  const [busy, setBusy] = useState(false);
  const [open, setOpen] = useState<Photo | null>(null);

  const shoot = useCallback(async () => {
    if (busy) return;
    setBusy(true); setFlash(true);
    const shot = await post<{ image: string }>('cameraShot');
    setTimeout(() => setFlash(false), 160);
    if (!shot.ok || !shot.data?.image) { setBusy(false); say(shot); return; }
    const saved = await api<{ id: number }>('photoSave', shot.data.image);
    setBusy(false);
    if (say(saved) && saved.data) { cache.set(saved.data.id, shot.data.image); void load.reload(); }
  }, [busy, load]);

  const last = load.data?.[0];
  const lastSrc = useImage(last?.id ?? -1);
  const remove = async (p: Photo) => { if (say(await api('photoDelete', p.id))) { cache.delete(p.id); setOpen(null); void load.reload(); } };

  return (
    <div className="ph-app ph-cam">
      <Header title={tab === 'camera' ? 'Camera' : 'Gallery'} large={false} right={<Segmented options={[{ id: 'camera', label: 'Camera' }, { id: 'gallery', label: 'Gallery' }]} value={tab} onChange={setTab} />} />
      {tab === 'camera' ? (
        <div className="ph-cam-body">
          <div className="ph-viewfinder" aria-label="Viewfinder">
            <i className="g1" /><i className="g2" /><i className="g3" /><i className="g4" />
            <span className="c tl" /><span className="c tr" /><span className="c bl" /><span className="c br" />
            <span className="ph-cam-hint">Frame your shot, then press the shutter</span>
            {flash && <b className="ph-flash" />}
          </div>
          <div className="ph-shutter-row">
            <button className="ph-lastshot" onClick={() => setTab('gallery')} aria-label="Open gallery">{lastSrc ? <img src={lastSrc} alt="" /> : <Ico name="image" size={18} />}</button>
            <button className={cx('ph-shutter', busy && 'busy')} onClick={() => void shoot()} disabled={busy} aria-label="Take photo"><span /></button>
            <span className="ph-shutter-count">{load.data?.length ?? 0}<small>photos</small></span>
          </div>
        </div>
      ) : (
        <div className="ph-scroll ph-pad">
          <Loaded {...load}>
            {(list) => list.length === 0
              ? <Empty icon="image" title="No photos yet" text="Photos you take show up here." />
              : <div className="ph-photogrid">{list.map((p) => <Thumb key={p.id} photo={p} onOpen={() => setOpen(p)} />)}</div>}
          </Loaded>
        </div>
      )}
      {open && <Viewer photo={open} onClose={() => setOpen(null)} onDelete={() => void remove(open)} />}
    </div>
  );
}

function Viewer({ photo, onClose, onDelete }: { photo: Photo; onClose: () => void; onDelete: () => void }) {
  const src = useImage(photo.id);
  const [confirm, setConfirm] = useState(false);
  return (
    <Sheet title={listTime(photo.at)} onClose={onClose}>
      <div className="ph-photo-full">{src ? <img src={src} alt="" /> : <span className="ph-thumb-load" />}</div>
      <div className="ph-info-actions">
        <button onClick={() => (confirm ? onDelete() : setConfirm(true))}><Ico name="trash" size={20} style={{ color: 'var(--ph-red)' }} /><span>{confirm ? 'Tap again to delete' : 'Delete'}</span></button>
      </div>
    </Sheet>
  );
}
