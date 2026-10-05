import { useState, useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import Navbar from './components/Navbar';
import Footer from './components/Footer';
import Home from './pages/Home';

const DEFAULT_UPDATE_DATA = {
  version: '1.2.4',
  url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.4/AniWings-universal.apk',
  universalUrl: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.4/AniWings-universal.apk',
  arm64Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.4/AniWings-arm64-v8a.apk',
  armv7Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.4/AniWings-armeabi-v7a.apk',
  mandatory: true,
  releaseNotes: 'AniWings v1.2.4 Update - Bug fixes, provider switch up properly and some design changes.',
  minVersion: '1.2.4',
  fileSize: '173.0 MB',
  updatedAt: '2026-10-04',
  appName: 'AniWings',
  tv: {
    version: '1.2.4',
    url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.4/aniwings-tv-v1.2.4-universal.apk',
    universalUrl: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.4/aniwings-tv-v1.2.4-universal.apk',
    arm64Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.4/aniwings-tv-v1.2.4-arm64-v8a.apk',
    armv7Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.4/aniwings-tv-v1.2.4-armeabi-v7a.apk',
    mandatory: true,
    releaseNotes: 'AniWings TV v1.2.4 Update - Completely refined TV user interface, added voice search support, and fixed bugs.',
    minVersion: '1.2.4',
    fileSize: '69.1 MB',
    updatedAt: '2026-10-03',
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
    releaseNotes: 'AniWings Desktop v1.2.5 Update - New version of AniWings on Desktop.',
    minVersion: '1.2.5',
    fileSize: '85.0 MB',
    updatedAt: '2026-10-05',
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
