const GITHUB_RELEASES_URL = 'https://api.github.com/repos/thehakaiben-cmyk/aniwings-app/releases?per_page=100';
const CACHE_KEY = 'aniwings_download_stats_v1';
const CACHE_TTL_MS = 10 * 60 * 1000; // 10 minutes cache to avoid hitting GitHub rate limits

export const FALLBACK_STATS = {
  total: 8950,
  mobile: 8058,
  tv: 869,
  desktop: 23,
};

export async function fetchLiveDownloadStats(initialFallback = FALLBACK_STATS) {
  // 1. Try reading from cache
  if (typeof window !== 'undefined' && window.localStorage) {
    try {
      const cached = localStorage.getItem(CACHE_KEY);
      if (cached) {
        const parsed = JSON.parse(cached);
        if (parsed?.timestamp && Date.now() - parsed.timestamp < CACHE_TTL_MS) {
          if (parsed.stats && parsed.stats.total >= (initialFallback?.total || 0)) {
            return parsed.stats;
          }
        }
      }
    } catch {
      // Ignore localStorage errors
    }
  }

  // 2. Fetch fresh stats from GitHub API
  try {
    const res = await fetch(GITHUB_RELEASES_URL);
    if (!res.ok) {
      throw new Error(`GitHub API HTTP ${res.status}`);
    }
    const releases = await res.json();
    if (!Array.isArray(releases)) {
      throw new Error('Invalid releases response');
    }

    let total = 0;
    let mobile = 0;
    let tv = 0;
    let desktop = 0;

    releases.forEach((rel) => {
      (rel.assets || []).forEach((asset) => {
        const count = asset.download_count || 0;
        total += count;
        const name = (asset.name || '').toLowerCase();
        if (name.includes('tv')) {
          tv += count;
        } else if (name.includes('desktop') || name.endsWith('.exe') || name.endsWith('.zip') || name.endsWith('.appimage')) {
          desktop += count;
        } else {
          mobile += count;
        }
      });
    });

    const fallbackTotal = initialFallback?.total || FALLBACK_STATS.total;
    const stats = {
      total: Math.max(total, fallbackTotal),
      mobile: Math.max(mobile, initialFallback?.mobile || FALLBACK_STATS.mobile),
      tv: Math.max(tv, initialFallback?.tv || FALLBACK_STATS.tv),
      desktop: Math.max(desktop, initialFallback?.desktop || FALLBACK_STATS.desktop),
    };

    if (typeof window !== 'undefined' && window.localStorage) {
      try {
        localStorage.setItem(CACHE_KEY, JSON.stringify({ timestamp: Date.now(), stats }));
      } catch {
        // Ignore localStorage quota errors
      }
    }

    return stats;
  } catch (err) {
    console.warn('Could not fetch live GitHub release stats, using fallback:', err);
    return initialFallback || FALLBACK_STATS;
  }
}
