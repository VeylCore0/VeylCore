// veyl_loadscreen: settings come from the server (window.nuiHandoverData.veyl); progress from FiveM's loading events.
(function () {
  'use strict';

  const $ = (id) => document.getElementById(id);
  const DEFAULTS = {
    headline: ['YOUR STORY.', 'STARTS HERE.'], subtitle: 'A new city. A new chapter.',
    updatesTitle: 'CITY UPDATES',
    updates: [{ icon: 'briefcase', text: 'New businesses are opening' }, { icon: 'users', text: 'Explore the city and meet your crew' }],
    tips: ['Get started at City Hall to find your first job.'], tipSeconds: 7,
    discord: '', rules: '', music: { enabled: true, volume: 0.35, tracks: [] },
  };
  const handover = (window.nuiHandoverData && window.nuiHandoverData.veyl) || null;
  const cfg = Object.assign({}, DEFAULTS, handover || {});

  const ICONS = {
    briefcase: 'M4 8h16v11H4zM9 8V6a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2M4 13h16',
    users: 'M9 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7zM2.5 20c.5-3.5 3.2-5.5 6.5-5.5s6 2 6.5 5.5M16 4.3a3.5 3.5 0 0 1 0 6.4M18 14.8c2 .7 3.3 2.5 3.6 5.2',
    car: 'M5 16h14M3 16v-3l2-5h14l2 5v3zM7 19a1.5 1.5 0 1 0 0-3M17 19a1.5 1.5 0 1 0 0-3M3 13h18',
    star: 'M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z',
    megaphone: 'M3 10v4h3l7 4V6L6 10zM16 9a4 4 0 0 1 0 6M19 6.5a8 8 0 0 1 0 11',
    home: 'M3 11l9-7 9 7M5 9.5V20h14V9.5M10 20v-6h4v6',
    shield: 'M12 3l8 3v6c0 4.5-3.4 8-8 9-4.6-1-8-4.5-8-9V6z',
    wrench: 'M14.5 6.5a4 4 0 0 0 5 5L21 13l-8 8-3-3 8-8-1.5-1.5a4 4 0 0 1-5-5L13 2l1.5 4.5zM5 19l-2 2',
  };
  const text = (v, max) => String(v == null ? '' : v).slice(0, max);

  // ---- content ---------------------------------------------------------------
  $('h1').textContent = text(cfg.headline && cfg.headline[0], 40);
  $('h2').textContent = text(cfg.headline && cfg.headline[1], 40);
  $('subtitle').textContent = text(cfg.subtitle, 80);
  $('updatesTitle').textContent = text(cfg.updatesTitle, 40);
  const list = $('updateList');
  (cfg.updates || []).slice(0, 4).forEach((u, i) => {
    const li = document.createElement('li');
    li.style.animationDelay = `${300 + i * 150}ms`;
    li.innerHTML = `<svg viewBox="0 0 24 24"><path d="${ICONS[u.icon] || ICONS.star}" /></svg><span></span>`;
    li.querySelector('span').textContent = text(u.text, 70);
    list.appendChild(li);
  });
  if (!list.children.length) $('updates').hidden = true;

  if (handover && typeof handover.players === 'number' && typeof handover.maxPlayers === 'number') {
    $('count').textContent = `${handover.players} / ${handover.maxPlayers}`;
    $('status').hidden = false;
  }

  // Tips rotate.
  const tips = (cfg.tips || []).filter(Boolean);
  let tipIndex = 0;
  if (tips.length) $('tip').textContent = text(tips[0], 140); else $('tip').parentElement.style.visibility = 'hidden';
  if (tips.length > 1) setInterval(() => {
    tipIndex = (tipIndex + 1) % tips.length;
    $('tip').style.opacity = '0';
    setTimeout(() => { $('tip').textContent = text(tips[tipIndex], 140); $('tip').style.opacity = '1'; }, 400);
  }, Math.max(3, Number(cfg.tipSeconds) || 7) * 1000);

  // Links open in the player's browser (FiveM: invokeNative openUrl).
  function link(id, url) {
    if (!url) return;
    const b = $(id); b.hidden = false;
    b.addEventListener('click', () => {
      if (window.invokeNative) window.invokeNative('openUrl', url); else window.open(url, '_blank', 'noopener');
    });
  }
  link('discord', cfg.discord);
  link('rules', cfg.rules);

  // ---- progress ------------------------------------------------------------------
  const PHASES = {
    INIT_CORE: 'Starting the game…',
    INIT_BEFORE_MAP_LOADED: 'Downloading city assets…',
    MAP: 'Loading the map…',
    INIT_AFTER_MAP_LOADED: 'Preparing the streets…',
    INIT_SESSION: 'Joining the city…',
  };
  let progress = 0, phase = '';
  function setProgress(f) {
    const p = Math.max(progress, Math.min(1, Number(f) || 0));
    if (p === progress) return;
    progress = p;
    const pct = Math.floor(p * 100);
    $('fill').style.width = `${pct}%`;
    $('pct').textContent = `${pct}%`;
    $('bar').setAttribute('aria-valuenow', String(pct));
  }
  function setSub(s) { if (s) $('loadSub').textContent = text(s, 120); }

  window.addEventListener('message', (e) => {
    const d = e.data || {};
    switch (d.eventName) {
      case 'loadProgress': setProgress(d.loadFraction); break;
      case 'startInitFunctionOrder': phase = d.type; setSub(PHASES[d.type]); break;
      case 'startDataFileEntries': phase = 'MAP'; setSub(PHASES.MAP); break;
      case 'performMapLoadFunction': setSub(PHASES.MAP); break;
      case 'onLogLine': if (d.message && phase !== 'INIT_SESSION') setSub(String(d.message).replace(/\.\.\.$/, '…')); break;
      default: break;
    }
  });
  if (handover) setSub('Connected. Loading the game…');

  // ---- music ----------------------------------------------------------------------
  const music = cfg.music || {};
  if (music.enabled !== false && window.VeylRadio) {
    const radio = window.VeylRadio.create({ volume: music.volume, tracks: music.tracks });
    const player = $('player');
    player.hidden = false;
    const vol = $('vol');
    const paintVol = (v) => vol.style.setProperty('--v', `${Math.round(v * 100)}%`);
    radio.onChange((s) => {
      $('trackTitle').textContent = text(s.track.title, 40);
      $('trackArtist').textContent = text(s.track.artist, 40);
      player.classList.toggle('playing', s.playing);
      player.classList.toggle('muted', s.muted);
      $('play').setAttribute('aria-label', s.playing ? 'Pause' : 'Play');
      $('playIcon').innerHTML = s.playing ? '<path d="M7 5h4v14H7zM13 5h4v14h-4z" />' : '<path d="M7 4v16l13-8z" />';
      vol.value = String(Math.round(s.volume * 100)); paintVol(s.muted ? 0 : s.volume);
    });
    $('play').addEventListener('click', () => { void radio.toggle(); $('tapHint').hidden = true; });
    $('next').addEventListener('click', () => radio.next());
    $('prev').addEventListener('click', () => radio.prev());
    $('mute').addEventListener('click', () => radio.toggleMute());
    vol.addEventListener('input', () => radio.setVolume(Number(vol.value) / 100));

    radio.play().then((ok) => {
      if (ok) return;
      // Audio blocked until the first click (normal browsers; FiveM usually allows autoplay).
      $('tapHint').hidden = false;
      const start = () => { void radio.play().then((on) => { if (on) $('tapHint').hidden = true; }); window.removeEventListener('pointerdown', start); };
      window.addEventListener('pointerdown', start);
    });
  }

  // ---- rain ------------------------------------------------------------------------
  const canvas = document.querySelector('.rain');
  const reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (canvas && !reduced) {
    const g = canvas.getContext('2d');
    let drops = [];
    const resize = () => {
      canvas.width = window.innerWidth; canvas.height = window.innerHeight;
      drops = Array.from({ length: Math.round(canvas.width / 9) }, () => ({ x: Math.random() * canvas.width, y: Math.random() * canvas.height, l: 8 + Math.random() * 18, v: 9 + Math.random() * 9 }));
    };
    resize(); window.addEventListener('resize', resize);
    const frame = () => {
      g.clearRect(0, 0, canvas.width, canvas.height);
      g.strokeStyle = 'rgba(200, 180, 255, 0.35)'; g.lineWidth = 1; g.beginPath();
      for (const d of drops) {
        g.moveTo(d.x, d.y); g.lineTo(d.x - d.l * 0.18, d.y + d.l);
        d.y += d.v; d.x -= d.v * 0.18;
        if (d.y > canvas.height) { d.y = -20; d.x = Math.random() * (canvas.width + 100); }
      }
      g.stroke();
      requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  }
})();
