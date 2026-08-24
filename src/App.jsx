import { useState, useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import Navbar from './components/Navbar';
import Footer from './components/Footer';
import Home from './pages/Home';

const DEFAULT_UPDATE_DATA = {
  version: '1.1.1',
  url: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.1.1/aniwings.apk',
  tvUrl: 'https://github.com/thehakaiben-cmyk/aniwings-app/releases/download/v1.1.1/aniwings.apk',
  mandatory: true,
  releaseNotes: 'AniWings v1.1.1 update - mandatory release featuring key stability improvements, bug fixes, optimized video streaming playback, and enhanced UI performance.',
  minVersion: '1.1.1',
  fileSize: '65.2 MB',
  updatedAt: '2026-08-24',
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
      <div className="app-container">
        <Navbar />
        <Routes>
          <Route
            path="/"
            element={
              <Home
                updateData={updateData}
                version={updateData.version}
              />
            }
          />
        </Routes>
        <Footer />
      </div>
    </Router>
  );
}

export default App;

