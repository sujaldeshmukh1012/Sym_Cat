import { useEffect, useState } from 'react'

const API_BASE_URL = (import.meta.env.VITE_API_BASE_URL || 'http://localhost:8000').replace(/\/$/, '')

export default function Reports() {
  const [reports, setReports] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [error, setError] = useState(null)

  useEffect(() => {
    fetchReports()
  }, [])

  async function fetchReports() {
    setLoading(true)
    setError(null)

    try {
      const controller = new AbortController()
      const timeoutId = window.setTimeout(() => controller.abort(), 10000)
      const response = await fetch(`${API_BASE_URL}/reports`, { signal: controller.signal })
      window.clearTimeout(timeoutId)

      if (!response.ok) throw new Error(`Request failed (${response.status})`)
      const payload = await response.json()
      setReports(payload.data || [])
    } catch (err) {
      if (err?.name === 'AbortError') {
        setError('Reports request timed out. Please retry.')
      } else {
        setError('Failed to load reports. Check your connection and try again.')
      }
    } finally {
      setLoading(false)
    }
  }

  async function handleDownload(report) {
    if (!report?.pdf_link) return
    const url = `${API_BASE_URL}${report.pdf_link}`
    window.open(url, '_blank', 'noopener,noreferrer')
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

  const query = search.trim().toLowerCase()
  const filtered = reports.filter(report =>
    String(report.report_id ?? '').toLowerCase().includes(query) ||
    String(report.inspection_id ?? '').toLowerCase().includes(query) ||
    String(report.title ?? '').toLowerCase().includes(query) ||
    String(report.created_by ?? '').toLowerCase().includes(query)
  )

  return (
    <div>
      <div className="page-header">
        <div>
          <div className="page-title">Reports</div>
          <div className="page-subtitle">{reports.length} reports available</div>
        </div>
        <button className="btn btn-secondary btn-sm" onClick={fetchReports}>↻ Refresh</button>
      </div>

      {error && (
        <div className="alert-banner critical" style={{ marginBottom: 16 }}>
          <span>✕</span>
          <div>
            <div className="alert-banner-title">Load Error</div>
            <div className="alert-banner-body">{error}</div>
          </div>
          <button className="btn btn-secondary btn-sm" style={{ marginLeft: 'auto' }} onClick={fetchReports}>Retry</button>
        </div>
      )}

      <div className="card">
        <div className="card-header">
          <div className="search-bar">
            <span className="search-icon">⌕</span>
            <input
              className="report-search-input"
              placeholder="Search by report id, inspection id, creator, or title…"
              value={search}
              onChange={event => setSearch(event.target.value)}
            />
          </div>
          <span style={{ fontSize: 13, color: 'var(--text-muted)' }}>{filtered.length} results</span>
        </div>

        <div className="card-body">
          <div className="card-title" style={{ marginBottom: 10 }}>Reports</div>

          {loading ? (
            <div style={{ padding: 16 }}>
              {[...Array(5)].map((_, index) => (
                <div key={index} className="skeleton skeleton-row" style={{ marginBottom: 6 }} />
              ))}
            </div>
          ) : filtered.length === 0 ? (
            <div className="empty-state">
              <div className="empty-state-icon">◻</div>
              <div className="empty-state-title">No reports found</div>
              <div className="empty-state-desc">Try searching by a different report ID, inspection ID, creator, or title</div>
            </div>
          ) : (
            <div style={{ overflowX: 'auto' }}>
              <table>
                <thead>
                  <tr>
                    <th>Inspection ID</th>
                    <th>Created At</th>
                    <th>Created By</th>
                    <th>Title</th>
                    <th>PDF</th>
                  </tr>
                </thead>
                <tbody>
                  {filtered.map(report => (
                    <tr key={`report-${report.report_id || report.inspection_id || report.created_at}`}>
                      <td className="mono" style={{ fontWeight: 500 }}>{report.inspection_id || '—'}</td>
                      <td className="mono" style={{ color: 'var(--text-secondary)', fontSize: 12 }}>{formatDate(report.created_at)}</td>
                      <td>{report.created_by || '—'}</td>
                      <td>{report.title || '—'}</td>
                      <td>
                        <button className="btn btn-sm btn-pdf" onClick={() => handleDownload(report)} disabled={!report.pdf_link}>
                          Open PDF
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}