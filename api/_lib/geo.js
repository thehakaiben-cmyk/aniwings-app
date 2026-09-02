import { getHeader } from './http.js';

const displayNames = typeof Intl.DisplayNames === 'function'
  ? new Intl.DisplayNames(['en'], { type: 'region' })
  : null;

export function getCountryCode(req) {
  const rawCode = (
    getHeader(req, 'x-vercel-ip-country') ||
    getHeader(req, 'cf-ipcountry') ||
    getHeader(req, 'x-country-code') ||
    ''
  ).trim().toUpperCase();

  return /^[A-Z]{2}$/.test(rawCode) ? rawCode : 'Unknown';
}

export function getCountryName(code) {
  if (!code || code === 'Unknown') return 'Unknown';

  try {
    return displayNames?.of(code) || code;
  } catch {
    return code;
  }
}

