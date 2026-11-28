// Shared picture helpers: the gallery picker, photo messages and the small square pictures used for contacts.
import { useCallback, useEffect, useState } from 'react';
import { api } from '../api';
import { listTime } from '../format';
import { Ico } from '../icons';
import { Empty, Sheet, Spinner, cx, say } from '../ui';
import type { Contact } from '../types';

// ---------------------------------------------------------------------------
// Gallery photos (the player's own, by id)
// ---------------------------------------------------------------------------
const gallery = new Map<number, string>();

export function useGalleryImage(id: number) {
  const [src, setSrc] = useState<string | null>(gallery.get(id) ?? null);
  useEffect(() => {
    if (id < 0 || gallery.has(id)) { setSrc(gallery.get(id) ?? null); return; }
    let live = true;
    void api<{ image: string }>('photoGet', id).then((r) => { if (r.ok && r.data && live) { gallery.set(id, r.data.image); setSrc(r.data.image); } });
    return () => { live = false; };
  }, [id]);
  return src;
}

/** Fetches one gallery photo (cached). */
export async function galleryImage(id: number): Promise<string | null> {
  const hit = gallery.get(id);
  if (hit) return hit;
  const r = await api<{ image: string }>('photoGet', id);
  if (r.ok && r.data) { gallery.set(id, r.data.image); return r.data.image; }
  return null;
}

function PickThumb({ id, at, onPick }: { id: number; at: number; onPick: () => void }) {
  const src = useGalleryImage(id);
  return <button className="ph-thumb" onClick={onPick} aria-label={`Photo from ${listTime(at)}`}>{src ? <img src={src} alt="" /> : <span className="ph-thumb-load" />}</button>;
}

/** A sheet with the player's gallery; tapping a photo picks it. */
export function GalleryPicker({ title = 'Choose a photo', onPick, onClose }: { title?: string; onPick: (id: number) => void; onClose: () => void }) {
  const [list, setList] = useState<{ id: number; at: number }[] | null>(null);
  useEffect(() => { void api<{ id: number; at: number }[]>('photoList').then((r) => setList(r.ok ? r.data ?? [] : [])); }, []);
  return (
    <Sheet title={title} onClose={onClose}>
      {list === null && <Spinner />}
      {list?.length === 0 && <Empty icon="image" title="No photos yet" text="Take a photo with the Camera app first." />}
      {!!list?.length && <div className="ph-photogrid ph-picker">{list.map((p) => <PickThumb key={p.id} id={p.id} at={p.at} onPick={() => onPick(p.id)} />)}</div>}
    </Sheet>
  );
}

// ---------------------------------------------------------------------------
// Photos that arrived in a message (by message id; fetched when shown, kept for the session)
// ---------------------------------------------------------------------------
const received = new Map<number, string>();

export function useMessagePhoto(messageId: number, enabled = true) {
  const [src, setSrc] = useState<string | null>(received.get(messageId) ?? null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    if (!enabled || messageId <= 0) return;
    if (received.has(messageId)) { setSrc(received.get(messageId) ?? null); return; }
    let live = true;
    void api<{ image: string }>('messagePhoto', messageId).then((r) => {
      if (!live) return;
      if (r.ok && r.data) { received.set(messageId, r.data.image); setSrc(r.data.image); } else setFailed(true);
    });
    return () => { live = false; };
  }, [messageId, enabled]);
  return { src, failed };
}

/** A photo shown full size, with Save to Gallery for photos people sent you. */
export function PhotoSheet({ src, messageId, mine, onClose }: { src: string; messageId?: number; mine?: boolean; onClose: () => void }) {
  const [saved, setSaved] = useState(false);
  const save = async () => { if (messageId && say(await api('messagePhotoSave', messageId))) setSaved(true); };
  return (
    <Sheet title="Photo" onClose={onClose}>
      <div className="ph-photo-full"><img src={src} alt="" /></div>
      {messageId && !mine && (
        <div className="ph-info-actions">
          <button onClick={() => void save()} disabled={saved}><Ico name={saved ? 'check' : 'image'} size={20} /><span>{saved ? 'Saved' : 'Save to Gallery'}</span></button>
        </div>
      )}
    </Sheet>
  );
}

// ---------------------------------------------------------------------------
// Contact pictures
// ---------------------------------------------------------------------------
/** Crops a picture to a centred square and shrinks it to a small JPEG (a contact picture). */
export function squareThumb(dataUrl: string, size = 112, quality = 0.72): Promise<string | null> {
  return new Promise((resolve) => {
    const img = new Image();
    img.onload = () => {
      try {
        const side = Math.min(img.width, img.height);
        const c = document.createElement('canvas');
        c.width = size; c.height = size;
        const ctx = c.getContext('2d');
        if (!ctx) return resolve(null);
        ctx.drawImage(img, (img.width - side) / 2, (img.height - side) / 2, side, side, 0, 0, size, size);
        resolve(c.toDataURL('image/jpeg', quality));
      } catch { resolve(null); }
    };
    img.onerror = () => resolve(null);
    img.src = dataUrl;
  });
}

let photoMap: Map<string, string> | null = null;
const listeners = new Set<() => void>();

/** Contact pictures by number, for the Messages lists. Refreshed after a contact is saved. */
export function useContactPhotos() {
  const [, bump] = useState(0);
  const refresh = useCallback(async () => {
    const r = await api<Contact[]>('contacts');
    if (r.ok) { photoMap = new Map((r.data ?? []).filter((c) => c.photo).map((c) => [c.number, c.photo as string])); listeners.forEach((f) => f()); }
  }, []);
  useEffect(() => {
    const f = () => bump((n) => n + 1);
    listeners.add(f);
    if (photoMap === null) void refresh();
    return () => { listeners.delete(f); };
  }, [refresh]);
  return { photoOf: (number?: string) => (number ? photoMap?.get(number) ?? null : null), refresh };
}

export function resetContactPhotos() { photoMap = null; listeners.forEach((f) => f()); }

export { cx };
