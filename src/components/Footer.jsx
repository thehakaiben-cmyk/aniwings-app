import { Link } from 'react-router-dom';

export default function Footer() {
  const currentYear = new Date().getFullYear();

  const socials = [
    {
      name: 'Discord',
      href: 'https://discord.com/invite/w7KwAcyPG3',
      icon: 'ri-discord-fill'
    },
    {
      name: 'Telegram',
      href: 'https://t.me/aniwings_off',
      icon: 'ri-telegram-fill'
    },
    {
      name: 'Reddit',
      href: 'https://www.reddit.com/r/AniWings_Official/',
      icon: 'ri-reddit-fill'
    }
  ];

  return (
    <div id="footer" style={{ borderTop: '1px solid rgba(255, 255, 255, 0.05)' }}>
      <div className="container">
        <div className="footer-content" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center' }}>
          <div className="footer-logo-container" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '10px', marginBottom: '1.5rem' }}>
            <img src="/images/logo.png" alt="AniWings logo" className="footer-logo-img" style={{ height: '40px', width: 'auto', borderRadius: '8px' }} />
            <Link to="/" className="footer-logo-text" style={{ fontFamily: "'Outfit', sans-serif", fontSize: '24px', fontWeight: 800, letterSpacing: '-0.5px' }}>
              Ani<span style={{ color: 'var(--accent-primary)' }}>Wings</span>
            </Link>
          </div>
          <p className="desc" style={{ color: 'var(--text-secondary)', maxWidth: '500px', fontSize: '14px', lineHeight: '1.6', marginBottom: '1.5rem' }}>
            AniWings is a top-tier anime client for Android. It lets you stream thousands of HD episodes smoothly and completely free with no intrusive ads or sign-ups.
          </p>
          <div className="fl-socials" style={{ display: 'flex', gap: '1.5rem', marginBottom: '2rem' }}>
            {socials.map((social) => (
              <a 
                key={social.name}
                href={social.href} 
                target="_blank" 
                rel="noopener noreferrer" 
                className="fbi-icon" 
                title={social.name}
                style={{
                  display: 'inline-flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  width: '44px',
                  height: '44px',
                  borderRadius: '50%',
                  background: 'rgba(255, 255, 255, 0.03)',
                  border: '1px solid rgba(255, 255, 255, 0.05)',
                  color: 'var(--text-secondary)',
                  fontSize: '20px',
                  transition: 'all 0.3s ease'
                }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.background = 'rgba(226, 91, 115, 0.1)';
                  e.currentTarget.style.borderColor = 'var(--accent-primary)';
                  e.currentTarget.style.color = 'var(--accent-primary)';
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.background = 'rgba(255, 255, 255, 0.03)';
                  e.currentTarget.style.borderColor = 'rgba(255, 255, 255, 0.05)';
                  e.currentTarget.style.color = 'var(--text-secondary)';
                }}
              >
                <i className={social.icon}></i>
              </a>
            ))}
          </div>
          <div className="copyright" style={{ color: 'var(--text-muted)', fontSize: '12px', borderTop: '1px solid rgba(255, 255, 255, 0.03)', width: '100%', paddingTop: '1.5rem' }}>
            &copy; {currentYear} AniWings. All rights reserved. Built for anime lovers.
          </div>
        </div>
      </div>
    </div>
  );
}
