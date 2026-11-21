// Veyl Radio: original synthwave tracks generated live with WebAudio (no audio files), or a playlist of
// the server's own files (config Music.Tracks). Exposes window.VeylRadio.
(function () {
  'use strict';

  const midi = (m) => 440 * Math.pow(2, (m - 69) / 12);

  // Each generated track: tempo, a chord per bar (pad voicing), bass roots, drums on/off, colour.
  const GENERATED = [
    { title: 'Midnight Drive', artist: 'Veyl Radio', bpm: 92, drums: true, cutoff: 1400,
      chords: [[57, 60, 64], [53, 57, 60], [55, 60, 64], [55, 59, 62]], bass: [45, 41, 48, 43] },
    { title: 'Vinewood Lights', artist: 'Veyl Radio', bpm: 104, drums: true, cutoff: 1800,
      chords: [[53, 56, 60], [53, 56, 61], [51, 56, 60], [51, 55, 58]], bass: [41, 37, 44, 39] },
    { title: 'Rain on Del Perro', artist: 'Veyl Radio', bpm: 80, drums: false, cutoff: 1100,
      chords: [[57, 62, 65], [58, 62, 65], [57, 60, 65], [55, 60, 64]], bass: [38, 46, 41, 36] },
  ];
  const ARP = [0, 1, 2, 1, 0, 2, 1, 2];

  function create(opts) {
    const files = (opts.tracks || []).filter((t) => t && t.file);
    const tracks = files.length ? files : GENERATED;
    let index = 0, volume = clamp(opts.volume ?? 0.35), muted = false, playing = false;
    let ctx = null, master = null, bus = null, reverb = null, delay = null, noise = null;
    let timer = null, step = 0, nextTime = 0;
    let audioEl = null;
    const listeners = [];
    const emit = () => listeners.forEach((fn) => fn(state()));
    const state = () => ({ track: tracks[index], index, playing, volume, muted, generated: !files.length });

    function clamp(v) { return Math.max(0, Math.min(1, Number(v) || 0)); }
    function gainValue() { return muted ? 0 : volume * 0.8; }

    // ---- generated engine ------------------------------------------------
    function setupContext() {
      if (ctx) return;
      ctx = new (window.AudioContext || window.webkitAudioContext)();
      master = ctx.createGain(); master.gain.value = gainValue();
      const comp = ctx.createDynamicsCompressor(); comp.threshold.value = -16; comp.ratio.value = 3;
      master.connect(comp).connect(ctx.destination);
      // Reverb from a generated impulse response.
      reverb = ctx.createConvolver();
      const len = ctx.sampleRate * 2.6, ir = ctx.createBuffer(2, len, ctx.sampleRate);
      for (let c = 0; c < 2; c++) { const d = ir.getChannelData(c); for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 2.4); }
      reverb.buffer = ir;
      const rv = ctx.createGain(); rv.gain.value = 0.32; reverb.connect(rv).connect(master);
      // Tempo delay for the arpeggio.
      delay = ctx.createDelay(1.5); const fb = ctx.createGain(); fb.gain.value = 0.32; const dg = ctx.createGain(); dg.gain.value = 0.28;
      delay.connect(fb).connect(delay); delay.connect(dg).connect(master);
      // White noise for hats/snare.
      noise = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
      const nd = noise.getChannelData(0); for (let i = 0; i < nd.length; i++) nd[i] = Math.random() * 2 - 1;
    }

    function newBus() {
      if (bus) { const old = bus; old.gain.setTargetAtTime(0, ctx.currentTime, 0.25); setTimeout(() => old.disconnect(), 1500); }
      bus = ctx.createGain(); bus.gain.value = 0; bus.gain.setTargetAtTime(1, ctx.currentTime, 0.4);
      bus.connect(master); bus.connect(reverb);
      const t = tracks[index]; delay.delayTime.value = (60 / t.bpm) * 0.75;
      step = 0; nextTime = ctx.currentTime + 0.1;
    }

    function env(g, t, a, peak, hold, r) {
      g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(peak, t + a);
      g.gain.setValueAtTime(peak, t + a + hold); g.gain.exponentialRampToValueAtTime(0.0001, t + a + hold + r);
    }
    function osc(type, freq, t, dur, out, peak, a, r, detune) {
      const o = ctx.createOscillator(), g = ctx.createGain();
      o.type = type; o.frequency.value = freq; if (detune) o.detune.value = detune;
      env(g, t, a, peak, Math.max(0, dur - a), r); o.connect(g).connect(out);
      o.start(t); o.stop(t + dur + r + 0.05);
    }
    function filter(type, f, q) { const n = ctx.createBiquadFilter(); n.type = type; n.frequency.value = f; if (q) n.Q.value = q; n.connect(bus); return n; }

    function scheduleStep(t, s) {
      const tr = tracks[index], spb = 60 / tr.bpm, sixteenth = spb / 4, bar = Math.floor(s / 16) % tr.chords.length, pos = s % 16;
      const chord = tr.chords[bar];
      if (pos === 0) { // pad: detuned saws through a soft low-pass
        const lp = filter('lowpass', tr.cutoff, 0.7);
        chord.forEach((n) => { osc('sawtooth', midi(n), t, sixteenth * 16, lp, 0.035, 0.7, 1.2, -7); osc('sawtooth', midi(n), t, sixteenth * 16, lp, 0.035, 0.7, 1.2, 7); });
        osc('sine', midi(chord[0] - 12), t, sixteenth * 16, lp, 0.05, 0.8, 1.2);
      }
      if (pos % 2 === 0) { // bass eighths
        const lp = filter('lowpass', 420, 4);
        osc('sawtooth', midi(tr.bass[bar] - 12), t, sixteenth * 1.6, lp, tr.drums ? 0.16 : 0.1, 0.01, 0.12);
      }
      { // arpeggio sixteenths (every other step on the slow track)
        if (tr.drums || pos % 2 === 0) {
          const n = chord[ARP[pos % ARP.length]] + 12;
          const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 2600; lp.connect(bus); lp.connect(delay);
          osc('triangle', midi(n), t, sixteenth * 0.6, lp, 0.05, 0.005, 0.18);
        }
      }
      if (!tr.drums) return;
      if (pos % 4 === 0) { // kick
        const o = ctx.createOscillator(), g = ctx.createGain();
        o.frequency.setValueAtTime(130, t); o.frequency.exponentialRampToValueAtTime(42, t + 0.18);
        env(g, t, 0.002, 0.55, 0.02, 0.3); o.connect(g).connect(bus); o.start(t); o.stop(t + 0.4);
      }
      if (pos === 4 || pos === 12) hit(t, 'bandpass', 1800, 0.22, 0.18);   // snare
      if (pos % 2 === 1) hit(t, 'highpass', 7500, 0.05, 0.04);              // hats
    }
    function hit(t, type, f, peak, r) {
      const src = ctx.createBufferSource(); src.buffer = noise;
      const fl = ctx.createBiquadFilter(); fl.type = type; fl.frequency.value = f;
      const g = ctx.createGain(); env(g, t, 0.001, peak, 0.01, r);
      src.connect(fl).connect(g).connect(bus); src.start(t); src.stop(t + r + 0.05);
    }
    function tick() {
      const tr = tracks[index], sixteenth = 60 / tr.bpm / 4;
      while (nextTime < ctx.currentTime + 0.15) { scheduleStep(nextTime, step); nextTime += sixteenth; step++; }
    }

    // ---- file playlist -----------------------------------------------------
    function loadFile() {
      if (!audioEl) {
        audioEl = new Audio();
        audioEl.addEventListener('ended', () => api.next());
        audioEl.addEventListener('error', () => { if (tracks.length > 1) api.next(); });
      }
      audioEl.src = tracks[index].file;
      audioEl.volume = gainValue();
    }

    const api = {
      onChange(fn) { listeners.push(fn); fn(state()); },
      state,
      /** Starts playback. Resolves to true if audio is really running (browsers may need a click first). */
      async play() {
        if (files.length) {
          if (!audioEl || !audioEl.src) loadFile();
          try { await audioEl.play(); playing = true; } catch { playing = false; }
          emit(); return playing;
        }
        setupContext();
        if (!bus) newBus();
        try { await ctx.resume(); } catch { /* needs a user gesture */ }
        playing = ctx.state === 'running';
        if (playing && !timer) timer = setInterval(tick, 25);
        emit(); return playing;
      },
      pause() {
        playing = false;
        if (files.length) { audioEl && audioEl.pause(); }
        else if (ctx) { ctx.suspend(); }
        emit();
      },
      toggle() { return playing ? (api.pause(), false) : api.play(); },
      next() { api.go(index + 1); },
      prev() { api.go(index - 1); },
      go(i) {
        index = (i + tracks.length) % tracks.length;
        if (files.length) { loadFile(); if (playing) audioEl.play().catch(() => {}); }
        else if (ctx) newBus();
        emit();
      },
      setVolume(v) {
        volume = clamp(v); muted = false;
        if (master) master.gain.setTargetAtTime(gainValue(), ctx.currentTime, 0.05);
        if (audioEl) audioEl.volume = gainValue();
        emit();
      },
      toggleMute() {
        muted = !muted;
        if (master) master.gain.setTargetAtTime(gainValue(), ctx.currentTime, 0.05);
        if (audioEl) audioEl.volume = gainValue();
        emit();
      },
    };
    return api;
  }

  window.VeylRadio = { create };
})();
