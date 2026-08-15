import { useState, useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import Navbar from './components/Navbar';
import Footer from './components/Footer';
import Home from './pages/Home';

const DEFAULT_UPDATE_DATA = {
  version: '1.0.0',
  url: 'https://github.com/senthil-prabhu-sudo/aniwings-app/releases/download/v1.0.0/aniwings.apk',
  tvUrl: 'https://github.com/senthil-prabhu-sudo/aniwings-app/releases/download/v1.0.0/aniwings.apk',
  mandatory: false,
  releaseNotes: 'Initial stable release of AniWings - featuring ad-free anime streaming, dual audio toggles (SUB/DUB), custom library tracking, and high-performance playback.',
  minVersion: '1.0.0',
  fileSize: '61.8 MB',
  updatedAt: '2026-08-01',
  appName: 'AniWings'
};

function App() {
  const [updateData, setUpdateData] = useState(DEFAULT_UPDATE_DATA);

  useEffect(() => {
    let isMounted = true;

    async function loadUpdateInfo() {
      try {
        const res = await fetch('/update.json');
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

