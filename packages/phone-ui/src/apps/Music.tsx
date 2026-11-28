// Music: live-generated stations (no audio files), volume, and "play out loud" so people nearby hear it too.
import { useEffect, useState, useSyncExternalStore } from 'react';
import { api } from '../api';
import { Ico } from '../icons';
import { getStations, loadStations, music, type Station } from '../music';
import { Header, Slider, Toggle, cx, say } from '../ui';

const LOOK: Record<string, string> = { synth: 'linear-gradient(135deg,#8b5fd6,#e05fb0)', lofi: 'linear-gradient(135deg,#3aa6c9,#7bd3a5)', night: 'linear-gradient(135deg,#2c3a8c,#9a4fd6)' };
const art = (s: Station) => LOOK[s.style ?? 'synth'] ?? 'linear-gradient(135deg,#59607a,#8b63d6)';

function useMusic() {
  return useSyncExternalStore(music.subscribe, () => `${music.station?.id ?? ''}|${music.volume}`);
}

export function MusicApp() {
  const [stations, setStations] = useState<Station[]>(getStations());
  const [loud, setLoud] = useState(false);
  useMusic();
  const now = music.station;

  useEffect(() => { void loadStations().then(setStations); }, []);
  // Leaving the app keeps the music going; stopping the speaker when the phone is put away is the server's job.

  const play = async (st: Station) => {
    music.play(st);
    if (loud) say(await api('speakerPlay', st.id));
  };
  const stop = async () => { music.stop(); if (loud) await api('speakerStop'); };
  const toggleLoud = async (v: boolean) => {
    setLoud(v);
    if (v && now) say(await api('speakerPlay', now.id)); else await api('speakerStop');
  };

  return (
    <div className="ph-app">
      <Header title="Music" />
      <div className="ph-scroll ph-pad">
        <div className="ph-nowplaying" style={{ background: now ? art(now) : undefined }}>
          <div className={cx('ph-eq', !now && 'idle')} aria-hidden="true"><i /><i /><i /><i /><i /></div>
          <div className="ph-np-text"><small>{now ? 'Now playing' : 'Nothing playing'}</small><strong>{now?.label ?? 'Pick a station'}</strong></div>
          {now && <button className="ph-np-stop" onClick={() => void stop()} aria-label="Stop"><Ico name="pause" size={20} /></button>}
        </div>
        <div className="ph-volrow"><Ico name="volume" size={16} /><Slider value={Math.round(music.volume * 100)} onChange={(v) => music.setVolume(v / 100)} label="Music volume" /></div>
        <div className="ph-loudrow"><span><strong>Play out loud</strong><small>People nearby hear it, louder the closer they are</small></span><Toggle on={loud} onChange={(v) => void toggleLoud(v)} label="Play out loud" /></div>
        <section className="ph-mine"><h4>Stations</h4>
          {stations.map((s) => (
            <button key={s.id} className={cx('ph-station', now?.id === s.id && 'on')} onClick={() => void (now?.id === s.id ? stop() : play(s))}>
              <span className="ph-station-art" style={{ background: art(s) }}><Ico name={now?.id === s.id ? 'pause' : 'play'} size={16} /></span>
              <span className="ph-station-main"><strong>{s.label}</strong><em>{s.url ? 'Internet radio' : 'Live generated'}</em></span>
              {now?.id === s.id && <span className="ph-eq mini" aria-hidden="true"><i /><i /><i /></span>}
            </button>
          ))}
        </section>
      </div>
    </div>
  );
}
