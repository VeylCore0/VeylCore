'use strict';

const $ = (id) => document.getElementById(id);
const STATS = [
    { key: 'health', icon: '♥', color: '#f87171' },
    { key: 'armor', icon: '⛨', color: '#60a5fa', hideZero: true },
    { key: 'hunger', icon: '🍔', color: '#fbbf24' },
    { key: 'thirst', icon: '💧', color: '#38bdf8' },
    { key: 'stress', icon: '✺', color: '#c084fc', hideZero: true, invert: true },
    { key: 'stamina', icon: '⚡', color: '#a3e635', hideFull: true },
    { key: 'oxygen', icon: '◎', color: '#67e8f9' },
];

const money = (n) => `$${Number(n || 0).toLocaleString('en-US')}`;

function render(d) {
    $('hud').classList.toggle('hidden', !d.show);
    if (!d.show) return;
    const status = $('status');
    status.innerHTML = '';
    STATS.forEach((s) => {
        const v = d[s.key];
        if (v === undefined || v === null) return;
        if (s.hideZero && v <= 0) return;
        if (s.hideFull && v >= 100) return;
        const node = document.createElement('div');
        const low = s.invert ? v >= 80 : v <= 15;
        node.className = `stat${low ? ' low' : ''}`;
        node.style.setProperty('--v', Math.max(0, Math.min(100, v)));
        node.style.setProperty('--c', s.color);
        node.title = s.key;
        const icon = document.createElement('span');
        icon.textContent = s.icon;
        node.appendChild(icon);
        status.appendChild(node);
    });
    $('cash').textContent = money(d.cash);
    $('bank').textContent = money(d.bank);
    $('job').textContent = `${d.talking ? '🎙 ' : ''}${d.job || ''}`;

    const inVeh = d.speed !== undefined && d.speed !== null;
    $('vehicle').classList.toggle('hidden', !inVeh);
    if (inVeh) {
        $('speed').textContent = d.speed;
        const fuel = d.fuel === undefined || d.fuel === null ? null : d.fuel;
        $('fuel').style.width = `${fuel === null ? 100 : fuel}%`;
        $('locked').textContent = d.locked ? '· LOCKED' : '';
    }
}

window.addEventListener('message', (e) => {
    if (e.data && e.data.action === 'update') render(e.data.data || {});
});
