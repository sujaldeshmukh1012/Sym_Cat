import { useEffect, useState } from 'react'
import { supabase } from '../src/supabase'

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

    const { data, error } = await supabase
      .from('report')
      .select('id, created_at, inspection_id, tasks, report_pdf, pdf_created')
      .order('created_at', { ascending: false })

    if (error) {
      setError('Failed to load reports. Check your connection and try again.')
    } else {
      setReports(data || [])
    }

    setLoading(false)
  }

  async function handleDownload(report) {
    if (!report?.report_pdf) return

    try {
      const response = await fetch(report.report_pdf)
      if (!response.ok) {
        throw new Error('Download failed')
      }

      const blob = await response.blob()
      const objectUrl = URL.createObjectURL(blob)
      const link = document.createElement('a')
      link.href = objectUrl
      link.download = `report-${report.id}.pdf`
      document.body.appendChild(link)
      link.click()
      link.remove()
      URL.revokeObjectURL(objectUrl)
    } catch {
      window.open(report.report_pdf, '_blank', 'noopener,noreferrer')
    }
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
    String(report.id ?? '').toLowerCase().includes(query) ||
    String(report.inspection_id ?? '').toLowerCase().includes(query) ||
    String(report.report_pdf ?? '').toLowerCase().includes(query)
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
              placeholder="Search by report id, inspection id, or PDF URL…"
              value={search}
              onChange={event => setSearch(event.target.value)}
            />
          </div>
          <span style={{ fontSize: 13, color: 'var(--text-muted)' }}>{filtered.length} results</span>
        </div>

        <div className="card-body">
          <div className="card-title" style={{ marginBottom: 10 }}>Reports Gallery</div>

          {loading ? (
            <div className="grid-3">
              {[...Array(6)].map((_, index) => (
                <div key={index} className="report-card">
                  <div className="skeleton" style={{ height: 12, width: 90, marginBottom: 10 }} />
                  <div className="skeleton" style={{ height: 18, width: '60%', marginBottom: 8 }} />
                  <div className="skeleton" style={{ height: 22, width: '75%', marginBottom: 8 }} />
                  <div className="skeleton" style={{ height: 14, width: '100%', marginBottom: 6 }} />
                  <div className="skeleton" style={{ height: 14, width: '85%', marginBottom: 14 }} />
                  <div className="report-card-actions">
                    <div className="skeleton" style={{ height: 36, width: 120 }} />
                  </div>
                </div>
              ))}
            </div>
          ) : filtered.length === 0 ? (
            <div className="empty-state">
              <div className="empty-state-icon">◻</div>
              <div className="empty-state-title">No reports found</div>
              <div className="empty-state-desc">Try searching by a different report ID, inspection ID, or URL</div>
            </div>
          ) : (
            <div className="grid-3">
              {filtered.map(report => (
                <div key={`report-${report.id}`} className="report-card">
                  <div className="mono report-card-id">ID: {report.id ?? '—'}</div>
                  <div className="mono report-card-id" style={{ marginTop: -2 }}>Inspection: {report.inspection_id || '—'}</div>
                  <div className="report-card-title">Report {report.id}</div>
                  <div className="mono" style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 8 }}>
                    Created: {formatDate(report.created_at)}
                  </div>
                  <div className="mono" style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 8 }}>
                    PDF Created: {formatDate(report.pdf_created)}
                  </div>
                  <div className="report-card-url">
                    {report.report_pdf || 'No report PDF URL available'}
                  </div>
                  <div className="report-card-actions">
                    <button className="btn btn-sm btn-pdf" onClick={() => handleDownload(report)} disabled={!report.report_pdf}>
                      Download PDF
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}