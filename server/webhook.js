// Delivery for ziks-bugreport: Discord webhook and/or ziks Dev Hub (https://dev.ushpuras.dev).
// Runs in the server's Node runtime: real binary multipart upload (screenshot + report files).
// Triggered only by the Lua side via a LOCAL server event (`on`, not `onNet`), so players cannot call it.
const https = require('https');

const TAG = '^3[ziks-bugreport]^7';
const VALID = /^https:\/\/(?:(?:ptb|canary)\.)?discord(?:app)?\.com\/api\/(?:v\d+\/)?webhooks\/\d+\/[\w-]+$/;
const MAX_TOTAL = 9.5 * 1024 * 1024; // Discord: 10 MiB per message on unboosted servers
const COLORS = { low: 0x5b8def, normal: 0x3fb37f, high: 0xe0a43b, critical: 0xe5484d };

let guildId = null;

function webhookUrl() {
  return (GetConvar('ziks_bugreport_webhook', '') || '').trim();
}
function devhubKey() {
  return (GetConvar('ziks_bugreport_devhub', '') || '').trim();
}
function devhubBase() {
  return (GetConvar('ziks_bugreport_devhub_url', 'https://dev.ushpuras.dev') || '').trim().replace(/\/+$/, '');
}
const DEVHUB_KEY = /^dhk_[0-9a-f]{48}$/;

function request(method, url, headers, body) {
  return new Promise((resolve) => {
    const u = new URL(url);
    const req = https.request(
      { method, hostname: u.hostname, path: u.pathname + u.search, headers: { 'User-Agent': 'ziks-bugreport (https://github.com/ziks29/ziks-bugreport, 1.0)', ...headers }, timeout: 60000 },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks).toString('utf8') }));
      }
    );
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', (e) => resolve({ status: 0, headers: {}, body: String(e && e.message) }));
    if (body) req.write(body);
    req.end();
  });
}

function multipart(payload, files) {
  const b = '----ziksbug' + Date.now().toString(16) + Math.random().toString(16).slice(2);
  const parts = [
    Buffer.from(`--${b}\r\nContent-Disposition: form-data; name="payload_json"\r\nContent-Type: application/json\r\n\r\n`),
    Buffer.from(JSON.stringify(payload), 'utf8'),
    Buffer.from('\r\n'),
  ];
  files.forEach((f, i) => {
    parts.push(Buffer.from(`--${b}\r\nContent-Disposition: form-data; name="files[${i}]"; filename="${f.name}"\r\nContent-Type: ${f.type}\r\n\r\n`));
    parts.push(f.data);
    parts.push(Buffer.from('\r\n'));
  });
  parts.push(Buffer.from(`--${b}--\r\n`));
  return { body: Buffer.concat(parts), type: `multipart/form-data; boundary=${b}` };
}

const cut = (s, n) => {
  s = s == null ? '' : String(s);
  return s.length > n ? s.slice(0, n - 1) + '…' : s;
};
// keep player text from pinging @everyone or breaking code blocks
const safe = (s) => String(s || '').replace(/@(everyone|here)/g, '@\u200b$1').replace(/```/g, "'''");

function buildMessage(r, files) {
  const L = r.labels || {};
  let desc = safe(r.description) || `*${L.none || 'No description'}*`;
  if (r.steps) desc += `\n\n**${L.steps || 'Steps to reproduce'}**\n${safe(r.steps)}`;
  if (r.expected) desc += `\n\n**${L.expected || 'Expected'}**\n${safe(r.expected)}`;
  if (r.actual) desc += `\n\n**${L.actual || 'Actual'}**\n${safe(r.actual)}`;

  const rep = r.reporter || {};
  let who = `${safe(rep.name)} · ID ${rep.server_id}`;
  if (rep.char) who += `\n${safe(rep.char)}`;
  if (rep.discord) who += `\n<@${rep.discord}>`;

  const fields = [
    { name: L.category || 'Category', value: cut(r.category || '-', 1024), inline: true },
    { name: L.severity || 'Severity', value: cut(r.severityLabel || r.severity, 1024), inline: true },
    { name: L.reporter || 'Reporter', value: cut(who, 1024), inline: true },
    { name: L.location || 'Location', value: cut(`${safe(r.location)}\n\`${r.coords}\``, 1024), inline: false },
  ];
  if (r.vehicle) fields.push({ name: L.vehicle || 'Vehicle', value: cut(safe(r.vehicle), 1024), inline: true });
  fields.push({ name: L.client || 'Client', value: cut(safe(r.client), 1024), inline: true });

  const embed = {
    title: cut(safe(r.title), 256),
    description: cut(desc, 4000),
    color: COLORS[r.severity] || COLORS.normal,
    fields,
    footer: { text: cut(['ziks-bugreport', r.server, r.build].filter(Boolean).join(' · '), 2048) },
    timestamp: new Date((r.at || Date.now() / 1000) * 1000).toISOString(),
  };
  if (files.some((f) => f.name === 'screenshot.jpg')) embed.image = { url: 'attachment://screenshot.jpg' };

  const payload = {
    username: 'Bug report',
    embeds: [embed],
    attachments: files.map((f, i) => ({ id: i, filename: f.name })),
    allowed_mentions: { parse: [], roles: r.pingRole ? [String(r.pingRole)] : [], users: [] },
  };
  if (r.pingRole) payload.content = `<@&${r.pingRole}>`;
  if (r.forum) {
    payload.thread_name = cut(`[${r.severityLabel || r.severity}] ${r.title}`, 100);
    if (r.forumTag) payload.applied_tags = [String(r.forumTag)];
  }
  return payload;
}

