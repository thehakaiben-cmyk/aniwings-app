import crypto from 'node:crypto';
import { appendSetCookie, isSecureRequest, parseCookies, serializeCookie, VISITOR_COOKIE } from '../_lib/cookies.js';
import { getCountryCode } from '../_lib/geo.js';
import { methodNotAllowed, readJsonBody, sendJson } from '../_lib/http.js';
import { recordVisit } from '../_lib/analytics-store.js';

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    methodNotAllowed(res, ['POST']);
    return;
  }

  const cookies = parseCookies(req);
  const visitorId = cookies[VISITOR_COOKIE] || crypto.randomUUID();

  if (!cookies[VISITOR_COOKIE]) {
    appendSetCookie(res, serializeCookie(VISITOR_COOKIE, visitorId, {
      httpOnly: true,
      secure: isSecureRequest(req),
      sameSite: 'Lax',
      path: '/',
      maxAge: 60 * 60 * 24 * 365,
    }));
  }

  let body = {};
  try {
    body = await readJsonBody(req);
  } catch {
    body = {};
  }

  try {
    await recordVisit({
      country: getCountryCode(req),
      visitorId,
      timezone: typeof body.timezone === 'string' ? body.timezone.slice(0, 80) : null,
    });
    sendJson(res, 200, { ok: true });
  } catch {
    sendJson(res, 202, { ok: false });
  }
}

