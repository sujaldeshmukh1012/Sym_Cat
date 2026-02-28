import { useEffect, useState } from 'react'
import Sidebar from '../components/Sidebar'
import TopBar from '../components/TopBar'
import Dashboard from '../pages/Dashboard'
import Inventory from '../pages/Inventory'
import MachineParts from '../pages/MachineParts'
import Logs from '../pages/Logs'
import Reports from '../pages/Reports'
import './App.css'

export default function App() {
  const [activePage, setActivePage] = useState('dashboard')
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

  const pages = {
    dashboard: <Dashboard setActivePage={setActivePage} />,
    inventory: <Inventory />,
    parts: <MachineParts />,
    logs: <Logs />,
    reports: <Reports />,
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
