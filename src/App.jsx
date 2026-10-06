import { useState, useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import Navbar from './components/Navbar';
import Footer from './components/Footer';
import Home from './pages/Home';

const DEFAULT_UPDATE_DATA = {
  version: '1.2.5',
  url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.5/AniWings-universal.apk',
  universalUrl: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.5/AniWings-universal.apk',
  arm64Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.5/AniWings-arm64-v8a.apk',
  armv7Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.5/AniWings-armeabi-v7a.apk',
  mandatory: true,
  releaseNotes: 'AniWings v1.2.5 Update - Fixed bugs, added intro/outro skip, swipe gesture for volume/brightness, filler and non filler filtration, leaderboard feature included.',
  minVersion: '1.2.5',
  fileSize: '176.1 MB',
  updatedAt: '2026-10-07',
  appName: 'AniWings',
  tv: {
    version: '1.2.5',
    url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.5/aniwings-tv-v1.2.5-universal.apk',
    universalUrl: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.5/aniwings-tv-v1.2.5-universal.apk',
    arm64Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.5/aniwings-tv-v1.2.5-arm64-v8a.apk',
    armv7Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.5/aniwings-tv-v1.2.5-armeabi-v7a.apk',
    mandatory: true,
    releaseNotes: 'AniWings TV v1.2.5 Update - Fixed bugs, email login support.',
    minVersion: '1.2.5',
    fileSize: '69.8 MB',
    updatedAt: '2026-10-07',
    appName: 'AniWings TV'
  },
  desktop: {
    version: '1.2.5',
    url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.5/aniwings-desktop-windows-v1.2.5.exe',
    windowsUrl: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.5/aniwings-desktop-windows-v1.2.5.exe',
    linuxUrl: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.5/aniwings-desktop-linux-v1.2.5.AppImage',
    windowsFileName: 'aniwings-desktop-windows-v1.2.5.exe',
    linuxFileName: 'aniwings-desktop-linux-v1.2.5.AppImage',
    mandatory: true,
    releaseNotes: 'AniWings Desktop v1.2.5 Release - Brand new app launched for desktop with features included from mobile version.',
    minVersion: '1.2.5',
    fileSize: '15.3 MB',
    updatedAt: '2026-10-07',
    appName: 'AniWings Desktop'
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
