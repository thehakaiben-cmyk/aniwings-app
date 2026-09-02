import { useCallback, useEffect, useMemo, useState } from 'react';

const numberFormatter = new Intl.NumberFormat('en');

function formatNumber(value) {
  return numberFormatter.format(Number(value || 0));
}

function formatDate(value) {
  if (!value) return 'Not recorded yet';

  try {
    return new Intl.DateTimeFormat('en', {
      dateStyle: 'medium',
      timeStyle: 'short',
    }).format(new Date(value));
  } catch {
    return value;
  }
}

function statusLabel(status) {
  if (!status) return 'Checking';
  if (status.api === 'Online' && status.storage?.healthy !== false) return 'Online';
  return 'Degraded';
}

function variantLabel(variant) {
  const labels = {
    universal: 'Universal APK',
    arm64: 'ARM64 v8a APK',
    armv7: 'armeabi-v7a APK',
  };

  return labels[variant] || variant;
}

export default function Admin() {
  const [checkingSession, setCheckingSession] = useState(true);
  const [authenticated, setAuthenticated] = useState(false);
  const [loadingStats, setLoadingStats] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [stats, setStats] = useState(null);

  const loadStats = useCallback(async () => {
    setLoadingStats(true);
    setError('');

    try {
      const response = await fetch('/api/admin/stats', {
        credentials: 'same-origin',
        cache: 'no-store',
      });
      const data = await response.json().catch(() => ({}));

      if (response.status === 401) {
        setAuthenticated(false);
        setStats(null);
        return;
      }

      if (!response.ok) throw new Error(data.error || 'Unable to load admin stats.');
      setStats(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoadingStats(false);
    }
  }, []);

  useEffect(() => {
    let mounted = true;

    async function checkSession() {
      try {
        const response = await fetch('/api/admin/session', {
          credentials: 'same-origin',
          cache: 'no-store',
        });
        const data = await response.json().catch(() => ({}));

        if (!mounted) return;
        setAuthenticated(Boolean(data.authenticated));
        if (data.authenticated) loadStats();
      } catch {
        if (mounted) setAuthenticated(false);
      } finally {
        if (mounted) setCheckingSession(false);
      }
    }

    checkSession();

    return () => {
      mounted = false;
    };
  }, [loadStats]);

  useEffect(() => {
    document.title = 'AniWings Admin';
  }, []);

  const metrics = useMemo(() => {
    const totals = stats?.totals || {};
    return [
      {
        label: 'App Downloads',
        value: formatNumber(totals.downloads),
        icon: 'ri-download-cloud-2-line',
        detail: `Last download: ${formatDate(stats?.lastDownloadAt)}`,
      },
      {
        label: 'Website Visits',
        value: formatNumber(totals.visits),
        icon: 'ri-eye-line',
        detail: `${formatNumber(totals.uniqueVisitors)} unique browser IDs`,
      },
      {
        label: 'Countries',
        value: formatNumber(stats?.countries?.length),
        icon: 'ri-earth-line',
        detail: 'Visits and downloads by detected country',
      },
      {
        label: 'Website Status',
        value: statusLabel(stats?.status),
        icon: 'ri-pulse-line',
        detail: `Checked: ${formatDate(stats?.status?.checkedAt)}`,
      },
    ];
  }, [stats]);

  const handleSubmit = async (event) => {
    event.preventDefault();
    setSubmitting(true);
    setError('');

    try {
      const response = await fetch('/api/admin/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'same-origin',
        body: JSON.stringify({ username, password }),
      });
      const data = await response.json().catch(() => ({}));

      if (!response.ok) throw new Error(data.error || 'Invalid username or password.');

      setPassword('');
      setAuthenticated(true);
      await loadStats();
    } catch (err) {
      setError(err.message);
    } finally {
      setSubmitting(false);
    }
  };

  const handleLogout = async () => {
    await fetch('/api/admin/logout', {
      method: 'POST',
      credentials: 'same-origin',
    }).catch(() => {});

    setAuthenticated(false);
    setStats(null);
    setPassword('');
  };

  if (checkingSession) {
    return (
      <main className="admin-page admin-page--centered">
        <div className="admin-loader">
          <i className="ri-loader-4-line"></i>
          <span>Checking admin session</span>
        </div>
      </main>
    );
  }

  if (!authenticated) {
    return (
      <main className="admin-page admin-page--centered">
        <section className="admin-login-panel" aria-labelledby="admin-login-title">
          <div className="admin-brand">
            <img src="/images/logo.png" alt="AniWings" />
            <div>
              <span>AniWings</span>
              <strong>Admin</strong>
            </div>
          </div>

          <h1 id="admin-login-title">Admin Sign In</h1>
          <p>Enter the admin credentials to view private site and download analytics.</p>

          <form className="admin-login-form" onSubmit={handleSubmit}>
            <label>
              <span>Username</span>
              <input
                autoComplete="username"
                onChange={(event) => setUsername(event.target.value)}
                required
                type="text"
                value={username}
              />
            </label>

            <label>
              <span>Password</span>
              <input
                autoComplete="current-password"
                onChange={(event) => setPassword(event.target.value)}
                required
                type="password"
                value={password}
              />
            </label>

            {error && (
              <div className="admin-error" role="alert">
                <i className="ri-error-warning-line"></i>
                <span>{error}</span>
              </div>
            )}

            <button className="btn btn-lg btn-pre admin-submit" disabled={submitting} type="submit">
              <i className={submitting ? 'ri-loader-4-line' : 'ri-lock-unlock-line'}></i>
              <span>{submitting ? 'Signing in' : 'Open Admin Page'}</span>
            </button>
          </form>
        </section>
      </main>
    );
  }

  return (
    <main className="admin-page">
      <section className="admin-dashboard">
        <header className="admin-header">
          <div className="admin-title-block">
            <span className="admin-kicker">Private Dashboard</span>
            <h1>AniWings Admin</h1>
            <p>Website visits, app downloads, country activity, and live service status.</p>
          </div>

          <div className="admin-actions">
            <button className="btn btn-secondary" disabled={loadingStats} onClick={loadStats} type="button">
              <i className={loadingStats ? 'ri-loader-4-line' : 'ri-refresh-line'}></i>
              <span>{loadingStats ? 'Refreshing' : 'Refresh'}</span>
            </button>
            <button className="btn btn-outline-light" onClick={handleLogout} type="button">
              <i className="ri-logout-box-r-line"></i>
              <span>Logout</span>
            </button>
          </div>
        </header>

        {error && (
          <div className="admin-error admin-dashboard-error" role="alert">
            <i className="ri-error-warning-line"></i>
            <span>{error}</span>
          </div>
        )}

        <div className="admin-metrics">
          {metrics.map((metric) => (
            <article className="admin-metric" key={metric.label}>
              <div className="admin-metric-icon">
                <i className={metric.icon}></i>
              </div>
              <span>{metric.label}</span>
              <strong>{metric.value}</strong>
              <small>{metric.detail}</small>
            </article>
          ))}
        </div>

        <div className="admin-grid">
          <section className="admin-panel admin-panel--wide">
            <div className="admin-panel-header">
              <h2>Country Activity</h2>
              <span>{formatNumber(stats?.countries?.length)} countries</span>
            </div>

            <div className="admin-table-wrap">
              <table className="admin-table">
                <thead>
                  <tr>
                    <th>Country</th>
                    <th>Visits</th>
                    <th>Downloads</th>
                  </tr>
                </thead>
                <tbody>
                  {stats?.countries?.length ? stats.countries.map((country) => (
                    <tr key={country.code}>
                      <td>
                        <span className="admin-country-code">{country.code}</span>
                        {country.name}
                      </td>
                      <td>{formatNumber(country.visits)}</td>
                      <td>{formatNumber(country.downloads)}</td>
                    </tr>
                  )) : (
                    <tr>
                      <td colSpan="3">No country data recorded yet.</td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </section>

          <section className="admin-panel">
            <div className="admin-panel-header">
              <h2>APK Downloads</h2>
              <span>Total {formatNumber(stats?.totals?.downloads)}</span>
            </div>

            <div className="admin-download-list">
              {stats?.downloadsByVariant?.length ? stats.downloadsByVariant.map((item) => (
                <div className="admin-download-row" key={item.variant}>
                  <span>{variantLabel(item.variant)}</span>
                  <strong>{formatNumber(item.count)}</strong>
                </div>
              )) : (
                <p className="admin-empty">No downloads recorded yet.</p>
              )}
            </div>
          </section>

          <section className="admin-panel">
            <div className="admin-panel-header">
              <h2>Website Status</h2>
              <span className={`admin-status-pill ${statusLabel(stats?.status).toLowerCase()}`}>
                {statusLabel(stats?.status)}
              </span>
            </div>

            <dl className="admin-status-list">
              <div>
                <dt>API</dt>
                <dd>{stats?.status?.api || 'Checking'}</dd>
              </div>
              <div>
                <dt>Storage</dt>
                <dd>{stats?.status?.storage?.mode || stats?.storage?.mode || 'Unknown'}</dd>
              </div>
              <div>
                <dt>Durable</dt>
                <dd>{stats?.status?.storage?.durable ? 'Yes' : 'No'}</dd>
              </div>
              <div>
                <dt>Last Visit</dt>
                <dd>{formatDate(stats?.lastVisitAt)}</dd>
              </div>
            </dl>
          </section>

          <section className="admin-panel admin-panel--wide">
            <div className="admin-panel-header">
              <h2>Recent Activity</h2>
              <span>Latest 25 events</span>
            </div>

            <div className="admin-table-wrap">
              <table className="admin-table">
                <thead>
                  <tr>
                    <th>Event</th>
                    <th>Country</th>
                    <th>Time</th>
                  </tr>
                </thead>
                <tbody>
                  {stats?.recentEvents?.length ? stats.recentEvents.map((event, index) => (
                    <tr key={`${event.timestamp}-${index}`}>
                      <td>
                        <i className={event.type === 'download' ? 'ri-download-cloud-2-line' : 'ri-eye-line'}></i>
                        {event.type === 'download' ? `Download: ${variantLabel(event.variant)}` : 'Website visit'}
                      </td>
                      <td>{event.countryName || event.country || 'Unknown'}</td>
                      <td>{formatDate(event.timestamp)}</td>
                    </tr>
                  )) : (
                    <tr>
                      <td colSpan="3">No recent activity recorded yet.</td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </section>
    </main>
  );
}

