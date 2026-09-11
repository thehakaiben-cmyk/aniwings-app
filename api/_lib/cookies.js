export const VISITOR_COOKIE = 'aniwings_visitor_id';


export function parseCookies(req) {
  const header = req.headers?.cookie || '';

  return header.split(';').reduce((cookies, part) => {
    const [rawName, ...rawValue] = part.trim().split('=');
    if (!rawName) return cookies;

    cookies[rawName] = decodeURIComponent(rawValue.join('=') || '');
    return cookies;
  }, {});
}

export function isSecureRequest(req) {
  const proto = req.headers?.['x-forwarded-proto'];
  return proto === 'https' || process.env.VERCEL === '1' || process.env.NODE_ENV === 'production';
}

export function serializeCookie(name, value, options = {}) {
  const parts = [`${name}=${encodeURIComponent(value)}`];

  if (options.maxAge !== undefined) parts.push(`Max-Age=${options.maxAge}`);
  if (options.path) parts.push(`Path=${options.path}`);
  if (options.httpOnly) parts.push('HttpOnly');
  if (options.secure) parts.push('Secure');
  if (options.sameSite) parts.push(`SameSite=${options.sameSite}`);

  return parts.join('; ');
}

export function appendSetCookie(res, cookie) {
  const existing = res.getHeader('Set-Cookie');

  if (!existing) {
    res.setHeader('Set-Cookie', cookie);
    return;
  }

  const cookies = Array.isArray(existing) ? existing : [existing];
  res.setHeader('Set-Cookie', [...cookies, cookie]);
}

