'use strict';

const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'veyl_appearance';
const $ = (id) => document.getElementById(id);
let state = { rows: [], headBlend: {}, hair: {}, allowCancel: true, saving: false };

async function post(endpoint, body) {
    try {
        const r = await fetch(`https://${resourceName}/${endpoint}`, {
            method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body || {}),
        });
        return await r.json();
    } catch (e) { return {}; }
}

function slider(label, min, max, value, onInput, sub) {
    const wrap = document.createElement('div');
    wrap.className = 'field';
    const lab = document.createElement('label');
    const val = document.createElement('span');
    val.textContent = value;
    lab.append(document.createTextNode(label), val);
    const input = document.createElement('input');
    input.type = 'range'; input.min = min; input.max = max; input.step = 1; input.value = value;
    input.disabled = max <= min;
    input.addEventListener('input', () => { val.textContent = input.value; onInput(Number(input.value), input, val); });
    wrap.append(lab, input);
    if (sub) { const s = document.createElement('div'); s.className = 'sub'; s.textContent = sub; wrap.append(s); }
    return { wrap, input, val };
}

function renderBody() {
    const blend = $('blend');
    blend.innerHTML = '';
    const hb = state.headBlend;
    const sendBlend = () => post('change', { kind: 'headBlend', values: hb });
    const sendHair = () => post('change', { kind: 'hair', values: state.hair });
    blend.append(
        slider('Mother', 0, 45, hb.mother, (v) => { hb.mother = v; sendBlend(); }).wrap,
        slider('Father', 0, 45, hb.father, (v) => { hb.father = v; sendBlend(); }).wrap,
        slider('Face resemblance', 0, 100, hb.shapeMix, (v) => { hb.shapeMix = v; sendBlend(); }).wrap,
        slider('Skin tone', 0, 100, hb.skinMix, (v) => { hb.skinMix = v; sendBlend(); }).wrap,
        slider('Hair colour', 0, 63, state.hair.color, (v) => { state.hair.color = v; sendHair(); }).wrap,
        slider('Hair highlight', 0, 63, state.hair.highlight, (v) => { state.hair.highlight = v; sendHair(); }).wrap,
    );
}

function renderClothing() {
    const root = $('tab-clothing');
    root.innerHTML = '';
    state.rows.forEach((row) => {
        let tex;
        const draw = slider(row.label, row.minD, row.maxD, row.d, async (v) => {
            row.d = v; row.t = 0;
            const r = await post('change', { kind: row.kind, id: row.id, d: row.d, t: 0 });
            if (r && typeof r.maxT === 'number') {
                tex.input.max = r.maxT; tex.input.value = 0; tex.val.textContent = '0';
                tex.input.disabled = r.maxT <= 0;
            }
        });
        tex = slider(`${row.label} style`, 0, row.maxT, row.t, (v) => {
            row.t = v;
            post('change', { kind: row.kind, id: row.id, d: row.d, t: v });
        });
        root.append(draw.wrap, tex.wrap);
    });
}

function setSex(sex) {
    document.querySelectorAll('.seg-btn').forEach((b) => b.classList.toggle('active', b.dataset.sex === sex));
}

document.querySelectorAll('.tab').forEach((tab) => tab.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t === tab));
    $('tab-body').classList.toggle('hidden', tab.dataset.tab !== 'body');
    $('tab-clothing').classList.toggle('hidden', tab.dataset.tab !== 'clothing');
}));
document.querySelectorAll('.seg-btn').forEach((b) => b.addEventListener('click', async () => {
    setSex(b.dataset.sex);
    const r = await post('change', { kind: 'sex', value: b.dataset.sex });
    if (r && r.rows) { state.rows = r.rows; state.headBlend = r.headBlend; state.hair = r.hair; renderBody(); renderClothing(); }
}));
document.querySelectorAll('[data-rot]').forEach((b) => b.addEventListener('click', () => post('change', { kind: 'rotate', value: Number(b.dataset.rot) })));
$('save').addEventListener('click', () => {
    if (state.saving) return;
    state.saving = true;
    $('save').disabled = true;
    $('error').textContent = '';
    post('save');
});
$('cancel').addEventListener('click', () => post('cancel'));
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && state.allowCancel) post('cancel'); });

window.addEventListener('message', (event) => {
    const d = event.data || {};
    if (d.action === 'open') {
        state = { rows: d.rows || [], headBlend: d.headBlend || {}, hair: d.hair || {}, allowCancel: d.allowCancel, saving: false };
        $('cancel').classList.toggle('hidden', !d.allowCancel);
        $('save').disabled = false;
        $('error').textContent = '';
        setSex(d.sex);
        renderBody();
        renderClothing();
        $('editor').classList.remove('hidden');
    } else if (d.action === 'close') {
        $('editor').classList.add('hidden');
    } else if (d.action === 'error') {
        state.saving = false;
        $('save').disabled = false;
        $('error').textContent = d.message || 'Could not save';
    }
});
