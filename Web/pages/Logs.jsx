import { useEffect, useState } from 'react'
import { supabase } from '../src/supabase'

export default function Logs() {
  const [logs, setLogs] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [error, setError] = useState(null)

  useEffect(() => {
    fetchLogs()
  }, [])

  async function fetchLogs() {
    setLoading(true)
    setError(null)

    const [tasksRes, orderCartRes] = await Promise.all([
      supabase
        .from('task')
        .select('id, fleet_serial, inspection_id, title, state, description, feedback, created_at')
        .order('created_at', { ascending: false }),
      supabase
        .from('order_cart')
        .select('inspection_id, status, created_at')
        .order('created_at', { ascending: false }),
    ])

    if (tasksRes.error) {
      setError('Failed to load logs. Check your connection and try again.')
    } else {
      const latestOrderStatusByInspectionId = {}
      if (!orderCartRes.error && Array.isArray(orderCartRes.data)) {
        for (const row of orderCartRes.data) {
          const key = String(row.inspection_id ?? '')
          if (!key || latestOrderStatusByInspectionId[key]) continue
          latestOrderStatusByInspectionId[key] = String(row.status ?? '').replace(/^"|"$/g, '')
        }
      }

      const merged = (tasksRes.data || []).map(task => {
        const inspectionKey = String(task.inspection_id ?? '')
        const orderStatus = latestOrderStatusByInspectionId[inspectionKey]
        return {
          ...task,
          resolved_state: orderStatus || task.state,
        }
      })

      setLogs(merged)
    }

    setLoading(false)
  }

  function formatDate(value) {
    if (!value) return '—'
    return new Date(value).toLocaleString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    })
  }

  const query = search.toLowerCase()
  const filtered = logs.filter(log =>
    String(log.id ?? '').toLowerCase().includes(query) ||
    String(log.fleet_serial ?? '').toLowerCase().includes(query) ||
    String(log.inspection_id ?? '').toLowerCase().includes(query) ||
    String(log.title ?? '').toLowerCase().includes(query) ||
    String(log.resolved_state ?? '').toLowerCase().includes(query) ||
    String(log.description ?? '').toLowerCase().includes(query) ||
    String(log.feedback ?? '').toLowerCase().includes(query)
  )

  return (
    <div>
      <div className="page-header">
        <div>
          <div className="page-title">Logs</div>
          <div className="page-subtitle">{logs.length} total task entries · sorted by latest</div>
        </div>
        <button className="btn btn-secondary btn-sm" onClick={fetchLogs}>↻ Refresh</button>
      </div>

      {error && (
        <div className="alert-banner critical" style={{ marginBottom: 16 }}>
          <span>✕</span>
          <div>
            <div className="alert-banner-title">Load Error</div>
            <div className="alert-banner-body">{error}</div>
          </div>
          <button className="btn btn-secondary btn-sm" style={{ marginLeft: 'auto' }} onClick={fetchLogs}>Retry</button>
        </div>
      )}

      <div className="card">
        <div className="card-header">
          <div className="search-bar">
            <span className="search-icon">⌕</span>
            <input
              placeholder="Search by id, fleet, inspection, title, state, description, or feedback…"
              value={search}
              onChange={e => setSearch(e.target.value)}
            />
          </div>
          <span style={{ fontSize: 13, color: 'var(--text-muted)' }}>{filtered.length} entries</span>
        </div>

        <div className="table-wrapper" style={{ borderRadius: 0, border: 'none' }}>
          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>Fleet Serial</th>
                <th>Inspection ID</th>
                <th>Title</th>
                <th>State</th>
                <th>Description</th>
                <th>Feedback</th>
                <th>Created At</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                [...Array(6)].map((_, i) => (
                  <tr key={i}>
                    {[...Array(8)].map((_, j) => (
                      <td key={j}><div className="skeleton" style={{ height: 16, width: j === 5 ? 220 : 100 }} /></td>
                    ))}
                  </tr>
                ))
              ) : filtered.length === 0 ? (
                <tr>
                  <td colSpan={8}>
                    <div className="empty-state">
                      <div className="empty-state-icon">☰</div>
                      <div className="empty-state-title">No log entries found</div>
                      <div className="empty-state-desc">Logs will appear here once recorded</div>
                    </div>
                  </td>
                </tr>
              ) : (
                filtered.map(log => (
                  <tr key={log.id}>
                    <td className="mono" style={{ color: 'var(--text-muted)', fontSize: 12 }}>{log.id}</td>
                    <td className="mono" style={{ color: 'var(--text-muted)', fontSize: 12 }}>{log.fleet_serial || '—'}</td>
                    <td className="mono" style={{ color: 'var(--text-secondary)', fontSize: 12 }}>{log.inspection_id || '—'}</td>
                    <td style={{ fontWeight: 600 }}>{log.title || '—'}</td>
                    <td>
                      <span className="badge badge-info">
                        <span className="badge-dot" /> {log.resolved_state || '—'}
                      </span>
                    </td>
                    <td style={{ color: 'var(--text-secondary)', maxWidth: 360 }}>
                      <span style={{ display: 'block', whiteSpace: 'pre-wrap' }}>{log.description || '—'}</span>
                    </td>
                    <td style={{ color: 'var(--text-secondary)', maxWidth: 360 }}>
                      <span style={{ display: 'block', whiteSpace: 'pre-wrap' }}>{log.feedback || '—'}</span>
                    </td>
                    <td className="mono" style={{ fontSize: 12, color: 'var(--text-secondary)' }}>{formatDate(log.created_at)}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}