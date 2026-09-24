import { useState, useEffect, useRef } from 'react';
import { useSearchParams, Link } from 'react-router-dom';
import {
  auth,
  db,
  googleProvider,
  signInWithPopup,
  signInWithRedirect,
  getRedirectResult,
  signOut,
  onAuthStateChanged,
  doc,
  setDoc,
  serverTimestamp,
  onSnapshot
} from '../firebase';

export default function TvLogin() {
  const [searchParams] = useSearchParams();

  const queryCode = searchParams.get('code') || '';
  const queryMode = searchParams.get('mode') || 'signin';

  const [code, setCode] = useState(queryCode.toUpperCase().trim());
  const [mode, setMode] = useState(queryMode === 'signup' ? 'signup' : 'signin');
  const [user, setUser] = useState(null);
  const [authLoading, setAuthLoading] = useState(true);
  const [authorizing, setAuthorizing] = useState(false);
  const [authError, setAuthError] = useState(null);
  const [pairingStatus, setPairingStatus] = useState('idle'); // 'idle' | 'pending' | 'approved' | 'expired' | 'not_found'
  const [success, setSuccess] = useState(false);
  const [authorizedUser, setAuthorizedUser] = useState(null);
  const [copied, setCopied] = useState(false);

  const unsubRef = useRef(null);

  // Normalize code format helper (e.g. "8492" -> "WNG-8492", "wng-8492" -> "WNG-8492")
  const formatTvCode = (input) => {
    let clean = input.toUpperCase().replace(/[^A-Z0-9]/g, '');
    if (clean.startsWith('WNG')) {
      clean = clean.slice(3);
    }
    if (clean.length > 0) {
      return `WNG-${clean.slice(0, 6)}`;
    }
    return '';
  };

  const handleCodeInputChange = (e) => {
    const rawVal = e.target.value;
    if (!rawVal) {
      setCode('');
      return;
    }
    const formatted = formatTvCode(rawVal);
    setCode(formatted);
    setAuthError(null);
    setSuccess(false);
  };

  // Auth State Listener & Redirect Check
  useEffect(() => {
    // Check if user just returned from a Google redirect
    getRedirectResult(auth)
      .then((result) => {
        if (result?.user) {
          setUser(result.user);
        }
      })
      .catch((err) => {
        console.warn('Redirect sign-in error:', err);
        setAuthError(err.message || 'Google sign-in via redirect failed.');
      });

    const unsubscribeAuth = onAuthStateChanged(auth, (currentUser) => {
      setUser(currentUser);
      setAuthLoading(false);
    });

    return () => unsubscribeAuth();
  }, []);

  // Update code when searchParams change
  useEffect(() => {
    if (queryCode) {
      setCode(queryCode.toUpperCase().trim());
    }
    if (queryMode) {
      setMode(queryMode === 'signup' ? 'signup' : 'signin');
    }
  }, [queryCode, queryMode]);

  // Firestore Real-time Listener for TV Pairing Document
  useEffect(() => {
    if (unsubRef.current) {
      unsubRef.current();
      unsubRef.current = null;
    }

    const trimmedCode = code.trim().toUpperCase();
    // Typical format WNG-1000..9999 or WNG-XXXX
    if (trimmedCode.length >= 7 && trimmedCode.startsWith('WNG-')) {
      try {
        const docRef = doc(db, 'tv_pairings', trimmedCode);
        unsubRef.current = onSnapshot(
          docRef,
          (snap) => {
            if (snap.exists()) {
              const data = snap.data();
              const status = data?.status || 'pending';
              setPairingStatus(status);
              if (status === 'approved') {
                setSuccess(true);
                setAuthorizedUser({
                  username: data?.username || data?.user?.username || 'AniWings TV User',
                  email: data?.email || data?.user?.email || '',
                  avatarUrl: data?.avatarUrl || data?.user?.avatarUrl,
                });
              }
            } else {
              setPairingStatus('not_found');
            }
          },
          (err) => {
            console.warn('Firestore pairing listener note:', err);
            // Permissions or missing doc shouldn't block manual authorization
            setPairingStatus('idle');
          }
        );
      } catch (err) {
        console.warn('Error establishing Firestore listener:', err);
      }
    } else {
      setPairingStatus('idle');
    }

    return () => {
      if (unsubRef.current) {
        unsubRef.current();
        unsubRef.current = null;
      }
    };
  }, [code]);

  // Authorize TV logic
  const handleAuthorizeTv = async (currentUser = user) => {
    const trimmedCode = code.trim().toUpperCase();
    if (!trimmedCode || trimmedCode.length < 6) {
      setAuthError('Please enter a valid TV pairing code (e.g. WNG-8492).');
      return;
    }

    if (!currentUser) {
      setAuthError('Please sign in with Google first.');
      return;
    }

    setAuthorizing(true);
    setAuthError(null);

    try {
      const displayName =
        currentUser.displayName || currentUser.email?.split('@')[0] || 'AniWings User';
      const avatarUrl =
        currentUser.photoURL || 'assets/images/avatars/jujutsukaisen_gojo.png';

      const payload = {
        code: trimmedCode,
        status: 'approved',
        userId: currentUser.uid,
        email: currentUser.email || '',
        username: displayName,
        avatarUrl: avatarUrl,
        totalHoursWatched: 0,
        favoriteGenre: 'Action',
        authProvider: 'google',
        approvedAt: serverTimestamp(),
        device: 'AniWings Web Portal',
        user: {
          id: currentUser.uid,
          email: currentUser.email || '',
          username: displayName,
          avatarUrl: avatarUrl,
          createdAt: new Date().toISOString(),
          totalHoursWatched: 0,
          favoriteGenre: 'Action',
          authProvider: 'google',
        },
      };

      const docRef = doc(db, 'tv_pairings', trimmedCode);
      await setDoc(docRef, payload, { merge: true });

      setSuccess(true);
      setAuthorizedUser({
        username: displayName,
        email: currentUser.email || '',
        avatarUrl: avatarUrl,
      });
    } catch (err) {
      console.error('Failed to authorize TV app in Firestore:', err);
      const isPermDenied =
        err?.code === 'permission-denied' ||
        err?.message?.toLowerCase().includes('permission') ||
        err?.message?.toLowerCase().includes('insufficient');
      if (isPermDenied) {
        setAuthError(
          'Firestore Permission Denied: The tv_pairings collection permission was missing in Firestore rules. Rules have now been deployed; please click Authorize again.'
        );
      } else {
        setAuthError(
          err?.message ||
            'Unable to complete pairing in Firebase Firestore. Please check internet connection or pairing code and try again.'
        );
      }
    } finally {
      setAuthorizing(false);
    }
  };

  // Google Sign-In Handler
  const handleGoogleSignIn = async () => {
    setAuthLoading(true);
    setAuthError(null);

    try {
      const result = await signInWithPopup(auth, googleProvider);
      if (result?.user) {
        setUser(result.user);
        // If code is already entered and valid, auto-authorize TV
        const trimmedCode = code.trim().toUpperCase();
        if (trimmedCode.length >= 7 && trimmedCode.startsWith('WNG-')) {
          await handleAuthorizeTv(result.user);
        }
      }
    } catch (err) {
      console.warn('Google popup error:', err);
      if (err.code === 'auth/popup-blocked') {
        // Fallback to redirect
        try {
          await signInWithRedirect(auth, googleProvider);
          return;
        } catch {
          setAuthError('Popup was blocked by your browser. Please enable popups or try again.');
        }
      } else if (err.code === 'auth/cancelled-popup-request' || err.code === 'auth/popup-closed-by-user') {
        setAuthError('Google sign-in was cancelled. Please try again.');
      } else {
        setAuthError(err.message || 'Google sign-in failed. Please try again.');
      }
    } finally {
      setAuthLoading(false);
    }
  };

  const handleSignOut = async () => {
    try {
      await signOut(auth);
      setUser(null);
      setSuccess(false);
    } catch (err) {
      console.warn('Sign out error:', err);
    }
  };

  const handleCopyLink = () => {
    const url = window.location.href;
    navigator.clipboard.writeText(url).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  };

  const isCodeValid = code.trim().length >= 7 && code.trim().startsWith('WNG-');

  return (
    <div className="tv-auth-page">
      {/* Dynamic Background Mesh */}
      <div className="tv-auth-bg">
        <div className="tv-auth-glow-top" />
        <div className="tv-auth-glow-bottom" />
      </div>

      <div className="container tv-auth-container">
        {/* Navigation Breadcrumb */}
        <div className="tv-auth-nav">
          <Link to="/" className="tv-back-link">
            <i className="ri-arrow-left-line"></i>
            <span>Back to Home</span>
          </Link>
          <div className="tv-badge">
            <i className="ri-tv-line"></i>
            <span>AniWings TV Sync</span>
          </div>
        </div>

        <div className="tv-auth-grid">
          {/* Main Card */}
          <div className="tv-auth-card">
            {/* Header */}
            <div className="tv-card-header">
              <div className="tv-device-icon-wrap">
                <i className="ri-tv-2-fill"></i>
                <div className="tv-pulse-ring" />
              </div>
              <h1 className="tv-card-title">
                {mode === 'signup' ? 'Create Account & Link TV' : 'Link Your Android TV'}
              </h1>
              <p className="tv-card-subtitle">
                {mode === 'signup'
                  ? 'Sign up with Google on your mobile/browser to activate and personalize your TV app.'
                  : 'Quick TV login: Connect your Google account to sync watchlist, history, and preferences to your TV.'}
              </p>
            </div>

            {/* Mode Switcher Tabs */}
            <div className="tv-mode-tabs">
              <button
                type="button"
                className={`tv-mode-tab${mode === 'signin' ? ' active' : ''}`}
                onClick={() => {
                  setMode('signin');
                  setAuthError(null);
                }}
              >
                <i className="ri-login-box-line"></i>
                <span>Sign In to TV</span>
              </button>
              <button
                type="button"
                className={`tv-mode-tab${mode === 'signup' ? ' active' : ''}`}
                onClick={() => {
                  setMode('signup');
                  setAuthError(null);
                }}
              >
                <i className="ri-user-add-line"></i>
                <span>Create Account</span>
              </button>
            </div>

            {/* Error Banner */}
            {authError && (
              <div className="tv-alert tv-alert-danger">
                <i className="ri-error-warning-fill"></i>
                <div className="tv-alert-content">
                  <span>{authError}</span>
                </div>
                <button
                  className="tv-alert-close"
                  onClick={() => setAuthError(null)}
                  aria-label="Dismiss alert"
                >
                  <i className="ri-close-line"></i>
                </button>
              </div>
            )}

            {/* Success State */}
            {success ? (
              <div className="tv-success-state">
                <div className="tv-success-icon-wrap">
                  <i className="ri-checkbox-circle-fill"></i>
                </div>
                <h2 className="tv-success-title">TV Successfully Authorized!</h2>
                <p className="tv-success-msg">
                  Your TV pairing code <strong className="tv-code-highlight">{code}</strong> is now approved.
                </p>

                {authorizedUser && (
                  <div className="tv-user-pill">
                    <img
                      src={
                        authorizedUser.avatarUrl?.startsWith('http')
                          ? authorizedUser.avatarUrl
                          : '/images/logo.png'
                      }
                      alt={authorizedUser.username}
                      className="tv-user-avatar"
                      onError={(e) => {
                        e.target.src = '/images/logo.png';
                      }}
                    />
                    <div className="tv-user-info">
                      <span className="tv-user-name">{authorizedUser.username}</span>
                      <span className="tv-user-email">{authorizedUser.email}</span>
                    </div>
                    <span className="tv-connected-badge">
                      <i className="ri-link"></i> Linked
                    </span>
                  </div>
                )}

                <div className="tv-tv-ready-notice">
                  <i className="ri-remote-control-line"></i>
                  <div>
                    <strong>Look at your TV screen!</strong>
                    <p>AniWings TV has unlocked your profile and is now opening the home feed.</p>
                  </div>
                </div>

                <div className="tv-success-actions">
                  <button
                    type="button"
                    className="btn btn-pre tv-btn-full"
                    onClick={() => {
                      setSuccess(false);
                      setCode('');
                      setPairingStatus('idle');
                    }}
                  >
                    <i className="ri-add-line"></i>
                    <span>Pair Another TV</span>
                  </button>
                  <Link to="/" className="btn btn-secondary tv-btn-full">
                    <i className="ri-home-4-line"></i>
                    <span>Return to Website</span>
                  </Link>
                </div>
              </div>
            ) : (
              /* Pairing Form */
              <div className="tv-form-body">
                {/* TV Code Input Section */}
                <div className="tv-input-section">
                  <label htmlFor="tv-code-input" className="tv-input-label">
                    <span>TV Pairing Code</span>
                    {pairingStatus === 'pending' && (
                      <span className="tv-status-chip pending">
                        <span className="tv-pulse-dot" /> Waiting for TV
                      </span>
                    )}
                    {pairingStatus === 'approved' && (
                      <span className="tv-status-chip success">
                        <i className="ri-check-line"></i> Active TV Found
                      </span>
                    )}
                  </label>

                  <div className="tv-code-box">
                    <div className="tv-code-prefix">
                      <i className="ri-hashtag"></i>
                    </div>
                    <input
                      id="tv-code-input"
                      type="text"
                      className="tv-code-input"
                      placeholder="WNG-8492"
                      value={code}
                      onChange={handleCodeInputChange}
                      maxLength={10}
                      autoComplete="off"
                      spellCheck="false"
                    />
                    {code && (
                      <button
                        type="button"
                        className="tv-code-clear"
                        onClick={() => {
                          setCode('');
                          setPairingStatus('idle');
                        }}
                        title="Clear code"
                      >
                        <i className="ri-close-circle-fill"></i>
                      </button>
                    )}
                  </div>
                  <p className="tv-input-hint">
                    Enter the code shown on your TV screen (e.g. <strong>WNG-8492</strong> or just the 4 digits).
                  </p>
                </div>

                {/* Google Sign In & User State */}
                <div className="tv-auth-section">
                  {user ? (
                    <div className="tv-user-connected-card">
                      <div className="tv-user-connected-header">
                        <div className="tv-user-details-group">
                          <img
                            src={user.photoURL || '/images/logo.png'}
                            alt={user.displayName || 'Google User'}
                            className="tv-user-avatar-large"
                            onError={(e) => {
                              e.target.src = '/images/logo.png';
                            }}
                          />
                          <div className="tv-user-details-text">
                            <div className="tv-user-signed-badge">
                              <i className="ri-google-fill"></i> Signed in with Google
                            </div>
                            <span className="tv-user-title">{user.displayName || 'AniWings Fan'}</span>
                            <span className="tv-user-sub">{user.email}</span>
                          </div>
                        </div>

                        <button
                          type="button"
                          className="tv-btn-switch"
                          onClick={handleSignOut}
                          title="Sign out or switch Google account"
                        >
                          <i className="ri-logout-box-r-line"></i>
                          <span>Switch</span>
                        </button>
                      </div>

                      {/* Authorize Button */}
                      <button
                        type="button"
                        className="btn btn-pre tv-btn-authorize"
                        disabled={!isCodeValid || authorizing}
                        onClick={() => handleAuthorizeTv(user)}
                      >
                        {authorizing ? (
                          <>
                            <span className="tv-spinner" />
                            <span>Linking TV App...</span>
                          </>
                        ) : (
                          <>
                            <i className="ri-shield-check-fill"></i>
                            <span>Authorize TV with this Google Account</span>
                          </>
                        )}
                      </button>
                    </div>
                  ) : (
                    /* Not Signed In: One-Click Google Access */
                    <div className="tv-google-cta-block">
                      <button
                        type="button"
                        className="tv-google-btn"
                        onClick={handleGoogleSignIn}
                        disabled={authLoading}
                      >
                        <svg className="tv-google-svg" viewBox="0 0 24 24" width="22" height="22">
                          <path
                            fill="#4285F4"
                            d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
                          />
                          <path
                            fill="#34A853"
                            d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
                          />
                          <path
                            fill="#FBBC05"
                            d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.63z"
                          />
                          <path
                            fill="#EA4335"
                            d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z"
                          />
                        </svg>
                        <span>
                          {authLoading ? 'Signing in with Google...' : 'Continue with Google'}
                        </span>
                      </button>

                      <div className="tv-security-badge">
                        <i className="ri-shield-keyhole-line"></i>
                        <span>Official Google OAuth 2.0 • No password typing on TV remote</span>
                      </div>
                    </div>
                  )}
                </div>
              </div>
            )}
          </div>

          {/* Right Column: Visual Guide & Feature Highlights */}
          <div className="tv-auth-sidebar">
            {/* Step-by-step Guide Card */}
            <div className="tv-guide-card">
              <h3 className="tv-guide-title">
                <i className="ri-guide-line"></i> How TV Login Works
              </h3>
              <ul className="tv-guide-steps">
                <li className="tv-guide-step">
                  <div className="tv-step-number">1</div>
                  <div className="tv-step-content">
                    <strong>Launch AniWings on TV</strong>
                    <p>Open the app on your Android TV / Fire TV and select <em>Sign In</em> or <em>Create Account</em>.</p>
                  </div>
                </li>
                <li className="tv-guide-step">
                  <div className="tv-step-number">2</div>
                  <div className="tv-step-content">
                    <strong>Scan QR or Enter Code</strong>
                    <p>Scan the on-screen TV QR code with your phone camera, or enter the code above.</p>
                  </div>
                </li>
                <li className="tv-guide-step">
                  <div className="tv-step-number">3</div>
                  <div className="tv-step-content">
                    <strong>Tap Google Sign-In</strong>
                    <p>Authenticate with Google. Your TV immediately detects your approval and logs in automatically!</p>
                  </div>
                </li>
              </ul>

              <div className="tv-guide-footer">
                <button
                  type="button"
                  className="tv-copy-btn"
                  onClick={handleCopyLink}
                >
                  <i className={copied ? 'ri-check-line' : 'ri-share-line'}></i>
                  <span>{copied ? 'Link Copied to Clipboard!' : 'Share Pairing Page'}</span>
                </button>
              </div>
            </div>

            {/* Why TV QR Login Card */}
            <div className="tv-benefits-card">
              <h4 className="tv-benefits-title">
                <i className="ri-sparkling-fill"></i> Why Pair with Google?
              </h4>
              <div className="tv-benefit-item">
                <div className="tv-benefit-icon">
                  <i className="ri-keyboard-box-line"></i>
                </div>
                <div className="tv-benefit-text">
                  <strong>Zero TV Remote Typing</strong>
                  <p>Never struggle typing complex emails or passwords with an on-screen TV keyboard.</p>
                </div>
              </div>
              <div className="tv-benefit-item">
                <div className="tv-benefit-icon">
                  <i className="ri-history-line"></i>
                </div>
                <div className="tv-benefit-text">
                  <strong>Cloud Watchlist & History</strong>
                  <p>Keep your episode progress, bookmarks, and favorite anime synced seamlessly.</p>
                </div>
              </div>
              <div className="tv-benefit-item">
                <div className="tv-benefit-icon">
                  <i className="ri-lock-2-line"></i>
                </div>
                <div className="tv-benefit-text">
                  <strong>Encrypted & Direct</strong>
                  <p>Direct Firebase Firestore snapshot handoff ensures 100% secure token exchange.</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
