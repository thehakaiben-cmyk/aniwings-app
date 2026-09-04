import { useState, useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import Navbar from './components/Navbar';
import Footer from './components/Footer';
import Home from './pages/Home';

const DEFAULT_UPDATE_DATA = {
  version: '1.1.3',
  url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.1.3/AniWings-universal.apk',
  universalUrl: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.1.3/AniWings-universal.apk',
  arm64Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.1.3/AniWings-arm64-v8a.apk',
  armv7Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.1.3/AniWings-armeabi-v7a.apk',
  mandatory: true,
  releaseNotes: 'AniWings v1.1.3 update - Includes Universal build (for all devices), ARM64-v8a (for high-end mobiles), and armeabi-v7a (for low-end devices). Features added extra streaming servers, UI improvements, and optimized bug fixes.',
  minVersion: '1.1.3',
  fileSize: '67.2 MB',
  updatedAt: '2026-08-31',
  appName: 'AniWings',
  tv: {
    version: '1.2.0',
    url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.0/aniwings-tv-v1.2.0-universal.apk',
    universalUrl: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.0/aniwings-tv-v1.2.0-universal.apk',
    arm64Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.0/aniwings-tv-v1.2.0-arm64-v8a.apk',
    armv7Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.0/aniwings-tv-v1.2.0-armeabi-v7a.apk',
    mandatory: true,
    releaseNotes: 'AniWings TV v1.2.0 Release - Dedicated Android TV edition featuring full D-pad remote navigation, high-performance video player, dual audio support (SUB/DUB), zero ads, and TV dashboard UI.',
    minVersion: '1.2.0',
    fileSize: '67.4 MB',
    updatedAt: '2026-09-04',
    appName: 'AniWings TV'
  }
};

function App() {
  const [updateData, setUpdateData] = useState(DEFAULT_UPDATE_DATA);

  useEffect(() => {
    let isMounted = true;

    async function loadUpdateInfo() {
      try {
        const res = await fetch(`/update.json?t=${Date.now()}`, { cache: 'no-store' });
        if (!res.ok) throw new Error(`HTTP status: ${res.status}`);
        const data = await res.json();
        if (isMounted && data && typeof data === 'object') {
          setUpdateData((prev) => ({ ...prev, ...data }));
        }
      } catch (err) {
        console.warn('Failed to load update.json, using fallback defaults:', err);
      }
    }

    loadUpdateInfo();

    return () => {
      isMounted = false;
    };
  }, []);

  return (
    <Router>
      <AppShell updateData={updateData} />
    </Router>
  );
}

function AppShell({ updateData }) {
  return (
    <div className="app-container">
      <Navbar />
      <Routes>
        <Route
          path="/"
          element={
            <Home
              updateData={updateData}
            />
          }
        />
      </Routes>
      <Footer />
    </div>
  );
}

export default App;