function filesFor(r, drop) {
  const files = [];
  const stamp = new Date((r.at || Date.now() / 1000) * 1000).toISOString().replace(/[:T]/g, '-').slice(0, 19);
  if (r.screenshot && !drop.has('shot')) {
    const data = Buffer.from(r.screenshot, 'base64');
    if (data.length > 0) files.push({ name: 'screenshot.jpg', type: 'image/jpeg', data });
  }
  if (r.reportText && !drop.has('report')) files.push({ name: `report-${stamp}.txt`, type: 'text/plain; charset=utf-8', data: Buffer.from(r.reportText, 'utf8') });
  if (r.playerJson && !drop.has('player')) {
    let pretty = r.playerJson;
    try { pretty = JSON.stringify(JSON.parse(r.playerJson), null, 2); } catch (_) {}
    files.push({ name: `player-${(r.reporter && r.reporter.server_id) || 'x'}.json`, type: 'application/json', data: Buffer.from(pretty, 'utf8') });
  }
  return files;
}

const sleep = (ms) => new Promise((res) => setTimeout(res, ms));

async function sendDevhub(r) {
  const key = devhubKey();
  if (!DEVHUB_KEY.test(key)) return ['fail', 'ziks_bugreport_devhub is not a Dev Hub key (dhk_...)'];
  const rep = r.reporter || {};
  const payload = {
    title: r.title, description: r.description, category: r.category, severity: r.severity,
    reproduction: r.steps, expected: r.expected, actual: r.actual,
    environment: r.environment || '', build: r.build || '',
    reporter: { server_id: String(rep.server_id || ''), citizenid: rep.citizenid || '', discord_id: rep.discord || '', name: rep.name || '', char: rep.char || '', job: rep.job || '' },
    screenshot_b64: r.screenshot || undefined,
    player_data: r.playerJson || undefined,
    server_console: r.serverConsole || undefined,
    report_text: r.reportText || undefined,
  };
  const body = Buffer.from(JSON.stringify(payload), 'utf8');
  for (let attempt = 1; attempt <= 3; attempt++) {
    const res = await request('POST', devhubBase() + '/api/ingest/bug', { 'Content-Type': 'application/json', 'Content-Length': body.length, Authorization: 'Bearer ' + key }, body);
    if (res.status === 201) {
      let url = null;
      try { url = JSON.parse(res.body).url || null; } catch (_) {}
      return ['ok', url];
    }
    if (res.status === 429) return ['retry', 'Dev Hub hourly report limit reached'];
    if (res.status === 0 || res.status >= 500) {
      if (attempt < 3) { await sleep(1500 * attempt); continue; }
      return ['retry', `Dev Hub HTTP ${res.status}`];
    }
    return ['fail', `Dev Hub HTTP ${res.status} ${cut(res.body, 200)}`];
  }
  return ['retry', 'Dev Hub gave up after retries'];
}

