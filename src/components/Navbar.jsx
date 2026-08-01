import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';

export default function Navbar() {
  const [menuOpen, setMenuOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  const [activeSection, setActiveSection] = useState('');

  useEffect(() => {
    const handleScroll = () => {
      setScrolled(window.scrollY > 30);
    };
    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  useEffect(() => {
    const sections = ['heading-content', 'section-about', 'section-features', 'section-download'];
    const observers = sections.map((id) => {
      const el = document.getElementById(id);
      if (!el) return null;
      const observer = new IntersectionObserver(
        ([entry]) => {
          if (entry.isIntersecting) setActiveSection(id);
        },
        { rootMargin: '-40% 0px -55% 0px' }
      );
      observer.observe(el);
      return observer;
    });
    return () => observers.forEach((obs) => obs && obs.disconnect());
  }, []);

  useEffect(() => {
    document.body.style.overflow = menuOpen ? 'hidden' : '';
    return () => { document.body.style.overflow = ''; };
  }, [menuOpen]);

  const navLinks = [
    { label: 'Home', href: '#heading-content', id: 'heading-content' },
    { label: 'About', href: '#section-about', id: 'section-about' },
    { label: 'Features', href: '#section-features', id: 'section-features' },
    { label: 'Download', href: '#section-download', id: 'section-download' },
  ];

  const handleNavClick = (e, href) => {
    e.preventDefault();
    setMenuOpen(false);
    const el = document.querySelector(href);
    if (el) el.scrollIntoView({ behavior: 'smooth' });
  };

  const handleFollowClick = (e) => {
    e.preventDefault();
    setMenuOpen(false);
    const footer = document.getElementById('footer');
    if (footer) footer.scrollIntoView({ behavior: 'smooth' });
  };

  return (
    <nav className={`navbar${scrolled ? ' scrolled' : ''}`}>
      <div className="navbar__inner">

        {/* Column 1 — Logo */}
        <Link to="/" className="navbar__logo">
          <img src="/images/logo.png" alt="AniWings" />
          <span className="navbar__logo-text">
            Ani<span>Wings</span>
          </span>
        </Link>

        {/* Column 2 — Desktop Nav Links (true center) */}
        <ul className="navbar__links">
          {navLinks.map((link) => (
            <li key={link.href}>
              <a
                href={link.href}
                className={`navbar__link${activeSection === link.id ? ' active' : ''}`}
                onClick={(e) => handleNavClick(e, link.href)}
              >
                {link.label}
              </a>
            </li>
          ))}
        </ul>

        {/* Column 3 — Right side: Follow CTA + Hamburger */}
        <div className="navbar__right">
          <a
            href="#footer"
            className="navbar__cta"
            onClick={handleFollowClick}
            id="navbar-follow-btn"
          >
            <i className="ri-heart-line"></i>
            Follow
          </a>

          <button
            className={`navbar__hamburger${menuOpen ? ' open' : ''}`}
            onClick={() => setMenuOpen(!menuOpen)}
            aria-label="Toggle menu"
          >
            <span></span>
            <span></span>
            <span></span>
          </button>
        </div>

      </div>

      {/* Mobile Menu */}
      <div className={`navbar__mobile${menuOpen ? '' : ' hidden'}`}>
        <div className="navbar__mobile-links">
          {navLinks.map((link) => (
            <a
              key={link.href}
              href={link.href}
              className={`navbar__mobile-link${activeSection === link.id ? ' active' : ''}`}
              onClick={(e) => handleNavClick(e, link.href)}
            >
              <i className={`ri-${link.id === 'heading-content' ? 'home-4' : link.id === 'section-about' ? 'information' : link.id === 'section-features' ? 'sparkles' : 'download'}-line`}></i>
              {link.label}
            </a>
          ))}
        </div>
        <div className="navbar__mobile-footer">
          <a
            href="#footer"
            className="navbar__mobile-cta"
            onClick={handleFollowClick}
          >
            <i className="ri-heart-line"></i>
            Follow Us
          </a>
        </div>
      </div>
    </nav>
  );
}
