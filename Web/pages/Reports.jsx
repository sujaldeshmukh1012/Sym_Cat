import { useEffect, useState } from 'react'

const API_BASE_URL = (import.meta.env.VITE_API_BASE_URL || 'http://localhost:8000').replace(/\/$/, '')

export default function Reports() {
  const [reports, setReports] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [currentPage, setCurrentPage] = useState(1)
  const [syncStatus, setSyncStatus] = useState('synced')
  const [error, setError] = useState(null)
  const pageSize = 10

  useEffect(() => {
    fetchReports()
  }, [])

  async function fetchReports() {
    setLoading(true)
    setError(null)
    setSyncStatus('pending')

    try {
      const controller = new AbortController()
      const timeoutId = window.setTimeout(() => controller.abort(), 10000)
      const response = await fetch(`${API_BASE_URL}/reports`, { signal: controller.signal })
      window.clearTimeout(timeoutId)

      if (!response.ok) throw new Error(`Request failed (${response.status})`)
      const payload = await response.json()
      setReports(payload.data || [])
      setSyncStatus('synced')
    } catch (err) {
      if (err?.name === 'AbortError') {
        setError('Reports request timed out. Please retry.')
      } else {
        setError('Failed to load reports. Check your connection and try again.')
      }
      setSyncStatus('failed')
    } finally {
      setLoading(false)
    }
  }

  function handlePreview(report) {
    if (!report) return

    let url = ''
    if (report.pdf_link) {
      const separator = report.pdf_link.includes('?') ? '&' : '?'
      url = `${API_BASE_URL}${report.pdf_link}${separator}download=false`
    } else if (report.report_pdf && String(report.report_pdf).startsWith('http')) {
      url = String(report.report_pdf)
    }

    if (!url) return
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

  function hasPreview(report) {
    if (!report) return false
    return Boolean(report.pdf_link) || (report.report_pdf && String(report.report_pdf).startsWith('http'))
  }

  const query = search.trim().toLowerCase()
  const filtered = reports.filter(report =>
    String(report.report_id ?? '').toLowerCase().includes(query) ||
    String(report.inspection_id ?? '').toLowerCase().includes(query) ||
    String(report.title ?? '').toLowerCase().includes(query) ||
    String(report.created_by ?? '').toLowerCase().includes(query)
  )

  const totalPages = Math.max(1, Math.ceil(filtered.length / pageSize))
  const effectivePage = Math.min(currentPage, totalPages)
  const startIndex = (effectivePage - 1) * pageSize
  const endIndex = startIndex + pageSize
  const paginatedReports = filtered.slice(startIndex, endIndex)

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

  return (
    <div>
      <div className="page-header">
        <div>
          <div className="page-title">Reports</div>
          <div className="page-subtitle">{reports.length} reports available</div>
        </div>
        <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
          <button className="btn btn-secondary btn-sm" onClick={fetchReports}>↻ Refresh</button>
          <span className={`sync-pill ${syncStatus}`}>
            <span className="badge-dot" />
            {syncStatus === 'synced' ? 'Synced' : syncStatus === 'pending' ? 'Loading…' : 'Sync Failed'}
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
            <div className="table-wrapper" style={{ borderRadius: 0, border: 'none' }}>
              <table>
                <thead>
                  <tr>
                    <th style={{ textAlign: 'center' }}>Inspection ID</th>
                    <th style={{ textAlign: 'center' }}>Created At</th>
                    <th style={{ textAlign: 'center' }}>Created By</th>
                    <th style={{ textAlign: 'center' }}>Title</th>
                    <th style={{ textAlign: 'center' }}>Status</th>
                    <th style={{ textAlign: 'center' }}>PDF</th>
                  </tr>
                </thead>
                <tbody>
                  {paginatedReports.map(report => (
                    <tr key={`report-${report.report_id || report.inspection_id || report.created_at}`}>
                      <td className="mono" style={{ fontWeight: 500, textAlign: 'center' }}>{report.inspection_id || '—'}</td>
                      <td className="mono" style={{ color: 'var(--text-secondary)', fontSize: 12 }}>{formatDate(report.created_at)}</td>
                      <td style={{ textAlign: 'center' }}>{report.created_by || '—'}</td>
                      <td>
                        <div style={{ fontWeight: 600 }}>{report.title || '—'}</div>
                        <div className="mono" style={{ marginTop: 3, color: 'var(--text-muted)', fontSize: 11 }}>
                          {report.report_id ? `Report #${report.report_id}` : 'No report ID'}
                        </div>
                      </td>
                      <td>
                        {hasPreview(report) ? (
                          <span className="badge badge-success">
                            <span className="badge-dot" /> Ready
                          </span>
                        ) : (
                          <span className="badge badge-warning">
                            <span className="badge-dot" /> Pending
                          </span>
                        )}
                      </td>
                      <td>
                        <button className="btn btn-sm btn-pdf" onClick={() => handlePreview(report)} disabled={!hasPreview(report)}>
                          Preview Report
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          {!loading && filtered.length > 0 && (
            <div className="inventory-pagination" style={{ marginTop: 12 }}>
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
    </div>
  )
}