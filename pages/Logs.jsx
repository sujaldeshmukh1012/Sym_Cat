import { useEffect, useState } from 'react'
import { supabase } from '../src/supabase'

export default function Logs() {
  const [logs, setLogs] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [expandedId, setExpandedId] = useState(null)
  const [error, setError] = useState(null)

  useEffect(() => { fetchLogs() }, [])

  async function fetchLogs() {
    setLoading(true)
    setError(null)
    const { data, error } = await supabase
      .from('logs')
      .select('*')
      .order('timestamp', { ascending: false })
    if (error) {
      setError('Failed to load logs. Check your connection and try again.')
    } else {
      setLogs(data || [])
    }
    setLoading(false)
  }

  const filtered = logs.filter(l =>
    l.inspector_name?.toLowerCase().includes(search.toLowerCase()) ||
    l.conversation?.toLowerCase().includes(search.toLowerCase())
  )

  function formatDate(ts) {
    if (!ts) return '—'
    return new Date(ts).toLocaleString('en-US', {
      month: 'short', day: 'numeric', year: 'numeric',
      hour: '2-digit', minute: '2-digit'
    })
  }

  return (
    <div>
      <div className="page-header">
        <div>
          <div className="page-title">Inspector Logs</div>
          <div className="page-subtitle">{logs.length} total entries · sorted by latest</div>
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
              placeholder="Search by inspector or content…"
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
                <th>Inspector</th>
                <th>Timestamp</th>
                <th>Conversation Preview</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                [...Array(6)].map((_, i) => (
                  <tr key={i}>
                    {[...Array(5)].map((_, j) => (
                      <td key={j}><div className="skeleton" style={{ height: 16, width: j === 3 ? 200 : 100 }} /></td>
                    ))}
                  </tr>
                ))
              ) : filtered.length === 0 ? (
                <tr>
                  <td colSpan={5}>
                    <div className="empty-state">
                      <div className="empty-state-icon">☰</div>
                      <div className="empty-state-title">No log entries found</div>
                      <div className="empty-state-desc">Inspector logs will appear here once recorded</div>
                    </div>
                  </td>
                </tr>
              ) : (
                filtered.map(log => (
                  <>
                    <tr key={log.id} style={{ cursor: 'pointer' }} onClick={() => setExpandedId(expandedId === log.id ? null : log.id)}>
                      <td className="mono" style={{ color: 'var(--text-muted)', fontSize: 12 }}>{log.id}</td>
                      <td style={{ fontWeight: 600 }}>{log.inspector_name || '—'}</td>
                      <td className="mono" style={{ fontSize: 12, color: 'var(--text-secondary)' }}>
                        {formatDate(log.timestamp)}
                      </td>
                      <td style={{ color: 'var(--text-secondary)', maxWidth: 300 }}>
                        <span style={{
                          display: 'block',
                          overflow: 'hidden',
                          textOverflow: 'ellipsis',
                          whiteSpace: 'nowrap',
                          fontSize: 13
                        }}>
                          {log.conversation
                            ? log.conversation.substring(0, 80) + (log.conversation.length > 80 ? '…' : '')
                            : '—'
                          }
                        </span>
                      </td>
                      <td>
                        <button className="btn btn-secondary btn-sm">
                          {expandedId === log.id ? '▲ Collapse' : '▼ Expand'}
                        </button>
                      </td>
                    </tr>
                    {expandedId === log.id && (
                      <tr key={`${log.id}-expanded`}>
                        <td colSpan={5} style={{ background: 'var(--primary-light)', padding: 0 }}>
                          <div style={{ padding: '20px 24px' }}>
                            <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.07em', marginBottom: 10 }}>
                              Full Conversation Log
                            </div>
                            <div style={{
                              background: 'var(--card)',
                              border: '1px solid var(--border)',
                              borderRadius: 6,
                              padding: '16px',
                              fontFamily: 'var(--font-mono)',
                              fontSize: 13,
                              lineHeight: 1.7,
                              whiteSpace: 'pre-wrap',
                              color: 'var(--text-primary)',
                              maxHeight: 300,
                              overflowY: 'auto'
                            }}>
                              {log.conversation || 'No conversation content recorded.'}
                            </div>
                            <div style={{ marginTop: 12, display: 'flex', gap: 8 }}>
                              <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>
                                Log ID: <span className="mono">{log.id}</span>
                              </span>
                              <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>·</span>
                              <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>
                                Recorded: {formatDate(log.timestamp)}
                              </span>
                            </div>
                          </div>
                        </td>
                      </tr>
                    )}
                  </>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
