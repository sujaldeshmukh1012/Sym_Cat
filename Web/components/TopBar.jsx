import { useEffect, useState } from 'react'
import symbiote_logo from "./symbiote_logo.png"

const PAGE_TITLES = {
  dashboard: 'Dashboard Overview',
  fleet_health_analytics: 'Fleet Health Analytics',
  inventory: 'Inventory Management',
  parts: 'Machine Specs',
  order_cart: 'Order Cart',
  logs: 'Inspector Logs',
  reports: 'Reports',
}

export default function TopBar({ activePage }) {
  const [theme, setTheme] = useState('light')

  useEffect(() => {
    const savedTheme = localStorage.getItem('symcat-theme')
    const systemPrefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches
    const initialTheme = savedTheme || (systemPrefersDark ? 'dark' : 'light')
    setTheme(initialTheme)
    document.documentElement.setAttribute('data-theme', initialTheme)
  }, [])

  function toggleTheme() {
    const nextTheme = theme === 'dark' ? 'light' : 'dark'
    setTheme(nextTheme)
    localStorage.setItem('symcat-theme', nextTheme)
    document.documentElement.setAttribute('data-theme', nextTheme)
  }

  const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
  return (
    <header className="topbar">
      <div className="topbar-logo">
          <img src={symbiote_logo} alt="Symbiote Logo" className="topbar-logo-mark" />
          <span>Symbiote</span>
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
  )
}
