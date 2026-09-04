import { getAdminSession } from '../_lib/auth.js';
import { methodNotAllowed, sendJson } from '../_lib/http.js';

export default function handler(req, res) {
  if (req.method !== 'GET') {
    methodNotAllowed(res, ['GET']);
    return;
  }

  sendJson(res, 200, { authenticated: Boolean(getAdminSession(req)) });
}

