import crypto from 'node:crypto';
import { ADMIN_SESSION_COOKIE, isSecureRequest, parseCookies, serializeCookie } from './cookies.js';

const SESSION_TTL_SECONDS = 60 * 60 * 8;
const DEFAULT_ADMIN_USERNAME = 'HakaiBen';

function base64url(input) {
  return Buffer.from(input).toString('base64url');
}

function sign(value) {
  const secret = process.env.ADMIN_SESSION_SECRET || process.env.ADMIN_PASSWORD;
  if (!secret) throw new Error('Admin session secret is not configured');

  return crypto.createHmac('sha256', secret).update(value).digest('base64url');
}

function timingSafeEqualString(a = '', b = '') {
  const aBuffer = Buffer.from(String(a));
  const bBuffer = Buffer.from(String(b));

  if (aBuffer.length !== bBuffer.length) {
    crypto.timingSafeEqual(aBuffer, aBuffer);
    return false;
  }

  return crypto.timingSafeEqual(aBuffer, bBuffer);
}

export function getAdminConfig() {
  return {
    username: process.env.ADMIN_USERNAME || DEFAULT_ADMIN_USERNAME,
    password: process.env.ADMIN_PASSWORD || '',
    configured: Boolean(process.env.ADMIN_PASSWORD),
  };
}

export function validateAdminCredentials(username, password) {
  const config = getAdminConfig();
  if (!config.configured) return { ok: false, reason: 'not_configured' };

  const usernameMatches = timingSafeEqualString(username, config.username);
  const passwordMatches = timingSafeEqualString(password, config.password);

  return { ok: usernameMatches && passwordMatches };
}

export function createAdminSessionCookie(req) {
  const now = Math.floor(Date.now() / 1000);
  const payload = base64url(JSON.stringify({
    sub: 'admin',
    iat: now,
    exp: now + SESSION_TTL_SECONDS,
  }));
  const signature = sign(payload);

  return serializeCookie(ADMIN_SESSION_COOKIE, `${payload}.${signature}`, {
    httpOnly: true,
    secure: isSecureRequest(req),
    sameSite: 'Strict',
    path: '/',
    maxAge: SESSION_TTL_SECONDS,
  });
}

export function clearAdminSessionCookie(req) {
  return serializeCookie(ADMIN_SESSION_COOKIE, '', {
    httpOnly: true,
    secure: isSecureRequest(req),
    sameSite: 'Strict',
    path: '/',
    maxAge: 0,
  });
}

export function getAdminSession(req) {
  const token = parseCookies(req)[ADMIN_SESSION_COOKIE];
  if (!token || !token.includes('.')) return null;

  const [payload, signature] = token.split('.');
  let expectedSignature;

  try {
    expectedSignature = sign(payload);
  } catch {
    return null;
  }

  if (!timingSafeEqualString(signature, expectedSignature)) return null;

  try {
    const data = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    if (data.sub !== 'admin' || !data.exp || data.exp < Math.floor(Date.now() / 1000)) return null;
    return data;
  } catch {
    return null;
  }
}

export function requireAdmin(req, res) {
  const session = getAdminSession(req);

  if (!session) {
    res.statusCode = 401;
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.end(JSON.stringify({ error: 'Unauthorized' }));
    return null;
  }

  return session;
}
