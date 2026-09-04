import fs from 'node:fs/promises';
import path from 'node:path';
import { getCountryName } from './geo.js';

const REDIS_REST_URL = process.env.KV_REST_API_URL || process.env.UPSTASH_REDIS_REST_URL;
const REDIS_REST_TOKEN = process.env.KV_REST_API_TOKEN || process.env.UPSTASH_REDIS_REST_TOKEN;
const USE_REDIS = Boolean(REDIS_REST_URL && REDIS_REST_TOKEN);

const COUNTERS_KEY = 'aniwings:stats:counters';
const COUNTRIES_KEY = 'aniwings:stats:countries';
const DOWNLOAD_COUNTRIES_KEY = 'aniwings:stats:download-countries';
const DOWNLOAD_VARIANTS_KEY = 'aniwings:stats:download-variants';
const VISITORS_KEY = 'aniwings:stats:visitors';
const EVENTS_KEY = 'aniwings:stats:events';

const localStatsPath = process.env.ANIWINGS_STATS_FILE ||
  (process.env.VERCEL ? '/tmp/aniwings-stats.json' : path.join(process.cwd(), '.data', 'aniwings-stats.json'));

function emptyStats() {
  return {
    totals: {
      visits: 0,
      downloads: 0,
      uniqueVisitors: 0,
    },
    countries: {},
    downloadCountries: {},
    downloadsByVariant: {},
    visitorIds: [],
    recentEvents: [],
    lastVisitAt: null,
    lastDownloadAt: null,
    createdAt: new Date().toISOString(),
  };
}

function toNumber(value) {
  const number = Number(value || 0);
  return Number.isFinite(number) ? number : 0;
}

function hashArrayToObject(value) {
  if (!value) return {};
  if (!Array.isArray(value)) return value;

  const object = {};
  for (let i = 0; i < value.length; i += 2) {
    object[value[i]] = value[i + 1];
  }
  return object;
}

function sortedEntries(object) {
  return Object.entries(object || {})
    .map(([key, value]) => ({ key, count: toNumber(value) }))
    .filter((entry) => entry.count > 0)
    .sort((a, b) => b.count - a.count || a.key.localeCompare(b.key));
}

function normalizeStats(stats, storageMode) {
  const visitsByCountry = stats.countries || {};
  const downloadsByCountry = stats.downloadCountries || {};
  const countryCodes = Array.from(new Set([
    ...Object.keys(visitsByCountry),
    ...Object.keys(downloadsByCountry),
  ]));

  const countries = countryCodes
    .map((code) => ({
      code,
      name: getCountryName(code),
      visits: toNumber(visitsByCountry[code]),
      downloads: toNumber(downloadsByCountry[code]),
    }))
    .sort((a, b) => (b.visits + b.downloads) - (a.visits + a.downloads) || a.name.localeCompare(b.name));

  return {
    totals: {
      visits: toNumber(stats.totals?.visits),
      downloads: toNumber(stats.totals?.downloads),
      uniqueVisitors: toNumber(stats.totals?.uniqueVisitors || stats.visitorIds?.length),
    },
    countries,
    downloadsByVariant: sortedEntries(stats.downloadsByVariant).map((entry) => ({
      variant: entry.key,
      count: entry.count,
    })),
    recentEvents: (stats.recentEvents || []).slice(0, 25),
    lastVisitAt: stats.lastVisitAt || null,
    lastDownloadAt: stats.lastDownloadAt || null,
    storage: {
      mode: storageMode,
      durable: storageMode === 'upstash-redis',
    },
  };
}

async function redisRequest(command, endpoint = '') {
  const response = await fetch(`${REDIS_REST_URL}${endpoint}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${REDIS_REST_TOKEN}`,
      'Content-Type': 'application/json',
      'User-Agent': 'aniwings-analytics',
    },
    body: JSON.stringify(command),
  });

  const data = await response.json().catch(() => ({}));

  if (!response.ok || data.error) {
    throw new Error(data.error || `Redis request failed with ${response.status}`);
  }

  return data.result ?? data;
}

