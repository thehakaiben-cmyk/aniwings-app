import { useEffect } from 'react';

let visitTracked = false;

export default function Home({ updateData }) {
  const DEFAULT_GITHUB_RELEASE_URL = 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.1.4/AniWings-universal.apk';
  const DEFAULT_TV_RELEASE_URL = 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.1/aniwings-tv-v1.2.1-universal.apk';

  const downloadUrl = updateData?.url || DEFAULT_GITHUB_RELEASE_URL;
  const universalDownloadUrl = updateData?.universalUrl || downloadUrl;
  const arm64DownloadUrl = updateData?.arm64Url || downloadUrl;
  const armv7DownloadUrl = updateData?.armv7Url || updateData?.armV7Url || downloadUrl;
  const fileSize = updateData?.fileSize || '122.4 MB';
  const updatedAt = updateData?.updatedAt || 'Recent';
  const releaseNotes = updateData?.releaseNotes;

  const tvData = updateData?.tv;
  const tvDownloadUrl = tvData?.url || updateData?.tvUrl || DEFAULT_TV_RELEASE_URL;
  const tvUniversalDownloadUrl = tvData?.universalUrl || updateData?.tvUniversalUrl || tvDownloadUrl;
  const tvArm64DownloadUrl = tvData?.arm64Url || updateData?.tvArm64Url || tvDownloadUrl;
  const tvArmv7DownloadUrl = tvData?.armv7Url || updateData?.tvArmv7Url || tvDownloadUrl;
  const tvFileSize = tvData?.fileSize || '70.8 MB';

  useEffect(() => {
    if (!visitTracked) {
      visitTracked = true;
      fetch('/api/analytics/visit', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'same-origin',
        keepalive: true,
        body: JSON.stringify({
          timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        }),
      }).catch(() => {});
    }

    // Scroll Reveal Animation via IntersectionObserver
    const observerOptions = {
      threshold: 0.1,
    };

    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('active');
        }
      });
    }, observerOptions);

    const revealElements = document.querySelectorAll('.reveal');
    revealElements.forEach((el) => observer.observe(el));

    // Cleanup observer on unmount
    return () => {
      revealElements.forEach((el) => observer.unobserve(el));
    };
  }, []);

  const handleScrollToDownload = (e) => {
    e.preventDefault();
    const downloadSection = document.getElementById('section-download');
    if (downloadSection) {
      downloadSection.scrollIntoView({ behavior: 'smooth' });
    }
  };

  const trackedDownloadUrl = (url, variant) => (
    `/api/download?variant=${encodeURIComponent(variant)}&url=${encodeURIComponent(url)}`
  );

  return (
    <div>
      {/* Hero Section */}
      <div id="heading-content">
        <div className="container">
          <div className="big-intro-content reveal active">
            <div className="bi-left">
              <div className="version-badge">
                <span className="badge-new">NEW</span>
                <span className="version-text">
                  Latest Stable Build is Live!
                </span>
              </div>
              <h1 className="heading">
                Enjoy Uninterrupted Anime on <span className="highlight">AniWings</span>
              </h1>
              <p className="description">
                Sick of constant interruptions, tedious sign-ups, and broken streaming servers? AniWings is your go-to ad-free anime client for Android. Features an advanced integrated media player, personalized library tracking, and butter-smooth playback for a top-tier viewing journey.
              </p>
              <div className="flex-btns">
                <a 
                  href="#section-download" 
                  onClick={handleScrollToDownload} 
                  className="btn btn-lg btn-pre"
                >
                  <i className="ri-download-line"></i>
                  <span>Download AniWings APK</span>
                </a>
                <a 
                  href="https://ani-wings.web.app/" 
                  target="_blank" 
                  rel="noopener noreferrer"
                  className="btn btn-lg btn-secondary website-btn"
                >
                  <i className="ri-global-line"></i>
                  <span>Visit AniWings Website</span>
                </a>
              </div>
            </div>
            <div className="bi-right">
              <div className="app-mockup-wrapper">
                <div className="mockup-screen mockup-back">
                  <img src="/images/app-login.jpg" alt="AniWings App Login Screen" />
                </div>
                <div className="mockup-screen mockup-front">
                  <img src="/images/app-home.jpg" alt="AniWings App Home Screen" />
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* What is AniWings Section */}
      <div className="section section-about reveal" id="section-about">
        <div className="container">
          <div className="content-x">
            <div className="intro">
              <img alt="AniWings details" src="/images/discover.jpg" style={{ border: '4px solid rgba(255, 255, 255, 0.05)', borderRadius: '20px' }} />
            </div>
            <div className="text">
              <h2 className="section-title" style={{ textAlign: 'left', marginBottom: '24px' }}>
                Discover <strong className="highlight">AniWings</strong>
              </h2>
              <p>
                AniWings is a completely free anime directory and player optimized for the Android ecosystem. Acting as a dedicated streaming hub, it organizes and streams thousands of titles, feature films, and the latest simulcast episodes.
              </p>
              <p>
                We focus on a bloat-free design and user privacy. You don't need to create an account, there are no subscriptions, and we don't serve intrusive banner or pop-up ads. Simply install the application, look up your favorite shows, and start your streaming session.
              </p>
              <p>
                Whether you love original Japanese voice acting with clear subtitles (SUB) or prefer localized English voice tracks (DUB), AniWings offers quick toggles so you can switch languages instantly during playback.
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Features Grid Section */}
      <div className="section section-features reveal" id="section-features">
        <div className="container">
          <h2 className="section-title">Why Stream on AniWings?</h2>
          <p className="section-desc">Crafted by community enthusiasts for dedicated fans. Here is what you can expect from the AniWings app.</p>
          
          <div className="features-list">
            <div className="fl-item">
              <div className="fl-icon">
                <i className="ri-shield-user-line"></i>
              </div>
              <div className="fl-title">Complete Privacy</div>
              <div className="fl-content">
                <p>Skip registration screens and emails. Access our massive collection of shows immediately without logging in or sharing any credentials.</p>
              </div>
            </div>

            <div className="fl-item">
              <div className="fl-icon">
                <i className="ri-translate-2"></i>
              </div>
              <div className="fl-title">Dual Audio Options</div>
              <div className="fl-content">
                <p>Break language barriers with ease. Quickly toggle between English subtitles (SUB) and localized voiceovers (DUB) directly from the stream settings.</p>
              </div>
            </div>

            <div className="fl-item">
              <div className="fl-icon">
                <i className="ri-speed-up-line"></i>
              </div>
              <div className="fl-title">Buffering-Free Engine</div>
              <div className="fl-content">
                <p>No more loading loops. AniWings integrates fast content delivery networks (CDNs) to stream your favorite episodes in HD with minimal latency.</p>
              </div>
            </div>

            <div className="fl-item">
              <div className="fl-icon">
                <i className="ri-history-line"></i>
              </div>
              <div className="fl-title">Fresh Simulcasts Everyday</div>
              <div className="fl-content">
                <p>Stay updated with ongoing seasonal anime. We refresh our catalogue daily with new episodes, syncing directly with the Japanese TV releases.</p>
              </div>
            </div>

            <div className="fl-item">
              <div className="fl-icon">
                <i className="ri-advertisement-line"></i>
              </div>
              <div className="fl-title">Zero Advertisements</div>
              <div className="fl-content">
                <p>Experience pure, uninterrupted entertainment. Our app prevents redirects, pop-ups, and annoying video ads from spoiling your watch sessions.</p>
              </div>
            </div>

            <div className="fl-item">
              <div className="fl-icon">
                <i className="ri-star-line"></i>
              </div>
              <div className="fl-title">Custom Anime Library</div>
              <div className="fl-content">
                <p>Track and curate your collection. Organize completed titles, keep tabs on your current episode count, and build watchlists for upcoming releases.</p>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Safety Section */}
      <div className="section section-about reveal">
        <div className="container">
          <div className="content-x reverse">
            <div className="intro">
              <img src="/images/secure.jpg" alt="AniWings Trust" style={{ border: '4px solid rgba(255, 255, 255, 0.05)', borderRadius: '20px' }} />
            </div>
            <div className="text">
              <h2 className="section-title" style={{ textAlign: 'left', marginBottom: '24px' }}>
                Is Using AniWings Secure?
              </h2>
              <p>
                <strong>Yes, 100%.</strong> Transparency and security are core values of AniWings. The app operates without needing root access, system permissions, or background tracking services, ensuring your personal details and device remain fully secure.
              </p>
              <p>
                We perform constant safety checks and keep the build completely free of malware, spyware, and telemetry code. We want your watch sessions to be relaxing and worry-free, without compromising on your digital privacy.
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Download Section */}
      <div className="section section-download reveal" id="section-download">
        <div className="container">
          <h2 className="section-title">Grab the Latest AniWings Release</h2>
          <p className="section-desc">Fetch the installable files below and launch your new premium anime experience.</p>
          
          <div className="dl-ul">
            {/* Android Mobile */}
            <div className="dlu-item">
              <div className="dlu-icon">
                <i className="ri-android-line"></i>
              </div>
              <h3 className="dlu-title">Android Mobile</h3>
              <p className="dlu-desc">{fileSize} • Select build for Android Mobiles & Tablets.</p>
              <div className="dlu-detail">
                <div className="dlu-btn-group">
                  <a 
                    href={trackedDownloadUrl(universalDownloadUrl, 'universal')} 
                    target="_blank"
                    rel="noopener noreferrer"
                    className="btn btn-lg btn-pre dlu-split-btn"
                  >
                    <i className="ri-download-fill"></i>
                    <span>Universal APK <span className="btn-tag">All Devices</span></span>
                  </a>
                  <a 
                    href={trackedDownloadUrl(arm64DownloadUrl, 'arm64')} 
                    target="_blank"
                    rel="noopener noreferrer"
                    className="btn btn-lg btn-secondary dlu-split-btn"
                  >
                    <i className="ri-cpu-line"></i>
                    <span>ARM64 v8a APK <span className="btn-tag">High-End</span></span>
                  </a>
                  <a 
                    href={trackedDownloadUrl(armv7DownloadUrl, 'armv7')} 
                    target="_blank"
                    rel="noopener noreferrer"
                    className="btn btn-lg btn-secondary dlu-split-btn"
                  >
                    <i className="ri-smartphone-line"></i>
                    <span>armeabi-v7a APK <span className="btn-tag">Low-End</span></span>
                  </a>
                </div>
              </div>
            </div>

            {/* Android TV */}
            <div className="dlu-item">
              <div className="dlu-icon">
                <i className="ri-tv-line"></i>
              </div>
              <h3 className="dlu-title">Android TV</h3>
              <p className="dlu-desc">{tvFileSize} • Select build for Smart TVs & TV boxes.</p>
              <div className="dlu-detail">
                <div className="dlu-btn-group">
                  <a 
                    href={trackedDownloadUrl(tvUniversalDownloadUrl, 'tv-universal')} 
                    target="_blank"
                    rel="noopener noreferrer"
                    className="btn btn-lg btn-pre dlu-split-btn"
                  >
                    <i className="ri-download-fill"></i>
                    <span>Universal TV APK <span className="btn-tag">All TVs</span></span>
                  </a>
                  <a 
                    href={trackedDownloadUrl(tvArm64DownloadUrl, 'tv-arm64')} 
                    target="_blank"
                    rel="noopener noreferrer"
                    className="btn btn-lg btn-secondary dlu-split-btn"
                  >
                    <i className="ri-cpu-line"></i>
                    <span>ARM64 v8a TV APK <span className="btn-tag">High-End</span></span>
                  </a>
                  <a 
                    href={trackedDownloadUrl(tvArmv7DownloadUrl, 'tv-armv7')} 
                    target="_blank"
                    rel="noopener noreferrer"
                    className="btn btn-lg btn-secondary dlu-split-btn"
                  >
                    <i className="ri-tv-2-line"></i>
                    <span>armeabi-v7a TV APK <span className="btn-tag">Low-End</span></span>
                  </a>
                </div>
              </div>
            </div>

            {/* iOS */}
            <div className="dlu-item coming-soon">
              <span className="coming-soon-badge">Coming Soon</span>
              <div className="dlu-icon">
                <i className="ri-apple-line"></i>
              </div>
              <h3 className="dlu-title">iOS (IPA)</h3>
              <p className="dlu-desc">Installable IPA file configured for iOS devices (iPhone and iPad).</p>
              <div className="dlu-detail">
                <div className="dlu-btn">
                  <button className="btn btn-lg btn-pre" disabled>
                    <i className="ri-download-fill"></i>
                    <span>Download for iOS</span>
                  </button>
                </div>
              </div>
            </div>
          </div>

          {/* Release Notes Cards */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))', gap: '1.5rem', marginTop: '2.5rem' }}>
            {/* Mobile Release Notes */}
            {releaseNotes && (
              <div className="release-notes-card" style={{
                padding: '1.5rem 2rem',
                borderRadius: '16px',
                background: 'rgba(255, 255, 255, 0.02)',
                border: '1px solid rgba(255, 255, 255, 0.06)',
                textAlign: 'left',
                backdropFilter: 'blur(10px)'
              }}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: '10px', marginBottom: '0.75rem' }}>
                  <h4 style={{ fontSize: '1.1rem', color: '#ffffff', display: 'flex', alignItems: 'center', gap: '8px', margin: 0 }}>
                    <i className="ri-smartphone-line" style={{ color: 'var(--accent-primary)' }}></i>
                    Mobile v{updateData?.version || '1.1.4'} Release Notes
                  </h4>
                  <span style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>
                    Released: {updatedAt}
                  </span>
                </div>
                <p style={{ color: 'var(--text-secondary)', fontSize: '0.95rem', lineHeight: '1.6', margin: 0 }}>
                  {releaseNotes}
                </p>
              </div>
            )}

            {/* TV Release Notes */}
            {tvData?.releaseNotes && (
              <div className="release-notes-card" style={{
                padding: '1.5rem 2rem',
                borderRadius: '16px',
                background: 'rgba(255, 255, 255, 0.02)',
                border: '1px solid rgba(255, 255, 255, 0.06)',
                textAlign: 'left',
                backdropFilter: 'blur(10px)'
              }}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: '10px', marginBottom: '0.75rem' }}>
                  <h4 style={{ fontSize: '1.1rem', color: '#ffffff', display: 'flex', alignItems: 'center', gap: '8px', margin: 0 }}>
                    <i className="ri-tv-line" style={{ color: '#3DDC84' }}></i>
                    Android TV v{tvData?.version || '1.2.1'} Release Notes
                  </h4>
                  <span style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>
                    Released: {tvData?.updatedAt || '2026-09-10'}
                  </span>
                </div>
                <p style={{ color: 'var(--text-secondary)', fontSize: '0.95rem', lineHeight: '1.6', margin: 0 }}>
                  {tvData.releaseNotes}
                </p>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
