import { clearAdminSessionCookie } from '../_lib/auth.js';
import { appendSetCookie } from '../_lib/cookies.js';
import { methodNotAllowed, sendJson } from '../_lib/http.js';

export default function handler(req, res) {
  if (req.method !== 'POST') {
    methodNotAllowed(res, ['POST']);
    return;
  }

  appendSetCookie(res, clearAdminSessionCookie(req));
  sendJson(res, 200, { ok: true });
}

