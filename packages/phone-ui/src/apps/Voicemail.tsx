// Voicemail: messages people left when you could not answer (typed or recorded), and leaving your own.
import { useEffect, useRef, useState } from 'react';
import { api } from '../api';
import { openApp, startCall } from '../controller';
import { formatDigits, listTime } from '../format';
import { Ico } from '../icons';
import { Avatar, Button, Empty, Header, IconButton, Segmented, Sheet, TextInput, cx, say } from '../ui';
import { Loaded, useLoad } from './kit';

type VM = { id: number; from_number: string; from_name: string | null; body: string; is_read: number; recorded?: number | boolean; seconds?: number | null; at: number };

const MAX_SECONDS = 30;
const clock = (s: number) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;
const isRec = (v: VM) => v.recorded === 1 || v.recorded === true;

// ---------------------------------------------------------------------------
// Recording (the phone's microphone, through the page)
// ---------------------------------------------------------------------------
type RecState = 'idle' | 'recording' | 'ready' | 'unsupported' | 'denied';

function useRecorder() {
  const [state, setState] = useState<RecState>(() => (typeof MediaRecorder === 'undefined' || !navigator.mediaDevices?.getUserMedia ? 'unsupported' : 'idle'));
  const [seconds, setSeconds] = useState(0);
  const [level, setLevel] = useState(0);
  const [audio, setAudio] = useState<string | null>(null);
  const rec = useRef<MediaRecorder | null>(null);
  const stream = useRef<MediaStream | null>(null);
  const chunks = useRef<Blob[]>([]);
  const timer = useRef<number>();
  const raf = useRef<number>();
  const started = useRef(0);
  const ctx = useRef<AudioContext | null>(null);

  const cleanup = () => {
    window.clearInterval(timer.current);
    if (raf.current) cancelAnimationFrame(raf.current);
    stream.current?.getTracks().forEach((t) => t.stop());
    stream.current = null;
    void ctx.current?.close().catch(() => undefined);
    ctx.current = null;
    setLevel(0);
  };
  useEffect(() => cleanup, []);

  const stop = () => { if (rec.current && rec.current.state !== 'inactive') rec.current.stop(); };

  const start = async () => {
    if (state === 'unsupported') return;
    setAudio(null); setSeconds(0);
    let s: MediaStream;
    try { s = await navigator.mediaDevices.getUserMedia({ audio: true }); } catch { setState('denied'); return; }
    stream.current = s;
    const type = ['audio/webm;codecs=opus', 'audio/ogg;codecs=opus', 'audio/webm', 'audio/mp4'].find((t) => MediaRecorder.isTypeSupported?.(t));
    const r = new MediaRecorder(s, { ...(type ? { mimeType: type } : {}), audioBitsPerSecond: 24000 });
    chunks.current = [];
    r.ondataavailable = (e) => { if (e.data.size > 0) chunks.current.push(e.data); };
    r.onstop = () => {
      const secs = Math.max(1, Math.round((Date.now() - started.current) / 1000));
      cleanup();
      const blob = new Blob(chunks.current, { type: r.mimeType || type || 'audio/webm' });
      const reader = new FileReader();
      reader.onload = () => { setSeconds(Math.min(secs, MAX_SECONDS)); setAudio(String(reader.result)); setState('ready'); };
      reader.readAsDataURL(blob);
    };
    rec.current = r;
    started.current = Date.now();
    r.start(250);
    setState('recording');
    timer.current = window.setInterval(() => {
      const sec = (Date.now() - started.current) / 1000;
      setSeconds(sec);
      if (sec >= MAX_SECONDS) stop();
    }, 200);
    // A little level meter so people can see the microphone is hearing them.
    try {
      const ac = new AudioContext();
      ctx.current = ac;
      const an = ac.createAnalyser();
      an.fftSize = 256;
      ac.createMediaStreamSource(s).connect(an);
      const buf = new Uint8Array(an.frequencyBinCount);
      const tick = () => { an.getByteTimeDomainData(buf); let peak = 0; for (const b of buf) peak = Math.max(peak, Math.abs(b - 128)); setLevel(Math.min(1, peak / 90)); raf.current = requestAnimationFrame(tick); };
      tick();
    } catch { /* no meter */ }
  };
  const reset = () => { setAudio(null); setSeconds(0); setState('idle'); };
  return { state, seconds, level, audio, start, stop, reset };
}