async function redisPipeline(commands) {
  const response = await fetch(`${REDIS_REST_URL}/pipeline`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${REDIS_REST_TOKEN}`,
      'Content-Type': 'application/json',
      'User-Agent': 'aniwings-analytics',
    },
    body: JSON.stringify(commands),
  });

  const data = await response.json().catch(() => null);

  if (!response.ok || !Array.isArray(data)) {
    throw new Error(`Redis pipeline failed with ${response.status}`);
  }

  const firstError = data.find((item) => item.error);
  if (firstError) throw new Error(firstError.error);

  return data.map((item) => item.result);
}

async function readLocalStats() {
  try {
    const raw = await fs.readFile(localStatsPath, 'utf8');
    return { ...emptyStats(), ...JSON.parse(raw) };
  } catch (err) {
    if (err.code === 'ENOENT') return emptyStats();
    throw err;
  }
}

async function writeLocalStats(stats) {
  await fs.mkdir(path.dirname(localStatsPath), { recursive: true });
  await fs.writeFile(localStatsPath, JSON.stringify(stats, null, 2));
}

function pushRecentEvent(stats, event) {
  stats.recentEvents = [event, ...(stats.recentEvents || [])].slice(0, 50);
}

export async function recordVisit({ country, visitorId, timezone }) {
  const timestamp = new Date().toISOString();
  const countryCode = country || 'Unknown';
  const event = {
    type: 'visit',
    country: countryCode,
    countryName: getCountryName(countryCode),
    timezone: timezone || null,
    timestamp,
  };

  if (USE_REDIS) {
    const isNewVisitor = visitorId
      ? await redisRequest(['SADD', VISITORS_KEY, visitorId])
      : 0;

    const commands = [
      ['HINCRBY', COUNTERS_KEY, 'visits', 1],
      ['HINCRBY', COUNTRIES_KEY, countryCode, 1],
      ['HSET', COUNTERS_KEY, 'lastVisitAt', timestamp],
      ['LPUSH', EVENTS_KEY, JSON.stringify(event)],
      ['LTRIM', EVENTS_KEY, 0, 49],
    ];

    if (isNewVisitor === 1) {
      commands.unshift(['HINCRBY', COUNTERS_KEY, 'uniqueVisitors', 1]);
    }

    await redisPipeline(commands);
    return;
  }

  const stats = await readLocalStats();
  const visitorIds = new Set(stats.visitorIds || []);

  stats.totals.visits += 1;
  stats.countries[countryCode] = toNumber(stats.countries[countryCode]) + 1;
  stats.lastVisitAt = timestamp;

  if (visitorId && !visitorIds.has(visitorId)) {
    visitorIds.add(visitorId);
    stats.visitorIds = Array.from(visitorIds);
    stats.totals.uniqueVisitors = visitorIds.size;
  }

  pushRecentEvent(stats, event);
  await writeLocalStats(stats);
}

export async function recordDownload({ country, variant, visitorId }) {
  const timestamp = new Date().toISOString();
  const countryCode = country || 'Unknown';
  const cleanVariant = variant || 'apk';
  const event = {
    type: 'download',
    country: countryCode,
    countryName: getCountryName(countryCode),
    variant: cleanVariant,
    timestamp,
  };

  if (USE_REDIS) {
    const isNewVisitor = visitorId
      ? await redisRequest(['SADD', VISITORS_KEY, visitorId])
      : 0;

    const commands = [
      ['HINCRBY', COUNTERS_KEY, 'downloads', 1],
      ['HINCRBY', DOWNLOAD_COUNTRIES_KEY, countryCode, 1],
      ['HINCRBY', DOWNLOAD_VARIANTS_KEY, cleanVariant, 1],
      ['HSET', COUNTERS_KEY, 'lastDownloadAt', timestamp],
      ['LPUSH', EVENTS_KEY, JSON.stringify(event)],
      ['LTRIM', EVENTS_KEY, 0, 49],
    ];

    if (isNewVisitor === 1) {
      commands.unshift(['HINCRBY', COUNTERS_KEY, 'uniqueVisitors', 1]);
    }

    await redisPipeline(commands);
    return;
  }

  const stats = await readLocalStats();
  const visitorIds = new Set(stats.visitorIds || []);

  stats.totals.downloads += 1;
  stats.downloadCountries[countryCode] = toNumber(stats.downloadCountries[countryCode]) + 1;
  stats.downloadsByVariant[cleanVariant] = toNumber(stats.downloadsByVariant[cleanVariant]) + 1;
  stats.lastDownloadAt = timestamp;

  if (visitorId && !visitorIds.has(visitorId)) {
    visitorIds.add(visitorId);
    stats.visitorIds = Array.from(visitorIds);
    stats.totals.uniqueVisitors = visitorIds.size;
  }

  pushRecentEvent(stats, event);
  await writeLocalStats(stats);
}

export async function getStats() {
  if (USE_REDIS) {
    const [
      counters,
      countries,
      downloadCountries,
      downloadsByVariant,
      recentEvents,
    ] = await redisPipeline([
      ['HGETALL', COUNTERS_KEY],
      ['HGETALL', COUNTRIES_KEY],
      ['HGETALL', DOWNLOAD_COUNTRIES_KEY],
      ['HGETALL', DOWNLOAD_VARIANTS_KEY],
      ['LRANGE', EVENTS_KEY, 0, 24],
    ]);

    const counterObject = hashArrayToObject(counters);
    const stats = {
      totals: {
        visits: counterObject.visits,
        downloads: counterObject.downloads,
        uniqueVisitors: counterObject.uniqueVisitors,
      },
      countries: hashArrayToObject(countries),
      downloadCountries: hashArrayToObject(downloadCountries),
      downloadsByVariant: hashArrayToObject(downloadsByVariant),
      recentEvents: (recentEvents || []).map((event) => {
        try {
          return JSON.parse(event);
        } catch {
          return null;
        }
      }).filter(Boolean),
      lastVisitAt: counterObject.lastVisitAt,
      lastDownloadAt: counterObject.lastDownloadAt,
    };

    return normalizeStats(stats, 'upstash-redis');
  }

  const stats = await readLocalStats();
  return normalizeStats(stats, process.env.VERCEL ? 'temporary-file' : 'local-file');
}

export async function getStorageHealth() {
  if (USE_REDIS) {
    await redisRequest(['PING']);
    return {
      mode: 'upstash-redis',
      durable: true,
      healthy: true,
    };
  }

  return {
    mode: process.env.VERCEL ? 'temporary-file' : 'local-file',
    durable: false,
    healthy: true,
  };
}

