#!/usr/bin/env node
// Posts commit changelogs to a Discord channel through a webhook.
//
//   node tools/discord-changelog.mjs                 commits since the last post (state in .changelog-state)
//   node tools/discord-changelog.mjs --last 5        the last 5 changes
//   node tools/discord-changelog.mjs abc123..def456  a commit range (used by the GitHub workflow)
//   add --dry-run to print what would be sent
//
// The webhook URL is a secret: it is read from the DISCORD_WEBHOOK_URL environment variable or from the
// .discord-webhook file in the repository root (both ignored by git). It is never committed.
// "Recipe: pin ..." commits are housekeeping and are skipped.

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const stateFile = join(root, '.changelog-state');
const args = process.argv.slice(2);
const dry = args.includes('--dry-run');
const COLOR = 0x9b72d5;
const SKIP = [/^Recipe: pin/i, /^Merge /];

function git(...a) { return execFileSync('git', a, { cwd: root, encoding: 'utf8' }).trim(); }

function webhook() {
  const url = (process.env.DISCORD_WEBHOOK_URL || (existsSync(join(root, '.discord-webhook')) ? readFileSync(join(root, '.discord-webhook'), 'utf8') : '')).trim();
  if (!/^https:\/\/(discord\.com|discordapp\.com)\/api\/webhooks\/\d+\/[\w-]+$/.test(url)) return null;
  return url;
}

function range() {
  const r = args.find((a) => a.includes('..'));
  if (r) return r;
  const i = args.indexOf('--last');
  if (i >= 0) return `HEAD~${Math.max(1, Number(args[i + 1]) || 1)}..HEAD`;
  if (existsSync(stateFile)) return `${readFileSync(stateFile, 'utf8').trim()}..HEAD`;
  return 'HEAD~1..HEAD';
}

function commits(rng) {
  const SEP = '\u001e', END = '\u001f';
  const out = git('log', '--reverse', `--format=%H${SEP}%h${SEP}%aI${SEP}%s${SEP}%b${END}`, rng);
  return out.split(END).map((c) => c.trim()).filter(Boolean).map((c) => {
    const [hash, short, date, subject, body = ''] = c.split(SEP);
    return { hash, short, date, subject: subject.trim(), body: body.trim() };
  }).filter((c) => !SKIP.some((re) => re.test(c.subject)));
}

/** Commit body -> Discord text: bullet lines kept, attribution trailers dropped, length capped. */
function describe(body) {
  const lines = body.split(/\r?\n/).filter((l) => !/^(Co-Authored-By|Signed-off-by):/i.test(l));
  let text = '';
  for (const raw of lines) {
    const l = raw.replace(/^\s*-\s+/, '• ').replace(/^\s{2,}/, '  ');
    if (!l.trim()) continue;
    // Continuation lines of a bullet are joined onto it.
    text += (l.startsWith('• ') || !text ? (text ? '\n' : '') : ' ') + l.trim();
  }
  return text.length > 3800 ? `${text.slice(0, 3797)}…` : text;
}

function embedFor(c) {
  const [, scope, rest] = c.subject.match(/^([\w-]+):\s+(.*)$/) || [];
  return {
    title: (scope ? `${scope} — ${rest}` : c.subject).slice(0, 256),
    description: describe(c.body) || undefined,
    color: COLOR,
    footer: { text: c.short },
    timestamp: c.date,
  };
}

/** Discord limits: 10 embeds and ~6000 characters per message. */
function batches(embeds) {
  const size = (e) => (e.title?.length ?? 0) + (e.description?.length ?? 0) + (e.footer?.text.length ?? 0);
  const out = [];
  let cur = [], total = 0;
  for (const e of embeds) {
    if (cur.length && (cur.length === 10 || total + size(e) > 5500)) { out.push(cur); cur = []; total = 0; }
    cur.push(e); total += size(e);
  }
  if (cur.length) out.push(cur);
  return out;
}

async function send(url, payload) {
  for (let attempt = 0; attempt < 5; attempt++) {
    const res = await fetch(`${url}?wait=true`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'User-Agent': 'veylcore-changelog' }, body: JSON.stringify(payload) });
    if (res.status === 429) { const j = await res.json().catch(() => ({})); await new Promise((r) => setTimeout(r, Math.ceil((j.retry_after ?? 1) * 1000) + 250)); continue; }
    if (!res.ok) throw new Error(`Discord answered ${res.status}: ${(await res.text()).slice(0, 300)}`);
    return;
  }
  throw new Error('Discord kept rate-limiting the webhook');
}

const rng = range();
const list = commits(rng);
if (list.length === 0) { console.log(`No changes to post in ${rng}.`); process.exit(0); }
const groups = batches(list.map(embedFor));
const payloads = groups.map((embeds, i) => ({
  username: 'VeylCore Changelog',
  content: i === 0 ? `**VeylCore update** · ${list.length} change${list.length === 1 ? '' : 's'}` : undefined,
  embeds,
  allowed_mentions: { parse: [] },
}));

if (dry) { console.log(JSON.stringify(payloads, null, 2)); process.exit(0); }
const url = webhook();
if (!url) { console.error('No webhook: set DISCORD_WEBHOOK_URL or put the URL in .discord-webhook (git-ignored).'); process.exit(1); }
for (const p of payloads) { await send(url, p); await new Promise((r) => setTimeout(r, 1100)); }
if (!args.some((a) => a.includes('..'))) writeFileSync(stateFile, git('rev-parse', 'HEAD') + '\n');
console.log(`Posted ${list.length} change${list.length === 1 ? '' : 's'} in ${payloads.length} message${payloads.length === 1 ? '' : 's'}.`);
