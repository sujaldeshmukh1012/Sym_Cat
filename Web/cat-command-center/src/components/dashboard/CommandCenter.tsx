import { useEffect, useState } from 'react';
import Sidebar from './Sidebar';
import TopBar from './TopBar';
import DashboardPage from './DashboardPage';
import InventoryPage from './InventoryPage';
import MachinePartsPage from './MachinePartsPage';
import LogsPage from './LogsPage';
import ReportsPage from './ReportsPage';
import '@/dashboard.css';

export default function CommandCenter() {
  const [activePage, setActivePage] = useState('dashboard');
  const [offlineMode, setOfflineMode] = useState(!navigator.onLine);

  useEffect(() => {
    function handleOnline() { setOfflineMode(false); }
    function handleOffline() { setOfflineMode(true); }
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);
    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  const pages: Record<string, React.ReactNode> = {
    dashboard: <DashboardPage setActivePage={setActivePage} />,
    inventory: <InventoryPage />,
    parts: <MachinePartsPage />,
    logs: <LogsPage />,
    reports: <ReportsPage />,
  };

  return (
    <div className="app-shell" data-theme="dark">
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
  );
}
