import { useState, useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route, useLocation } from 'react-router-dom';
import Navbar from './components/Navbar';
import Footer from './components/Footer';
import Home from './pages/Home';
import Admin from './pages/Admin';

const DEFAULT_UPDATE_DATA = {
  version: '1.1.3',
  url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.1.3/AniWings-universal.apk',
  universalUrl: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.1.3/AniWings-universal.apk',
  arm64Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.1.3/AniWings-arm64-v8a.apk',
  armv7Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.1.3/AniWings-armeabi-v7a.apk',
  tvUrl: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.1.3/AniWings-universal.apk',
  mandatory: true,
  releaseNotes: 'AniWings v1.1.3 update - Includes Universal build (for all devices), ARM64-v8a (for high-end mobiles), and armeabi-v7a (for low-end devices). Features added extra streaming servers, UI improvements, and optimized bug fixes. Note: Android TV version is currently in development.',
  minVersion: '1.1.3',
  fileSize: '67.2 MB',
  updatedAt: '2026-08-31',
  appName: 'AniWings'
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
  const location = useLocation();
  const isAdminRoute = location.pathname.startsWith('/admin');

  return (
    <div className={`app-container${isAdminRoute ? ' admin-shell' : ''}`}>
      {!isAdminRoute && <Navbar />}
      <Routes>
        <Route
          path="/"
          element={
            <Home
              updateData={updateData}
            />
          }
        />
        <Route path="/admin/*" element={<Admin />} />
      </Routes>
      {!isAdminRoute && <Footer />}
    </div>
  );
}

export default App;

