import { requireAdmin } from '../_lib/auth.js';
import { getStats, getStorageHealth } from '../_lib/analytics-store.js';
import { methodNotAllowed, sendJson } from '../_lib/http.js';

export default async function handler(req, res) {
  if (req.method !== 'GET') {
    methodNotAllowed(res, ['GET']);
    return;
  }

  if (!requireAdmin(req, res)) return;

  try {
    const [stats, storage] = await Promise.all([getStats(), getStorageHealth()]);
    sendJson(res, 200, {
      ...stats,
      status: {
        website: 'Online',
        api: 'Online',
        storage,
        checkedAt: new Date().toISOString(),
      },
    });
  } catch (err) {
    sendJson(res, 500, {
      error: 'Unable to load analytics.',
      status: {
        website: 'Online',
        api: 'Degraded',
        storage: {
          healthy: false,
          message: err.message,
        },
        checkedAt: new Date().toISOString(),
      },
    });
  }
}

