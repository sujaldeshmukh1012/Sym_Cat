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

    const { data, error } = await supabase
      .from('logs')
      .select('id, user_id, machine_spec_id, inspected_at, status, problem, created_at')
      .order('inspected_at', { ascending: false })

    if (error) {
      setError('Failed to load logs. Check your connection and try again.')
    } else {
      setLogs(data || [])
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
    String(log.user_id ?? '').toLowerCase().includes(query) ||
    String(log.machine_spec_id ?? '').toLowerCase().includes(query) ||
    String(log.status ?? '').toLowerCase().includes(query) ||
    String(log.problem ?? '').toLowerCase().includes(query)
  )

  return (
    <div>
      <div className="page-header">
        <div>
          <div className="page-title">Logs</div>
          <div className="page-subtitle">{logs.length} total entries · sorted by latest inspection</div>
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
              placeholder="Search by id, user, machine spec, status, or problem…"
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
                <th>User ID</th>
                <th>Machine Spec ID</th>
                <th>Inspected At</th>
                <th>Status</th>
                <th>Problem</th>
                <th>Created At</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                [...Array(6)].map((_, i) => (
                  <tr key={i}>
                    {[...Array(7)].map((_, j) => (
                      <td key={j}><div className="skeleton" style={{ height: 16, width: j === 5 ? 220 : 100 }} /></td>
                    ))}
                  </tr>
                ))
              ) : filtered.length === 0 ? (
                <tr>
                  <td colSpan={7}>
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
                    <td className="mono" style={{ color: 'var(--text-muted)', fontSize: 12 }}>{log.user_id || '—'}</td>
                    <td className="mono" style={{ color: 'var(--text-secondary)', fontSize: 12 }}>{log.machine_spec_id || '—'}</td>
                    <td className="mono" style={{ fontSize: 12, color: 'var(--text-secondary)' }}>{formatDate(log.inspected_at)}</td>
                    <td>
                      <span className="badge badge-info">
                        <span className="badge-dot" /> {log.status || '—'}
                      </span>
                    </td>
                    <td style={{ color: 'var(--text-secondary)', maxWidth: 360 }}>
                      <span style={{ display: 'block', whiteSpace: 'pre-wrap' }}>{log.problem || '—'}</span>
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