#!/usr/bin/env node
// Publishes ROADMAP.md to a Discord channel through a webhook, as one message per section.
// The first run posts the messages and remembers their ids (.roadmap-state, git-ignored); later runs EDIT those
// same messages, so the channel always shows one up-to-date roadmap. Sections added later are posted as new messages,
// and messages for removed sections are deleted.
//
//   node tools/discord-roadmap.mjs            publish / update
//   node tools/discord-roadmap.mjs --dry-run  print what would be sent
//   node tools/discord-roadmap.mjs --repost   forget the old messages and post fresh ones
//
// The webhook URL is a secret: DISCORD_ROADMAP_WEBHOOK_URL or the git-ignored .discord-roadmap-webhook file.

import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const stateFile = join(root, '.roadmap-state');
const args = process.argv.slice(2);
const dry = args.includes('--dry-run');
const COLORS = { '✅': 0x5fd3a5, '🧪': 0x6fc8e0, '🛠️': 0xb892f4, '🔜': 0x7aa7ff, '🌱': 0xe9be71 };

function webhook() {
  const file = join(root, '.discord-roadmap-webhook');
  const url = (process.env.DISCORD_ROADMAP_WEBHOOK_URL || (existsSync(file) ? readFileSync(file, 'utf8') : '')).trim();
  return /^https:\/\/(discord\.com|discordapp\.com)\/api\/webhooks\/\d+\/[\w-]+$/.test(url) ? url : null;
}

/** ROADMAP.md -> { title, intro, sections: [{ title, body }] }. Markdown bold and bullets are Discord-compatible. */
function parse() {
  const md = readFileSync(join(root, 'ROADMAP.md'), 'utf8').replace(/\r\n/g, '\n');
  const title = (md.match(/^# (.+)$/m) || [, 'Roadmap'])[1].trim();
  const parts = md.split(/^## /m);
  const intro = parts[0].replace(/^# .+$/m, '').trim();
  const sections = parts.slice(1).map((p) => {
    const [head, ...rest] = p.split('\n');
    return { title: head.trim(), body: rest.join('\n').trim().replace(/^- /gm, '• ') };
  });
  return { title, intro, sections };
}

function messages() {
  const { title, intro, sections } = parse();
  const updated = new Date().toISOString();
  const out = [{ username: 'VeylCore Roadmap', content: `# ${title}\n${intro}`.slice(0, 2000), embeds: [], allowed_mentions: { parse: [] } }];
  for (const s of sections) {
    const icon = Object.keys(COLORS).find((k) => s.title.startsWith(k));
    out.push({
      username: 'VeylCore Roadmap',
      embeds: [{ title: s.title.slice(0, 256), description: s.body.slice(0, 4000), color: COLORS[icon] ?? 0x9b72d5, footer: { text: 'Last updated' }, timestamp: updated }],
      allowed_mentions: { parse: [] },
    });
  }
  return out;
}

async function call(method, url, body) {
  for (let attempt = 0; attempt < 5; attempt++) {
    const res = await fetch(url, { method, headers: { 'Content-Type': 'application/json', 'User-Agent': 'veylcore-roadmap' }, body: body ? JSON.stringify(body) : undefined });
    if (res.status === 429) { const j = await res.json().catch(() => ({})); await new Promise((r) => setTimeout(r, Math.ceil((j.retry_after ?? 1) * 1000) + 250)); continue; }
    if (res.status === 404 && method !== 'POST') return null; // message was deleted in Discord
    if (!res.ok) throw new Error(`Discord answered ${res.status}: ${(await res.text()).slice(0, 300)}`);
    return method === 'DELETE' ? true : res.json();
  }
  throw new Error('Discord kept rate-limiting the webhook');
}

const list = messages();
if (dry) { console.log(JSON.stringify(list, null, 2)); process.exit(0); }
const url = webhook();
if (!url) { console.error('No webhook: set DISCORD_ROADMAP_WEBHOOK_URL or put the URL in .discord-roadmap-webhook (git-ignored).'); process.exit(1); }

const old = !args.includes('--repost') && existsSync(stateFile) ? JSON.parse(readFileSync(stateFile, 'utf8')) : [];
const ids = [];
let posted = 0, edited = 0, removed = 0;
for (let i = 0; i < list.length; i++) {
  let msg = null;
  if (old[i]) { msg = await call('PATCH', `${url}/messages/${old[i]}`, list[i]); if (msg) edited++; }
  // Messages must stay in order: once one has to be re-posted, post everything after it fresh too.
  if (!msg) {
    for (let j = i; j < old.length; j++) if (old[j]) { await call('DELETE', `${url}/messages/${old[j]}`); }
    old.length = i;
    msg = await call('POST', `${url}?wait=true`, list[i]);
    posted++;
  }
  ids.push(msg.id);
  await new Promise((r) => setTimeout(r, 700));
}
for (let j = list.length; j < old.length; j++) if (old[j]) { await call('DELETE', `${url}/messages/${old[j]}`); removed++; }
writeFileSync(stateFile, JSON.stringify(ids) + '\n');
console.log(`Roadmap published: ${edited} updated, ${posted} posted, ${removed} removed.`);
