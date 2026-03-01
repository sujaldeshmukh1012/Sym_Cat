import { useEffect, useState } from 'react'
import Sidebar from '../components/Sidebar'
import TopBar from '../components/TopBar'
import Dashboard from '../pages/Dashboard'
import FleetHealthAnalytics from '../pages/FleetHealthAnalytics'
import Inventory from '../pages/Inventory'
import MachineParts from '../pages/MachineParts'
import Logs from '../pages/Logs'
import Reports from '../pages/Reports'
import OrderCart from '../pages/OrderCart'
import './App.css'

const PAGE_STORAGE_KEY = 'symcat-active-page'
const VALID_PAGES = new Set([
  'dashboard',
  'fleet_health_analytics',
  'inventory',
  'parts',
  'logs',
  'reports',
  'order_cart',
])

function getInitialPage() {
  const saved = localStorage.getItem(PAGE_STORAGE_KEY)
  return VALID_PAGES.has(saved) ? saved : 'dashboard'
}

export default function App() {
  const [activePage, setActivePage] = useState(getInitialPage)
  const [offlineMode, setOfflineMode] = useState(!navigator.onLine)

  useEffect(() => {
    function handleOnline() {
      setOfflineMode(false)
    }

    function handleOffline() {
      setOfflineMode(true)
    }

    window.addEventListener('online', handleOnline)
    window.addEventListener('offline', handleOffline)

    return () => {
      window.removeEventListener('online', handleOnline)
      window.removeEventListener('offline', handleOffline)
    }
  }, [])

  useEffect(() => {
    localStorage.setItem(PAGE_STORAGE_KEY, activePage)
  }, [activePage])

  const pages = {
    dashboard: <Dashboard setActivePage={setActivePage} />,
    fleet_health_analytics: <FleetHealthAnalytics />,
    inventory: <Inventory />,
    parts: <MachineParts />,
    logs: <Logs />,
    reports: <Reports />,
    order_cart: <OrderCart />,
  }

  return (
    <div className="app-shell">
      {offlineMode && (
        <div className="offline-banner">
          <span className="offline-icon">⚠</span>
          <strong>Offline Mode</strong> — Actions are queued and will sync when connection is restored.
        </div>
      )}
      <TopBar activePage={activePage} />
      <div className="app-body">
        <Sidebar activePage={activePage} setActivePage={setActivePage} />
        <main className="main-content">
          {pages[activePage]}
        </main>
      </div>
    </div>
  )
}
