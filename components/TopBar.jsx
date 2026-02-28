const PAGE_TITLES = {
  dashboard: 'Dashboard Overview',
  inventory: 'Inventory Management',
  parts: 'Machine Parts',
  logs: 'Inspector Logs',
  reports: 'Reports',
}

export default function TopBar({ activePage }) {
  const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
  return (
    <header className="topbar">
      <div className="topbar-logo">
        <div className="topbar-logo-mark">⚙</div>
        SymCat
      </div>
      <div className="topbar-divider" />
      <span className="topbar-page-title">{PAGE_TITLES[activePage]}</span>
      <div className="topbar-spacer" />
      <div className="topbar-status">
        <span className="status-dot" />
        System Online · {now}
      </div>
    </header>
  )
}
