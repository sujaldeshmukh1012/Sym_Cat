const NAV_ITEMS = [
  { key: 'dashboard', icon: '◈', label: 'Dashboard' },
  { key: 'inventory', icon: '▦', label: 'Inventory' },
  { key: 'parts', icon: '⚙', label: 'Machine Specs' },
  { key: 'order_cart', icon: '🛒', label: 'Order Cart' },
  { key: 'logs', icon: '☰', label: 'Inspector Logs' },
  { key: 'reports', icon: '◻', label: 'Reports' },
]

export default function Sidebar({ activePage, setActivePage }) {
  return (
    <aside className="sidebar">
      <div className="sidebar-section-label">Navigation</div>
      <nav className="sidebar-nav">
        {NAV_ITEMS.map(item => (
          <button
            key={item.key}
            className={`sidebar-item${activePage === item.key ? ' active' : ''}`}
            onClick={() => setActivePage(item.key)}
          >
            <span className="sidebar-icon">{item.icon}</span>
            {item.label}
          </button>
        ))}
      </nav>
      <div className="sidebar-footer">
        Symbiote v1.0<br />
        <span style={{ fontSize: 11 }}>Powered by Supabase</span>
      </div>
    </aside>
  )
}
