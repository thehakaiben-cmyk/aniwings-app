import { useState, useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import Navbar from './components/Navbar';
import Footer from './components/Footer';
import Home from './pages/Home';

const DEFAULT_UPDATE_DATA = {
  version: '1.2.0',
  url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.0/AniWings-universal.apk',
  universalUrl: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.0/AniWings-universal.apk',
  arm64Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.0/AniWings-arm64-v8a.apk',
  armv7Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.0/AniWings-armeabi-v7a.apk',
  mandatory: true,
  releaseNotes: 'AniWings v1.2.0 Update - Added anime download support for offline viewing, custom DNS access configuration, new Indian language multi-audio servers, modular extension support (Beta), general bug fixes, and performance optimizations.',
  minVersion: '1.2.0',
  fileSize: '120.3 MB',
  updatedAt: '2026-09-20',
  appName: 'AniWings',
  tv: {
    version: '1.2.2',
    url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.2/aniwings-tv-v1.2.2-universal.apk',
    universalUrl: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.2/aniwings-tv-v1.2.2-universal.apk',
    arm64Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.2/aniwings-tv-v1.2.2-arm64-v8a.apk',
    armv7Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.2/aniwings-tv-v1.2.2-armeabi-v7a.apk',
    mandatory: true,
    releaseNotes: 'AniWings TV v1.2.2 Update - Improved TV interface, expanded support for Fire TV and NVIDIA Shield TV, resolved streaming server issues, applied playback optimizations, and fixed bugs.',
    minVersion: '1.2.2',
    fileSize: '66.9 MB',
    updatedAt: '2026-09-20',
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
