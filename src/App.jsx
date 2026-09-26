import { useState, useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import Navbar from './components/Navbar';
import Footer from './components/Footer';
import Home from './pages/Home';

const DEFAULT_UPDATE_DATA = {
  version: '1.2.1',
  url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.1/AniWings-universal.apk',
  universalUrl: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.1/AniWings-universal.apk',
  arm64Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.1/AniWings-arm64-v8a.apk',
  armv7Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.2.1/AniWings-armeabi-v7a.apk',
  mandatory: true,
  releaseNotes: 'AniWings v1.2.1 Update - Completely reworked user interface with modern design updates, resolved streaming server and buffer issues with 2 brand new servers added, opened modular extension support for everyone, introduced profile customization, integrated in-app TV QR code login linking, added tracker provider customization (Kitsu, AniDB, MyAnimeList, and AniList) handed over directly to users, added Help & Guidance page and direct Email Support, introduced an optional Support page to maintain the app (optional ad viewing - not mandatory), and implemented optimal bug fixes in our open-source architecture.',
  minVersion: '1.2.1',
  fileSize: '156.8 MB',
  updatedAt: '2026-09-26',
  appName: 'AniWings',
  tv: {
    version: '1.2.3',
    url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.3/aniwings-tv-v1.2.3-universal.apk',
    universalUrl: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.3/aniwings-tv-v1.2.3-universal.apk',
    arm64Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.3/aniwings-tv-v1.2.3-arm64-v8a.apk',
    armv7Url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/tv-v1.2.3/aniwings-tv-v1.2.3-armeabi-v7a.apk',
    mandatory: true,
    releaseNotes: 'AniWings TV v1.2.3 Update - Reworked and optimized TV user interface with fresh design updates, added Fire TV and NVIDIA Shield TV support with HDR and fixed color correction, resolved streaming server and playback buffering issues, added seamless TV login via the AniWings mobile app using QR code scanning, and applied general performance bug fixes.',
    minVersion: '1.2.3',
    fileSize: '67.1 MB',
    updatedAt: '2026-09-26',
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
