import { useState, useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import Navbar from './components/Navbar';
import Footer from './components/Footer';
import Home from './pages/Home';

const DEFAULT_UPDATE_DATA = {
  version: '1.1.4',
  url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.1.4/AniWings-universal.apk',
  universalUrl: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.1.4/AniWings-universal.apk',
  arm64Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.1.4/AniWings-arm64-v8a.apk',
  armv7Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.1.4/AniWings-armeabi-v7a.apk',
  mandatory: true,
  releaseNotes: 'AniWings v1.1.4 Update (Mandatory) - Essential performance update featuring optimized home screen catalog loading, enhanced streaming server provider reliability, schedule synchronization fixes, video player playback smooth-seeking enhancements, and critical security and bug fixes.',
  minVersion: '1.1.4',
  fileSize: '122.4 MB',
  updatedAt: '2026-09-10',
  appName: 'AniWings',
  tv: {
    version: '1.2.1',
    url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.1/aniwings-tv-v1.2.1-universal.apk',
    universalUrl: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.1/aniwings-tv-v1.2.1-universal.apk',
    arm64Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.1/aniwings-tv-v1.2.1-arm64-v8a.apk',
    armv7Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.1/aniwings-tv-v1.2.1-armeabi-v7a.apk',
    mandatory: true,
    releaseNotes: 'AniWings TV v1.2.1 Update (Mandatory) - Dedicated Android TV performance update with enhanced remote control D-pad navigation responsiveness, optimized full-screen video playback engine, improved catalog loading speeds, audio stream sync stability, and critical bug fixes.',
    minVersion: '1.2.1',
    fileSize: '70.8 MB',
    updatedAt: '2026-09-10',
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
