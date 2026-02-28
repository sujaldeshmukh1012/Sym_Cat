import { useEffect, useState } from 'react'
import { supabase } from '../src/supabase'

export default function Dashboard({ setActivePage }) {
  const [stats, setStats] = useState({ inventory: 0, parts: 0, logs: 0, reports: 0 })
  const [recentLogs, setRecentLogs] = useState([])
  const [lowStock, setLowStock] = useState([])
  const [loading, setLoading] = useState(true)
  const [lastUpdated, setLastUpdated] = useState('')

  useEffect(() => {
    fetchDashboardData()
  }, [])

  async function fetchDashboardData() {
    setLoading(true)
    const [inv, parts, logs, reports, recentLogsRes] = await Promise.all([
      supabase.from('inventory').select('id, quantity', { count: 'exact' }),
      supabase.from('machine_parts').select('id', { count: 'exact' }),
      supabase.from('logs').select('id', { count: 'exact' }),
      supabase.from('reports').select('id', { count: 'exact' }),
      supabase.from('logs').select('*').order('timestamp', { ascending: false }).limit(5),
    ])

    const lowStockRes = await supabase
      .from('inventory')
      .select('id, name, brand, quantity')
      .lt('quantity', 10)
      .order('quantity', { ascending: true })
      .limit(5)

    setStats({
      inventory: inv.count || 0,
      parts: parts.count || 0,
      logs: logs.count || 0,
      reports: reports.count || 0,
    })
    setRecentLogs(recentLogsRes.data || [])
    setLowStock(lowStockRes.data || [])
    setLastUpdated(new Date().toLocaleTimeString())
    setLoading(false)
  }

  const kpis = [
    { label: 'Inventory Items', value: stats.inventory, icon: '▦', page: 'inventory' },
    { label: 'Machine Parts', value: stats.parts, icon: '⚙', page: 'parts' },
    { label: 'Total Log Entries', value: stats.logs, icon: '☰', page: 'logs' },
    { label: 'Total Reports', value: stats.reports, icon: '◻', page: 'reports' },
  ]

  return (
    <div>
      {/* Page Header */}
      <div className="page-header">
        <div>
          <div className="page-title">Dashboard Overview</div>
          <div className="page-subtitle">Real-time operational summary · Last updated {lastUpdated}</div>
        </div>
        <button className="btn btn-secondary btn-sm" onClick={fetchDashboardData}>↻ Refresh</button>
      </div>

      {/* KPI Strip */}
      <div className="kpi-strip">
        {kpis.map(kpi => (
          <div
            key={kpi.label}
            className="kpi-card"
            style={{ cursor: 'pointer' }}
            onClick={() => setActivePage(kpi.page)}
          >
            <div className="kpi-label">{kpi.icon} {kpi.label}</div>
            {loading
              ? <div className="skeleton" style={{ height: 40, width: 80, marginBottom: 8 }} />
              : <div className="kpi-value">{kpi.value.toLocaleString()}</div>
            }
            <div className="kpi-meta">
              <span className="kpi-timestamp">Updated {lastUpdated}</span>
            </div>
          </div>
        ))}
      </div>

      {/* Alerts section */}
      {lowStock.length > 0 && (
        <div className="alert-banner warning" style={{ marginBottom: 24 }}>
          <span style={{ fontSize: 18 }}>⚠</span>
          <div>
            <div className="alert-banner-title">Low Stock Warning — {lowStock.length} item(s) below threshold</div>
            <div className="alert-banner-body">
              {lowStock.map(i => `${i.name} (qty: ${i.quantity})`).join(' · ')}
            </div>
          </div>
          <button className="btn btn-secondary btn-sm" style={{ marginLeft: 'auto' }} onClick={() => setActivePage('inventory')}>
            View Inventory
          </button>
        </div>
      )}

      {/* Operational Overview */}
      <div className="grid-2" style={{ marginBottom: 24 }}>
        {/* Recent Logs */}
        <div className="card">
          <div className="card-header">
            <span className="card-title">☰ Recent Log Entries</span>
            <button className="btn btn-secondary btn-sm" onClick={() => setActivePage('logs')}>View All</button>
          </div>
          <div style={{ overflowX: 'auto' }}>
            {loading ? (
              <div style={{ padding: 16 }}>
                {[...Array(4)].map((_, i) => <div key={i} className="skeleton skeleton-row" style={{ marginBottom: 4 }} />)}
              </div>
            ) : recentLogs.length === 0 ? (
              <div className="empty-state">
                <div className="empty-state-icon">☰</div>
                <div className="empty-state-title">No logs yet</div>
              </div>
            ) : (
              <table>
                <thead>
                  <tr>
                    <th>Inspector</th>
                    <th>Timestamp</th>
                  </tr>
                </thead>
                <tbody>
                  {recentLogs.map(log => (
                    <tr key={log.id}>
                      <td style={{ fontWeight: 500 }}>{log.inspector_name || '—'}</td>
                      <td className="mono" style={{ color: 'var(--text-secondary)', fontSize: 12 }}>
                        {log.timestamp ? new Date(log.timestamp).toLocaleString() : '—'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </div>

        {/* Low Stock */}
        <div className="card">
          <div className="card-header">
            <span className="card-title">▦ Low Stock Items</span>
            <span className="badge badge-warning">
              <span className="badge-dot" /> {lowStock.length} Items
            </span>
          </div>
          <div>
            {loading ? (
              <div style={{ padding: 16 }}>
                {[...Array(4)].map((_, i) => <div key={i} className="skeleton skeleton-row" style={{ marginBottom: 4 }} />)}
              </div>
            ) : lowStock.length === 0 ? (
              <div className="empty-state">
                <div className="empty-state-icon">✓</div>
                <div className="empty-state-title">All stock levels healthy</div>
              </div>
            ) : (
              <table>
                <thead>
                  <tr><th>Item</th><th>Brand</th><th>Qty</th></tr>
                </thead>
                <tbody>
                  {lowStock.map(item => (
                    <tr key={item.id}>
                      <td style={{ fontWeight: 500 }}>{item.name}</td>
                      <td style={{ color: 'var(--text-secondary)' }}>{item.brand}</td>
                      <td>
                        <span className={`badge ${item.quantity === 0 ? 'badge-critical' : 'badge-warning'}`}>
                          <span className="badge-dot" />{item.quantity}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
