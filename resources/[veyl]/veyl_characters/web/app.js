'use strict';

const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'veyl_characters';
const $ = (id) => document.getElementById(id);
let state = { characters: [], maxCharacters: 3, pending: false, deleteTarget: null };

function post(endpoint, body) {
    return fetch(`https://${resourceName}/${endpoint}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body || {}),
    }).catch(() => {});
}

function setPending(p, label) {
    state.pending = p;
    document.querySelectorAll('button').forEach((b) => { b.disabled = p; });
    if (label) $('stage').textContent = label;
}

function toast(message, type) {
    const t = $('toast');
    t.textContent = message;
    t.className = `toast ${type || ''}`;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => t.classList.add('hidden'), 3500);
}

function showPanel(id) {
    ['create', 'confirm-delete'].forEach((p) => $(p).classList.toggle('hidden', p !== id));
}

function render() {
    const slots = $('slots');
    slots.innerHTML = '';
    state.characters.forEach((c) => {
        const node = document.createElement('div');
        node.className = 'slot';
        const info = document.createElement('div');
        const name = document.createElement('div');
        name.className = 'slot-name';
        name.textContent = `${c.firstname} ${c.lastname}`;
        const meta = document.createElement('div');
        meta.className = 'slot-meta';
        meta.textContent = `Born ${c.dob}${c.lastPlayed ? ` · Last played ${c.lastPlayed}` : ' · New'}`;
        info.append(name, meta);

        const actions = document.createElement('div');
        actions.className = 'slot-actions';
        const play = document.createElement('button');
        play.className = 'btn primary small';
        play.textContent = 'Play';
        play.onclick = () => {
            if (state.pending) return;
            setPending(true, 'Loading character...');
            post('select', { id: c.id });
        };
        const del = document.createElement('button');
        del.className = 'btn ghost small';
        del.textContent = 'Delete';
        del.onclick = () => {
            state.deleteTarget = c;
            $('delete-name').textContent = `${c.firstname} ${c.lastname}`;
            $('delete-input').value = '';
            showPanel('confirm-delete');
        };
        actions.append(play, del);
        node.append(info, actions);
        slots.appendChild(node);
    });
    if (state.characters.length < state.maxCharacters) {
        const add = document.createElement('div');
        add.className = 'slot empty';
        add.textContent = `+ Create character (${state.characters.length}/${state.maxCharacters})`;
        add.onclick = () => { $('form-error').textContent = ''; showPanel('create'); };
        slots.appendChild(add);
    }
}

$('create-form').addEventListener('submit', (e) => {
    e.preventDefault();
    if (state.pending) return;
    $('form-error').textContent = '';
    setPending(true, 'Creating character...');
    post('create', {
        firstname: $('firstname').value.trim(), lastname: $('lastname').value.trim(),
        dob: $('dob').value, sex: $('sex').value,
    });
});
$('create-cancel').onclick = () => showPanel(null);
$('delete-cancel').onclick = () => showPanel(null);
$('delete-confirm').onclick = () => {
    if (state.pending || !state.deleteTarget) return;
    setPending(true, 'Deleting character...');
    post('delete', { id: state.deleteTarget.id, confirmName: $('delete-input').value.trim() });
};
$('retry').onclick = () => {
    $('error').classList.add('hidden');
    setPending(true, 'Retrying...');
    post('retry');
};
$('quit').onclick = () => post('disconnect');
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') showPanel(null); });

window.addEventListener('message', (event) => {
    const { action, data } = event.data || {};
    switch (action) {
        case 'open':
            $('app').classList.remove('hidden');
            showPanel(null);
            break;
        case 'close':
            $('app').classList.add('hidden');
            setPending(false, '');
            break;
        case 'stage':
            $('error').classList.add('hidden');
            $('stage').textContent = data.stage;
            break;
        case 'characters':
            state.characters = data.characters || [];
            if (data.maxCharacters) state.maxCharacters = data.maxCharacters;
            setPending(false, state.characters.length ? 'Select a character' : 'Create your first character');
            showPanel(null);
            render();
            break;
        case 'formError':
            setPending(false, '');
            $('form-error').textContent = data.message || 'Could not create character';
            break;
        case 'toast':
            setPending(false);
            toast(data.message, data.type);
            break;
        case 'error':
            setPending(false, '');
            $('retry').disabled = false;
            $('error').classList.remove('hidden');
            $('error-detail').textContent = `${data.stage}: ${data.message || ''}${data.code ? ` (${data.code})` : ''}`;
            break;
        default: break;
    }
});
