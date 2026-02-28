import { useEffect, useState } from 'react'
import { supabase } from '../src/supabase'

export default function Dashboard({ setActivePage }) {
  const [stats, setStats] = useState({ inventory: 0, parts: 0, logs: 0, reports: 0 })
  const [recentLogs, setRecentLogs] = useState([])
  const [lowStock, setLowStock] = useState([])
  const [loading, setLoading] = useState(true)
  const [lastUpdated, setLastUpdated] = useState('')
  const [dashboardError, setDashboardError] = useState('')

  useEffect(() => {
    fetchDashboardData()
  }, [])

  async function fetchDashboardData() {
    setLoading(true)
    setDashboardError('')
    const [inv, parts, logs, reportsDb, recentLogsRes, lowStockRes] = await Promise.all([
      supabase.from('inventory').select('id, stock_qty, created_at', { count: 'exact' }),
      supabase.from('parts').select('id', { count: 'exact' }),
      supabase.from('task').select('id', { count: 'exact' }),
      supabase.from('report').select('id', { count: 'exact' }),
      supabase.from('task').select('id, inspection_id, state, created_at').order('created_at', { ascending: false }).limit(5),
      supabase
        .from('inventory')
        .select('id, part_name, component_tag, stock_qty')
        .lt('stock_qty', 10)
        .order('stock_qty', { ascending: true })
        .limit(5),
    ])

    const recentInspectionIds = Array.from(
      new Set(
        (recentLogsRes.data || [])
          .map(log => log.inspection_id)
          .filter(inspectionId => inspectionId !== null && inspectionId !== undefined)
      )
    )

    let orderCartRes = { data: [], error: null }
    if (recentInspectionIds.length > 0) {
      orderCartRes = await supabase
        .from('order_cart')
        .select('inspection_id, status, created_at')
        .in('inspection_id', recentInspectionIds)
        .order('created_at', { ascending: false })
    }

    const errors = [inv.error, parts.error, logs.error, reportsDb.error, recentLogsRes.error, orderCartRes.error, lowStockRes.error]
      .filter(Boolean)
      .map(error => error.message)

    if (errors.length > 0) {
      setDashboardError(errors[0])
    }

    const safeCount = (result) => {
      if (typeof result.count === 'number') return result.count
      if (Array.isArray(result.data)) return result.data.length
      return 0
    }

    const inventoryCount = safeCount(inv)

    if (import.meta.env.DEV) {
      console.group('[Dashboard] Supabase query diagnostics')
      console.log('inventory', {
        error: inv.error?.message || null,
        count: inv.count,
        rowsVisible: Array.isArray(inv.data) ? inv.data.length : 0,
        sample: Array.isArray(inv.data) ? inv.data.slice(0, 3) : [],
      })
      console.log('parts', { error: parts.error?.message || null, count: parts.count })
      console.log('task', { error: logs.error?.message || null, count: logs.count })
      console.log('report_db', { error: reportsDb.error?.message || null, count: reportsDb.count })
      console.log('recentLogs', {
        error: recentLogsRes.error?.message || null,
        rows: Array.isArray(recentLogsRes.data) ? recentLogsRes.data.length : 0,
      })
      console.log('order_cart', {
        error: orderCartRes.error?.message || null,
        rows: Array.isArray(orderCartRes.data) ? orderCartRes.data.length : 0,
      })
      console.log('lowStock', {
        error: lowStockRes.error?.message || null,
        rows: Array.isArray(lowStockRes.data) ? lowStockRes.data.length : 0,
      })
      console.groupEnd()
    }

    const latestOrderStatusByInspectionId = {}
    if (!orderCartRes.error && Array.isArray(orderCartRes.data)) {
      for (const row of orderCartRes.data) {
        const key = String(row.inspection_id ?? '')
        if (!key || latestOrderStatusByInspectionId[key]) continue
        latestOrderStatusByInspectionId[key] = String(row.status ?? '').replace(/^"|"$/g, '')
      }
    }

    const resolvedRecentLogs = (recentLogsRes.data || []).map(log => {
      const key = String(log.inspection_id ?? '')
      return {
        ...log,
        resolved_state: latestOrderStatusByInspectionId[key] || log.state,
      }
    })

    setStats({
      inventory: inventoryCount,
      parts: safeCount(parts),
      logs: safeCount(logs),
      reports: safeCount(reportsDb),
    })
    setRecentLogs(resolvedRecentLogs)
    setLowStock(lowStockRes.data || [])
    setLastUpdated(new Date().toLocaleTimeString())
    setLoading(false)
  }

  const kpis = [
    { label: 'Inventory Items', value: stats.inventory, icon: '▦', page: 'inventory' },
    { label: 'Machine Parts', value: stats.parts, icon: '⚙', page: 'parts' },
    { label: 'Total Tasks', value: stats.logs, icon: '☰', page: 'logs' },
    { label: 'Total Reports', value: stats.reports, icon: '◻', page: 'reports' },
  ]

  return (
    <div className="dashboard-shell">
      {/* Page Header */}
      <div className="page-header dashboard-header">
        <div className="dashboard-header-copy">
          <div className="page-title">Dashboard Overview</div>
          <div className="page-subtitle">Real-time operational summary · Last updated {lastUpdated}</div>
        </div>
        <button className="btn btn-sm dashboard-refresh-btn" onClick={fetchDashboardData}>↻ Refresh</button>
      </div>

      {dashboardError && (
        <div className="alert-banner critical" style={{ marginBottom: 16 }}>
          <span>✕</span>
          <div>
            <div className="alert-banner-title">Dashboard Data Error</div>
            <div className="alert-banner-body">{dashboardError}</div>
          </div>
        </div>
      )}

      {/* KPI Strip */}
      <div className="kpi-strip dashboard-kpi-strip">
        {kpis.map(kpi => (
          <div
            key={kpi.label}
            className="kpi-card dashboard-kpi-card"
            style={{ cursor: 'pointer' }}
            onClick={() => setActivePage(kpi.page)}
          >
            <div className="kpi-label dashboard-kpi-label">{kpi.icon} {kpi.label}</div>
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
              {lowStock.map(i => `${i.part_name || 'Unnamed part'} (qty: ${i.stock_qty ?? 0})`).join(' · ')}
            </div>
          </div>
          <button className="btn btn-secondary btn-sm" style={{ marginLeft: 'auto' }} onClick={() => setActivePage('inventory')}>
            View Inventory
          </button>
        </div>
      )}

      {/* Operational Overview */}
      <div className="grid-2 dashboard-panels" style={{ marginBottom: 24 }}>
        {/* Recent Logs */}
        <div className="card dashboard-panel-card">
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
                    <th>Inspection</th>
                    <th>State</th>
                    <th>Created At</th>
                  </tr>
                </thead>
                <tbody>
                  {recentLogs.map(log => (
                    <tr key={log.id}>
                      <td style={{ fontWeight: 500 }}>{log.inspection_id || '—'}</td>
                      <td>
                        <span className="badge badge-info">
                          <span className="badge-dot" /> {log.resolved_state || '—'}
                        </span>
                      </td>
                      <td className="mono" style={{ color: 'var(--text-secondary)', fontSize: 12 }}>
                        {log.created_at ? new Date(log.created_at).toLocaleString() : '—'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </div>

        {/* Low Stock */}
        <div className="card dashboard-panel-card">
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
                  <tr><th>Part</th><th>Component Tag</th><th>Stock Qty</th></tr>
                </thead>
                <tbody>
                  {lowStock.map(item => (
                    <tr key={item.id}>
                      <td style={{ fontWeight: 500 }}>{item.part_name || '—'}</td>
                      <td style={{ color: 'var(--text-secondary)' }}>{item.component_tag || '—'}</td>
                      <td>
                        <span className={`badge ${item.stock_qty === 0 ? 'badge-critical' : 'badge-warning'}`}>
                          <span className="badge-dot" />{item.stock_qty}
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
