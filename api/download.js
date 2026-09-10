import crypto from 'node:crypto';
import { recordDownload } from './_lib/analytics-store.js';
import { appendSetCookie, isSecureRequest, parseCookies, serializeCookie, VISITOR_COOKIE } from './_lib/cookies.js';
import { getCountryCode } from './_lib/geo.js';
import { methodNotAllowed } from './_lib/http.js';

const FALLBACK_DOWNLOAD_URLS = {
  universal: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.1.4/AniWings-universal.apk',
  arm64: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.1.4/AniWings-arm64-v8a.apk',
  armv7: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.1.4/AniWings-armeabi-v7a.apk',
  'tv-universal': 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.1/aniwings-tv-v1.2.1-universal.apk',
  'tv-arm64': 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.1/aniwings-tv-v1.2.1-arm64-v8a.apk',
  'tv-armv7': 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.1/aniwings-tv-v1.2.1-armeabi-v7a.apk',
};

function cleanVariant(value) {
  const variant = String(value || 'universal').toLowerCase();
  return /^[a-z0-9_-]{1,40}$/.test(variant) ? variant : 'universal';
}

function isAllowedDownloadUrl(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' &&
      url.hostname === 'github.com' &&
      url.pathname.startsWith('/thehakaiben-cmyk/aniwings-app/releases/download/') &&
      url.pathname.toLowerCase().endsWith('.apk');
  } catch {
    return false;
  }
}

export default async function handler(req, res) {
  if (req.method !== 'GET') {
    methodNotAllowed(res, ['GET']);
    return;
  }

  const requestUrl = new URL(req.url, `https://${req.headers.host || 'localhost'}`);
  const variant = cleanVariant(requestUrl.searchParams.get('variant'));
  const requestedTarget = requestUrl.searchParams.get('url');
  const targetUrl = isAllowedDownloadUrl(requestedTarget)
    ? requestedTarget
    : FALLBACK_DOWNLOAD_URLS[variant] || FALLBACK_DOWNLOAD_URLS.universal;

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

  try {
    await recordDownload({
      country: getCountryCode(req),
      variant,
      visitorId,
    });
  } catch {
    // The download should still proceed if analytics storage is temporarily unavailable.
  }

  res.statusCode = 302;
  res.setHeader('Location', targetUrl);
  res.setHeader('Cache-Control', 'no-store');
  res.end();
}
