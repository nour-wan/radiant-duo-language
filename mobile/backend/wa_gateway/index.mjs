// Alas WhatsApp gateway: a WhatsApp number linked like WhatsApp Web (scan a QR once),
// used only to send verification codes. Listens on 127.0.0.1; every request needs the key.
//
//   GET  /status          -> { status: "connecting" | "qr" | "open" | "closed", qr, me }
//   POST /send {to, text} -> { ok: true } | 4xx { error }
//   POST /pair {phone}    -> { code } to type on the phone instead of scanning the QR
//   POST /logout          -> unlinks the number (a new QR follows)

import { randomUUID, timingSafeEqual } from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const baileys = require('@whiskeysockets/baileys');
const QRCode = require('qrcode');
const pino = require('pino');

const makeWASocket = baileys.default;
const { useMultiFileAuthState, DisconnectReason, fetchLatestBaileysVersion, Browsers } = baileys;

const PORT = Number(process.env.WA_PORT || 8110);
const AUTH_DIR = process.env.WA_AUTH_DIR || '/var/lib/alas-wa/auth';
const KEY = fs.readFileSync(process.env.WA_KEY_FILE || '/etc/alas-wa/key', 'utf8').trim();
const SEND_GAP_MS = 2500; // one message at a time, spaced out like a person would

const logger = pino({ level: process.env.WA_LOG_LEVEL || 'warn' });
let sock = null;
let state = { status: 'connecting', qr: null, me: null };
let restartTimer = null;

function wipeAuth() {
  fs.rmSync(AUTH_DIR, { recursive: true, force: true });
}

// What we sent in the last 24 hours, by message id. When a phone can't decrypt a message (its
// encryption session changed, e.g. after this service restarted) it asks us to send it again; without
// the text WhatsApp shows "Waiting for this message" forever. Kept on disk so a restart doesn't lose it.
const SENT_FILE = process.env.WA_SENT_FILE || `${AUTH_DIR}/../sent-messages.json`;
const SENT_TTL_MS = 24 * 60 * 60 * 1000;
const sent = new Map();
try {
  for (const [id, v] of Object.entries(JSON.parse(fs.readFileSync(SENT_FILE, 'utf8')))) {
    if (Date.now() - v.t < SENT_TTL_MS) sent.set(id, v);
  }
} catch {
  // first run, or nothing saved yet
}
let saveTimer = null;
function rememberSent(msg, text) {
  if (!msg?.key?.id) return;
  sent.set(msg.key.id, { text, t: Date.now() });
  for (const [id, v] of sent) {
    if (Date.now() - v.t > SENT_TTL_MS || sent.size > 2000) sent.delete(id);
    else break; // oldest first
  }
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    try {
      fs.writeFileSync(SENT_FILE, JSON.stringify(Object.fromEntries(sent)), { mode: 0o600 });
    } catch (e) {
      logger.error(e, 'could not save sent messages');
    }
  }, 500);
}

async function start() {
  clearTimeout(restartTimer);
  fs.mkdirSync(AUTH_DIR, { recursive: true, mode: 0o700 });
  const { state: auth, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
  const { version } = await fetchLatestBaileysVersion().catch(() => ({ version: undefined }));
  state = { status: 'connecting', qr: null, me: null };
  const s = makeWASocket({
    version,
    auth,
    logger,
    browser: Browsers.ubuntu('Alas Foodstuff'),
    markOnlineOnConnect: false,
    syncFullHistory: false,
    // Lets WhatsApp re-send a message a phone couldn't decrypt (see rememberSent)
    getMessage: async (key) => {
      const hit = sent.get(key.id);
      return hit ? { conversation: hit.text } : undefined;
    },
  });
  sock = s;
  s.ev.on('creds.update', saveCreds);
  s.ev.on('connection.update', async (u) => {
    if (s !== sock) return; // an old socket after a restart
    if (u.qr) {
      state = { status: 'qr', qr: await QRCode.toDataURL(u.qr, { margin: 1, width: 360 }), me: null };
    }
    if (u.connection === 'open') {
      state = { status: 'open', qr: null, me: (s.user?.id || '').split(':')[0].split('@')[0] };
      logger.warn({ me: state.me }, 'linked');
    }
    if (u.connection === 'close') {
      const code = u.lastDisconnect?.error?.output?.statusCode;
      if (code === DisconnectReason.loggedOut) {
        // Unlinked from the phone (or by /logout): start over with a fresh QR
        wipeAuth();
        state = { status: 'closed', qr: null, me: null };
      } else {
        state = { ...state, status: 'connecting' };
      }
      restartTimer = setTimeout(() => start().catch((e) => logger.error(e)), 3000);
    }
  });
}

// Messages leave strictly one after another
let queue = Promise.resolve();
function send(to, text) {
  const job = queue.then(async () => {
    if (state.status !== 'open') throw Object.assign(new Error('not_linked'), { http: 503 });
    const jid = `${String(to).replace(/\D/g, '')}@s.whatsapp.net`;
    const [found] = await sock.onWhatsApp(jid);
    if (!found?.exists) throw Object.assign(new Error('not_on_whatsapp'), { http: 422 });
    const msg = await sock.sendMessage(found.jid, { text });
    rememberSent(msg, text);
    await new Promise((r) => setTimeout(r, SEND_GAP_MS));
  });
  queue = job.catch(() => {});
  return job;
}

function authorized(req) {
  const given = Buffer.from(String(req.headers['x-api-key'] || ''));
  const want = Buffer.from(KEY);
  return given.length === want.length && timingSafeEqual(given, want);
}

function reply(res, code, body) {
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (c) => {
      data += c;
      if (data.length > 10_000) reject(new Error('too_large'));
    });
    req.on('end', () => {
      try {
        resolve(data ? JSON.parse(data) : {});
      } catch {
        reject(new Error('bad_json'));
      }
    });
  });
}

http
  .createServer(async (req, res) => {
    if (!authorized(req)) return reply(res, 401, { error: 'unauthorized' });
    try {
      if (req.method === 'GET' && req.url === '/status') return reply(res, 200, state);
      if (req.method === 'POST' && req.url === '/send') {
        const { to, text } = await readJson(req);
        if (!to || !text) return reply(res, 400, { error: 'to_and_text_required' });
        await send(to, String(text).slice(0, 1000));
        return reply(res, 200, { ok: true });
      }
      if (req.method === 'POST' && req.url === '/pair') {
        const { phone } = await readJson(req);
        const digits = String(phone || '').replace(/\D/g, '');
        if (!digits) return reply(res, 400, { error: 'phone_required' });
        if (state.status === 'open' || sock?.authState?.creds?.registered) return reply(res, 409, { error: 'already_linked' });
        if (state.status !== 'qr') return reply(res, 503, { error: 'not_ready' });
        const code = await sock.requestPairingCode(digits);
        return reply(res, 200, { code });
      }
      if (req.method === 'POST' && req.url === '/logout') {
        try {
          await sock?.logout();
        } catch {
          wipeAuth();
          restartTimer = setTimeout(() => start().catch((e) => logger.error(e)), 1000);
        }
        return reply(res, 200, { ok: true });
      }
      return reply(res, 404, { error: 'not_found' });
    } catch (e) {
      const id = randomUUID().slice(0, 8);
      if (!e.http) logger.error({ err: e, id }, 'request failed');
      return reply(res, e.http || 500, { error: e.http ? e.message : `server_error_${id}` });
    }
  })
  .listen(PORT, '127.0.0.1', () => logger.warn(`listening on 127.0.0.1:${PORT}`));

start().catch((e) => {
  logger.error(e);
  process.exit(1);
});