async function send(r) {
  const url = webhookUrl();
  if (!url) return ['fail', 'webhook not configured'];
  if (!VALID.test(url)) return ['fail', 'ziks_bugreport_webhook is not a Discord webhook URL'];

  // drop the biggest optional files first if the message is too large
  const drop = new Set();
  const order = ['player', 'report', 'shot'];
  let files = filesFor(r, drop);
  while (files.reduce((n, f) => n + f.data.length, 0) > MAX_TOTAL && order.length) {
    drop.add(order.shift());
    files = filesFor(r, drop);
  }

  for (let attempt = 1; attempt <= 4; attempt++) {
    const { body, type } = multipart(buildMessage(r, files), files);
    const res = await request('POST', url + '?wait=true', { 'Content-Type': type, 'Content-Length': body.length }, body);
    if (res.status === 200 || res.status === 204) {
      let link = null;
      try {
        const m = JSON.parse(res.body);
        if (guildId && m.channel_id && m.id) link = `https://discord.com/channels/${guildId}/${m.channel_id}/${m.id}`;
      } catch (_) {}
      return ['ok', link];
    }
    if (res.status === 429) {
      let wait = 2;
      try { wait = Number(JSON.parse(res.body).retry_after) || wait; } catch (_) {}
      if (wait > 30) return ['retry', `rate limited for ${wait}s`];
      await sleep(wait * 1000 + 250);
      continue;
    }
    if (res.status === 413 && order.length) {
      drop.add(order.shift());
      files = filesFor(r, drop);
      continue;
    }
    if (res.status === 0 || res.status >= 500) {
      if (attempt < 4) { await sleep(1500 * attempt); continue; }
      return ['retry', `HTTP ${res.status} ${cut(res.body, 120)}`];
    }
    return ['fail', `HTTP ${res.status} ${cut(res.body, 200)}`];
  }
  return ['retry', 'gave up after retries'];
}

// Sends to every configured target (or only report.targets when retrying a queued report).
// ok if any target succeeded; retry if the rest only failed temporarily; remaining = targets to retry.
async function deliverAll(report) {
  const configured = [];
  if (webhookUrl()) configured.push('webhook');
  if (devhubKey()) configured.push('devhub');
  const targets = Array.isArray(report.targets) && report.targets.length ? report.targets.filter((t) => configured.includes(t)) : configured;
  if (!targets.length) return ['fail', 'no delivery target configured', []];
  const results = await Promise.all(targets.map(async (t) => {
    try { return [t, ...(t === 'devhub' ? await sendDevhub(report) : await send(report))]; }
    catch (e) { return [t, 'retry', String(e && e.message)]; }
  }));
  const ok = results.filter((x) => x[1] === 'ok');
  const retry = results.filter((x) => x[1] === 'retry');
  const fail = results.filter((x) => x[1] === 'fail');
  fail.forEach((x) => console.log(`${TAG} ^1${x[0]} rejected the report:^7 ${x[2]}`));
  if (retry.length) return [ok.length ? 'ok' : 'retry', retry.map((x) => `${x[0]}: ${x[2]}`).join('; '), retry.map((x) => x[0])];
  if (ok.length) return ['ok', (ok.find((x) => x[0] === 'devhub') || ok[0])[2], []];
  return ['fail', fail.map((x) => `${x[0]}: ${x[2]}`).join('; '), []];
}

on('ziks-bugreport:deliver', async (id, report) => {
  let out;
  try { out = await deliverAll(report || {}); } catch (e) { out = ['retry', String(e && e.message), []]; }
  emit('ziks-bugreport:delivered', id, out[0], out[1], out[2]);
});

// startup check: validates the webhook and remembers the guild for message links
setTimeout(async () => {
  const key = devhubKey();
  if (key) {
    if (!DEVHUB_KEY.test(key)) console.log(`${TAG} ^1ziks_bugreport_devhub is not a Dev Hub key (dhk_...).^7`);
    else {
      const res = await request('GET', devhubBase() + '/api/ingest/ping', { Authorization: 'Bearer ' + key });
      if (res.status === 200) {
        try { const d = JSON.parse(res.body); console.log(`${TAG} Dev Hub OK: "${d.workspace.name}" -> ${d.url}`); } catch (_) {}
      } else console.log(`${TAG} ^1Dev Hub check failed: HTTP ${res.status}^7 (revoked key?)`);
    }
  }
  const url = webhookUrl();
  if (!url) {
    if (!key) console.log(`${TAG} ^1Nothing to send to.^7 Add to server.cfg:  set ziks_bugreport_webhook "https://discord.com/api/webhooks/..."  and/or  set ziks_bugreport_devhub "dhk_..."`);
    return;
  }
  if (!VALID.test(url)) {
    console.log(`${TAG} ^1ziks_bugreport_webhook does not look like a Discord webhook URL.^7`);
    return;
  }
  const res = await request('GET', url, {});
  if (res.status === 200) {
    try {
      const w = JSON.parse(res.body);
      guildId = w.guild_id || null;
      console.log(`${TAG} webhook OK: "${w.name}" -> channel ${w.channel_id}`);
    } catch (_) {}
  } else {
    console.log(`${TAG} ^1webhook check failed: HTTP ${res.status}^7 (deleted webhook or wrong URL?)`);
  }
}, 1000);

if (typeof module !== 'undefined') module.exports = { buildMessage, filesFor, multipart, send, sendDevhub, deliverAll, VALID };