// ---------------------------------------------------------------------------
// Playing a recording
// ---------------------------------------------------------------------------
function Player({ src, seconds }: { src: string | null; seconds?: number | null }) {
  const el = useRef<HTMLAudioElement | null>(null);
  const [playing, setPlaying] = useState(false);
  const [pos, setPos] = useState(0);
  const [len, setLen] = useState(seconds ?? 0);
  useEffect(() => {
    if (!src) return;
    const a = new Audio(src);
    el.current = a;
    a.onended = () => { setPlaying(false); setPos(0); };
    a.ontimeupdate = () => setPos(a.currentTime);
    a.onloadedmetadata = () => { if (Number.isFinite(a.duration) && a.duration > 0) setLen(a.duration); };
    return () => { a.pause(); el.current = null; };
  }, [src]);
  const toggle = () => {
    const a = el.current;
    if (!a) return;
    if (playing) { a.pause(); setPlaying(false); } else { void a.play().then(() => setPlaying(true)).catch(() => say({ ok: false, message: 'Could not play the recording' } as never)); }
  };
  const total = len || seconds || 0;
  return (
    <div className="ph-player">
      <button onClick={toggle} disabled={!src} aria-label={playing ? 'Pause' : 'Play'}><Ico name={playing ? 'pause' : 'play'} size={20} /></button>
      <span className="ph-player-track"><i style={{ width: `${total ? Math.min(100, (pos / total) * 100) : 0}%` }} /></span>
      <time>{clock(playing || pos > 0 ? pos : total)}</time>
    </div>
  );
}

function Recording({ vm }: { vm: VM }) {
  const [audio, setAudio] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => { void api<{ audio: string }>('voicemailAudio', vm.id).then((r) => { if (r.ok && r.data) setAudio(r.data.audio); else setFailed(true); }); }, [vm.id]);
  return failed ? <p className="ph-hint">The recording could not be loaded.</p> : <Player src={audio} seconds={vm.seconds} />;
}

// ---------------------------------------------------------------------------
export function VoicemailApp() {
  const load = useLoad(() => api<VM[]>('voicemailList'));
  const [open, setOpen] = useState<VM | null>(null);
  const [leave, setLeave] = useState(false);
  const unread = load.data?.filter((v) => !v.is_read).length ?? 0;
  const nameOf = (v: VM) => v.from_name || formatDigits(v.from_number);

  const view = async (v: VM) => {
    setOpen(v);
    if (!v.is_read) { await api('voicemailRead', v.id); load.setData((l) => l?.map((x) => (x.id === v.id ? { ...x, is_read: 1 } : x)) ?? null); }
  };
  const remove = async (v: VM) => { if (say(await api('voicemailDelete', v.id))) { setOpen(null); load.setData((l) => l?.filter((x) => x.id !== v.id) ?? null); } };

  return (
    <div className="ph-app">
      <Header title="Voicemail" right={<><IconButton icon="mic" label="Leave a voicemail" tone="accent" onClick={() => setLeave(true)} /></>} />
      <div className="ph-scroll">
        <Loaded {...load}>
          {(list) => list.length === 0
            ? <Empty icon="mic" title="No voicemail" text="When you miss a call, people can leave you a message here." />
            : (
              <>
                {unread > 0 && <p className="ph-vmcount">{unread} new</p>}
                <ul className="ph-list">
                  {list.map((v) => (
                    <li key={v.id}>
                      <button className={cx('ph-vm', !v.is_read && 'unread')} onClick={() => void view(v)}>
                        <i className="ph-udot on" style={{ visibility: v.is_read ? 'hidden' : 'visible' }} />
                        <Avatar name={v.from_name ?? ''} id={v.from_number} size={42} />
                        <span className="ph-vm-main"><span className="ph-conv-top"><strong>{nameOf(v)}</strong><time>{listTime(v.at)}</time></span>
                          <span className="ph-vm-body">{isRec(v) ? <span className="ph-vm-rec"><Ico name="mic" size={13} /> Recording · {clock(v.seconds ?? 0)}</span> : v.body}</span></span>
                      </button>
                    </li>
                  ))}
                </ul>
              </>
            )}
        </Loaded>
      </div>
      {open && (
        <Sheet title="Voicemail" onClose={() => setOpen(null)}>
          <div className="ph-info-head"><Avatar name={open.from_name ?? ''} id={open.from_number} size={64} /><strong>{nameOf(open)}</strong><span className="ph-sub">{formatDigits(open.from_number)} · {listTime(open.at)}</span></div>
          {isRec(open) ? <Recording vm={open} /> : <div className="ph-vm-full"><Ico name="mic" size={16} /><p>{open.body}</p></div>}
          <div className="ph-info-actions">
            <button onClick={() => { setOpen(null); void startCall(open.from_number); }}><Ico name="phone" size={20} /><span>Call back</span></button>
            <button onClick={() => { setOpen(null); openApp('messages', `to/${open.from_number}`); }}><Ico name="chat" size={20} /><span>Message</span></button>
            <button onClick={() => void remove(open)}><Ico name="trash" size={20} style={{ color: 'var(--ph-red)' }} /><span>Delete</span></button>
          </div>
        </Sheet>
      )}
      {leave && <LeaveSheet onClose={() => { setLeave(false); }} />}
    </div>
  );
}

