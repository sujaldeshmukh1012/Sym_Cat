import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';

const PAGE_TITLES: Record<string, string> = {
  dashboard: 'Dashboard Overview',
  inventory: 'Inventory Management',
  parts: 'Machine Specs',
  logs: 'Inspector Logs',
  reports: 'Reports',
};

interface TopBarProps {
  activePage: string;
}

export default function TopBar({ activePage }: TopBarProps) {
  const [theme, setTheme] = useState('dark');
  const navigate = useNavigate();

  useEffect(() => {
    const savedTheme = localStorage.getItem('symcat-theme');
    const initialTheme = savedTheme || 'dark';
    setTheme(initialTheme);
    document.documentElement.setAttribute('data-theme', initialTheme);
  }, []);

  function toggleTheme() {
    const nextTheme = theme === 'dark' ? 'light' : 'dark';
    setTheme(nextTheme);
    localStorage.setItem('symcat-theme', nextTheme);
    document.documentElement.setAttribute('data-theme', nextTheme);
  }

  const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

  return (
    <header className="topbar">
      <div
        className="topbar-logo"
        style={{ cursor: 'pointer' }}
        onClick={() => navigate('/')}
        title="Return to Symbiote Intro"
      >
        <div className="topbar-logo-mark">S</div>
        Symbiote
      </div>
      <div className="topbar-divider" />
      <span className="topbar-page-title">{PAGE_TITLES[activePage]}</span>
      <div className="topbar-spacer" />
      <button
        className="theme-toggle"
        onClick={toggleTheme}
        aria-label={`Theme: ${theme}. Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`}
        title={`Theme: ${theme}. Click to switch to ${theme === 'dark' ? 'light' : 'dark'} mode`}
      >
        <span className="theme-toggle-icon">{theme === 'dark' ? '☾' : '☀'}</span>
        <span className="theme-toggle-label">{theme === 'dark' ? 'Dark' : 'Light'}</span>
      </button>
      <div className="topbar-status">
        <span className="status-dot" />
        System Online · {now}
      </div>
    </header>
  );
}
