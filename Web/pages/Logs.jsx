import { useEffect, useState } from 'react'
import { supabase } from '../src/supabase'

export default function Logs() {
  const [logs, setLogs] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [currentPage, setCurrentPage] = useState(1)
  const [syncStatus, setSyncStatus] = useState('synced')
  const [error, setError] = useState(null)
  const pageSize = 10

  useEffect(() => {
    fetchLogs()
  }, [])

  async function fetchLogs() {
    setLoading(true)
    setError(null)
    setSyncStatus('pending')

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
      setSyncStatus('failed')
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
      setSyncStatus('synced')
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

  const totalPages = Math.max(1, Math.ceil(filtered.length / pageSize))
  const effectivePage = Math.min(currentPage, totalPages)
  const startIndex = (effectivePage - 1) * pageSize
  const endIndex = startIndex + pageSize
  const paginatedLogs = filtered.slice(startIndex, endIndex)

  const showStart = filtered.length === 0 ? 0 : startIndex + 1
  const showEnd = filtered.length === 0 ? 0 : Math.min(endIndex, filtered.length)

  useEffect(() => {
    setCurrentPage(1)
  }, [query])

  useEffect(() => {
    if (currentPage > totalPages) {
      setCurrentPage(totalPages)
    }
  }, [currentPage, totalPages])

  const pageNumbers = (() => {
    if (totalPages <= 7) return Array.from({ length: totalPages }, (_, index) => index + 1)
    if (effectivePage <= 4) return [1, 2, 3, 4, 5, '…', totalPages]
    if (effectivePage >= totalPages - 3) return [1, '…', totalPages - 4, totalPages - 3, totalPages - 2, totalPages - 1, totalPages]
    return [1, '…', effectivePage - 1, effectivePage, effectivePage + 1, '…', totalPages]
  })()

  function getStateBadgeClass(stateValue) {
    const normalized = String(stateValue ?? '').toLowerCase().trim()
    if (normalized === 'completed' || normalized === 'confirmed' || normalized === 'approved') return 'badge-success'
    if (normalized === 'pending') return 'badge-warning'
    if (normalized === 'in_progress' || normalized === 'in progress' || normalized === 'in-progress') return 'badge-info-soft'
    if (normalized === 'declined' || normalized === 'rejected' || normalized === 'failed') return 'badge-critical'
    return 'badge-info'
  }

  function truncateText(value, maxLength = 100) {
    const text = String(value ?? '')
    if (!text) return '—'
    if (text.length <= maxLength) return text
    return `${text.slice(0, maxLength)}...`
  }

  return (
    <div className="logs-shell">
      <div className="page-header">
        <div>
          <div className="page-title">Logs</div>
          <div className="page-subtitle">{logs.length} total task entries · sorted by latest</div>
        </div>
        <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
          <button className="btn btn-secondary btn-sm" onClick={fetchLogs}>↻ Refresh</button>
          <span className={`sync-pill ${syncStatus}`}>
            <span className="badge-dot" />
            {syncStatus === 'synced' ? 'Synced' : syncStatus === 'pending' ? 'Saving…' : 'Sync Failed'}
          </span>
        </div>
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
                <th style={{ textAlign: 'center' }}>ID</th>
                <th style={{ textAlign: 'center' }}>Fleet Serial</th>
                <th style={{ textAlign: 'center' }}>Inspection ID</th>
                <th style={{ textAlign: 'center' }}>Title</th>
                <th style={{ textAlign: 'center' }}>State</th>
                <th style={{ textAlign: 'center' }}>Description</th>
                <th style={{ textAlign: 'center' }}>Feedback</th>
                <th style={{ textAlign: 'center' }}>Created At</th>
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
                paginatedLogs.map(log => (
                  <tr key={log.id}>
                    <td className="mono" style={{ color: 'var(--text-muted)', fontSize: 12, textAlign: 'center' }}>{log.id}</td>
                    <td className="mono" style={{ color: 'var(--text-muted)', fontSize: 12, textAlign: 'center' }}>{log.fleet_serial || '—'}</td>
                    <td className="mono" style={{ color: 'var(--text-secondary)', fontSize: 12, textAlign: 'center' }}>{log.inspection_id || '—'}</td>
                    <td style={{ fontWeight: 600, textAlign: 'center' }}>{log.title || '—'}</td>
                    <td style={{ textAlign: 'center' }}>
                      <span className={`badge ${getStateBadgeClass(log.resolved_state)}`}>
                        <span className="badge-dot" /> {log.resolved_state || '—'}
                      </span>
                    </td>
                    <td style={{ color: 'var(--text-secondary)', maxWidth: 360, textAlign: 'center' }}>
                      <span className="logs-text-cell" title={log.description || ''}>{truncateText(log.description)}</span>
                    </td>
                    <td style={{ color: 'var(--text-secondary)', maxWidth: 360, textAlign: 'center' }}>
                      <span className="logs-text-cell" title={log.feedback || ''}>{truncateText(log.feedback)}</span>
                    </td>
                    <td className="mono" style={{ fontSize: 12, color: 'var(--text-secondary)', textAlign: 'center' }}>{formatDate(log.created_at)}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        {!loading && filtered.length > 0 && (
          <div className="inventory-pagination">
            <div className="inventory-pagination-meta">
              Showing <span className="mono">{showStart}-{showEnd}</span> of <span className="mono">{filtered.length}</span>
            </div>

            <div className="inventory-pagination-controls">
              <button
                className="btn btn-secondary btn-sm"
                onClick={() => setCurrentPage(page => Math.max(1, page - 1))}
                disabled={effectivePage === 1}
              >
                ← Prev
              </button>

              <div className="inventory-page-list">
                {pageNumbers.map((page, index) =>
                  page === '…' ? (
                    <span key={`dots-${index}`} className="inventory-page-dots">…</span>
                  ) : (
                    <button
                      key={`page-${page}`}
                      className={`inventory-page-btn${page === effectivePage ? ' active' : ''}`}
                      onClick={() => setCurrentPage(page)}
                    >
                      {page}
                    </button>
                  )
                )}
              </div>

              <button
                className="btn btn-secondary btn-sm"
                onClick={() => setCurrentPage(page => Math.min(totalPages, page + 1))}
                disabled={effectivePage === totalPages}
              >
                Next →
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}