function LeaveSheet({ onClose }: { onClose: () => void }) {
  const rec = useRecorder();
  const [mode, setMode] = useState<'record' | 'type'>('record');
  const [number, setNumber] = useState('');
  const [body, setBody] = useState('');
  const [busy, setBusy] = useState(false);
  const digits = number.replace(/\D/g, '');
  const numberOk = digits.length === 7;
  const useType = mode === 'type' || rec.state === 'unsupported' || rec.state === 'denied';
  const ok = numberOk && !busy && (useType ? body.trim().length >= 2 : rec.state === 'ready' && !!rec.audio);

  const send = async () => {
    setBusy(true);
    const r = useType ? await api('voicemailLeave', digits, body) : await api('voicemailLeave', digits, '', rec.audio, Math.round(rec.seconds));
    setBusy(false);
    if (say(r)) onClose();
  };

  return (
    <Sheet title="Leave a voicemail" onClose={onClose}>
      <div className="ph-form">
        <label>To<TextInput value={formatDigits(number)} onChange={setNumber} placeholder="555-1234" inputMode="tel" autoFocus /></label>
        {(rec.state !== 'unsupported' && rec.state !== 'denied') && <Segmented options={[{ id: 'record', label: 'Record' }, { id: 'type', label: 'Type' }]} value={mode} onChange={setMode} />}
        {useType ? (
          <>
            {(rec.state === 'unsupported' || rec.state === 'denied') && (
              <p className="ph-hint">{rec.state === 'denied' ? 'The microphone is blocked, so type your message instead.' : 'Recording is not available here, so type your message instead.'}</p>
            )}
            <label>Message<TextInput multiline value={body} onChange={setBody} placeholder="Say what you would say after the beep" maxLength={500} /></label>
          </>
        ) : (
          <div className="ph-rec">
            <div className="ph-rec-bars" aria-hidden="true">{[0.5, 0.8, 1, 0.7, 0.9, 0.6, 1, 0.8, 0.5].map((k, i) => <i key={i} style={{ height: rec.state === 'recording' ? 4 + Math.round(rec.level * 24 * k) : 4 }} />)}</div>
            <span className="ph-rec-time">{clock(rec.seconds)}<small> / {clock(MAX_SECONDS)}</small></span>
            {rec.state === 'ready' && <Player src={rec.audio} seconds={rec.seconds} />}
            {rec.state === 'ready'
              ? <Button kind="ghost" onClick={rec.reset}>Record again</Button>
              : <button className={cx('ph-rec-btn', rec.state === 'recording' && 'on')} onClick={() => (rec.state === 'recording' ? rec.stop() : void rec.start())} aria-label={rec.state === 'recording' ? 'Stop recording' : 'Start recording'}><Ico name={rec.state === 'recording' ? 'stop' : 'mic'} size={30} /></button>}
            <p className="ph-rec-hint">{rec.state === 'recording' ? 'Recording… tap to stop' : rec.state === 'ready' ? 'Listen to it, then send' : `Tap the button and speak (up to ${MAX_SECONDS} seconds)`}</p>
          </div>
        )}
        <Button kind="primary" block onClick={send} disabled={!ok}>{busy ? 'Sending…' : 'Send voicemail'}</Button>
      </div>
    </Sheet>
  );
}
