import { createAdminSessionCookie, validateAdminCredentials } from '../_lib/auth.js';
import { appendSetCookie } from '../_lib/cookies.js';
import { getClientIp, methodNotAllowed, readJsonBody, sendJson } from '../_lib/http.js';

const attempts = globalThis.__aniwingsLoginAttempts || new Map();
globalThis.__aniwingsLoginAttempts = attempts;

const WINDOW_MS = 15 * 60 * 1000;
const MAX_ATTEMPTS = 8;

function isLimited(ip) {
  const now = Date.now();
  const record = attempts.get(ip);

  if (!record || record.resetAt < now) {
    attempts.set(ip, { count: 0, resetAt: now + WINDOW_MS });
    return false;
  }

  return record.count >= MAX_ATTEMPTS;
}

function recordFailedAttempt(ip) {
  const now = Date.now();
  const record = attempts.get(ip) || { count: 0, resetAt: now + WINDOW_MS };
  record.count += 1;
  attempts.set(ip, record);
}

function clearAttempts(ip) {
  attempts.delete(ip);
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    methodNotAllowed(res, ['POST']);
    return;
  }

  const ip = getClientIp(req);
  if (isLimited(ip)) {
    sendJson(res, 429, { error: 'Too many login attempts. Try again later.' });
    return;
  }

  let body;
  try {
    body = await readJsonBody(req);
  } catch {
    sendJson(res, 400, { error: 'Invalid request body.' });
    return;
  }

  const username = typeof body.username === 'string' ? body.username : '';
  const password = typeof body.password === 'string' ? body.password : '';
  const result = validateAdminCredentials(username, password);

  if (result.reason === 'not_configured') {
    sendJson(res, 503, { error: 'Admin credentials are not configured on the server.' });
    return;
  }

  if (!result.ok) {
    recordFailedAttempt(ip);
    sendJson(res, 401, { error: 'Invalid username or password.' });
    return;
  }

  clearAttempts(ip);
  appendSetCookie(res, createAdminSessionCookie(req));
  sendJson(res, 200, { ok: true });
}

