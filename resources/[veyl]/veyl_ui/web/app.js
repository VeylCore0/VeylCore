'use strict';

const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'veyl_ui';
const $ = (id) => document.getElementById(id);

function post(endpoint, body) {
    return fetch(`https://${resourceName}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(body || {}),
    }).catch(() => {});
}

function el(tag, attrs, ...children) {
    const node = document.createElement(tag);
    Object.entries(attrs || {}).forEach(([k, v]) => {
        if (k === 'class') node.className = v;
        else if (k.startsWith('on')) node.addEventListener(k.slice(2), v);
        else if (v !== undefined && v !== null && v !== false) node.setAttribute(k, v === true ? '' : v);
    });
    children.flat().forEach((c) => {
        if (c === null || c === undefined) return;
        node.appendChild(typeof c === 'string' || typeof c === 'number' ? document.createTextNode(String(c)) : c);
    });
    return node;
}

/* ---------------- Notifications ---------------- */
function notify({ message, type, duration }) {
    const node = el('div', { class: `notify ${['success', 'error', 'warning'].includes(type) ? type : ''}` }, message);
    $('notifications').appendChild(node);
    const list = $('notifications');
    while (list.children.length > 5) list.removeChild(list.firstChild);
    setTimeout(() => {
        node.classList.add('leaving');
        setTimeout(() => node.remove(), 220);
    }, Math.max(1500, Math.min(duration || 4500, 15000)));
}

/* ---------------- Progress ---------------- */
let progressAnim = null;
function progressStart({ label, duration }) {
    $('progress-label').textContent = label;
    const fill = $('progress-fill');
    fill.style.transition = 'none';
    fill.style.width = '0%';
    $('progress').classList.remove('hidden');
    cancelAnimationFrame(progressAnim);
    progressAnim = requestAnimationFrame(() => {
        fill.style.transition = `width ${duration}ms linear`;
        fill.style.width = '100%';
    });
}
function progressStop() {
    cancelAnimationFrame(progressAnim);
    $('progress').classList.add('hidden');
}

/* ---------------- Modals ---------------- */
let modalOpen = false;
let submitting = false;

function closeModalView() {
    modalOpen = false;
    submitting = false;
    $('modal-backdrop').classList.add('hidden');
    $('modal-body').innerHTML = '';
    $('modal-footer').innerHTML = '';
}

function sendResult(value) {
    if (!modalOpen || submitting) return;
    submitting = true; // prevent repeated clicks while Lua handles the result
    post('modal:result', { value });
}

function cancelModal() {
    if (!modalOpen || submitting) return;
    submitting = true;
    post('modal:cancel');
}

function openModal(kind, data) {
    modalOpen = true;
    submitting = false;
    $('modal-title').textContent = data.title || (kind === 'confirm' ? 'Are you sure?' : kind === 'input' ? 'Enter details' : 'Menu');
    $('modal-subtitle').textContent = data.subtitle || '';
    const body = $('modal-body');
    const footer = $('modal-footer');
    body.innerHTML = '';
    footer.innerHTML = '';

    if (kind === 'confirm') {
        body.appendChild(el('p', { class: 'message' }, data.message || ''));
        footer.append(
            el('button', { class: 'btn', onclick: () => sendResult(false) }, data.cancelLabel || 'Cancel'),
            el('button', { class: 'btn primary', onclick: () => sendResult(true) }, data.confirmLabel || 'Confirm'),
        );
    } else if (kind === 'input') {
        const fields = Array.isArray(data.fields) ? data.fields : [];
        const form = el('form', { onsubmit: (e) => { e.preventDefault(); submitInput(fields, form); } });
        fields.forEach((f, i) => {
            const id = `f_${i}`;
            let input;
            if (f.type === 'select') {
                input = el('select', { id, name: f.name },
                    (f.options || []).map((o) => el('option', { value: o.value, selected: o.value === f.default }, o.label)));
            } else {
                input = el('input', {
                    id, name: f.name, type: f.type === 'number' ? 'number' : (f.type === 'date' ? 'date' : 'text'),
                    min: f.min, max: f.max, maxlength: f.maxLength, placeholder: f.placeholder || '',
                    value: f.default !== undefined ? f.default : '',
                });
            }
            form.appendChild(el('div', { class: 'field' }, el('label', { for: id }, f.label || f.name), input, el('div', { class: 'error' })));
        });
        body.appendChild(form);
        footer.append(
            el('button', { class: 'btn', onclick: cancelModal }, 'Cancel'),
            el('button', { class: 'btn primary', onclick: () => submitInput(fields, form) }, data.submitLabel || 'Submit'),
        );
        const first = form.querySelector('input,select');
        if (first) setTimeout(() => first.focus(), 30);
    } else if (kind === 'menu') {
        const items = Array.isArray(data.items) ? data.items : [];
        if (items.length === 0) body.appendChild(el('div', { class: 'empty' }, data.emptyText || 'Nothing here yet.'));
        items.forEach((item) => {
            body.appendChild(el('button', {
                class: 'menu-item', disabled: item.disabled === true,
                onclick: () => sendResult(item.value),
            },
            item.right ? el('span', { class: 'right' }, String(item.right)) : null,
            el('div', { class: 'label' }, item.label || ''),
            item.description ? el('div', { class: 'desc' }, item.description) : null));
        });
    }
    $('modal-backdrop').classList.remove('hidden');
}

function submitInput(fields, form) {
    const values = {};
    let valid = true;
    fields.forEach((f, i) => {
        const input = form.querySelector(`#f_${i}`);
        const err = input.parentElement.querySelector('.error');
        err.textContent = '';
        let v = input.value;
        if (f.type === 'number') {
            if (v === '') v = null; else v = Number(v);
            if (v !== null && (Number.isNaN(v) || (f.min !== undefined && v < f.min) || (f.max !== undefined && v > f.max))) {
                err.textContent = `Enter a number${f.min !== undefined ? ` from ${f.min}` : ''}${f.max !== undefined ? ` to ${f.max}` : ''}`;
                valid = false;
            }
        } else if (typeof v === 'string') {
            v = v.trim();
        }
        if (f.required && (v === null || v === '')) { err.textContent = 'Required'; valid = false; }
        values[f.name] = v;
    });
    if (valid) sendResult(values);
}

$('modal-close').addEventListener('click', cancelModal);
$('modal-backdrop').addEventListener('mousedown', (e) => { if (e.target === $('modal-backdrop')) cancelModal(); });
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && modalOpen) cancelModal(); });

window.addEventListener('message', (event) => {
    const d = event.data || {};
    switch (d.action) {
        case 'notify': notify(d); break;
        case 'progress:start': progressStart(d); break;
        case 'progress:stop': progressStop(); break;
        case 'modal:open': openModal(d.kind, d.data || {}); break;
        case 'modal:close': closeModalView(); break;
        default: break;
    }
});
