import { useEffect, useState } from 'react'
import { supabase } from '../src/supabase'

const TEMPLATE_CARDS = [
  {
    id: 'T-1001',
    user_id: 'template-user',
    title: 'Hydraulic Pressure Inspection',
    public_url: 'https://example.com/reports/hydraulic-pressure-inspection.pdf',
    created_at: '2026-02-01T10:15:00.000Z',
    isTemplate: true,
  },
  {
    id: 'T-1002',
    user_id: 'template-user',
    title: 'Engine Performance Audit',
    public_url: 'https://example.com/reports/engine-performance-audit.pdf',
    created_at: '2026-02-10T14:40:00.000Z',
    isTemplate: true,
  },
]

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
      .from('reports')
      .select('id, user_id, title, public_url, created_at')
      .order('created_at', { ascending: false })

    if (error) {
      setError('Failed to load reports. Check your connection and try again.')
    } else {
      setReports(data || [])
    }

    setLoading(false)
  }

  async function handleDownload(report) {
    if (!report?.public_url) return

    try {
      const response = await fetch(report.public_url)
      if (!response.ok) {
        throw new Error('Download failed')
      }

      const blob = await response.blob()
      const objectUrl = URL.createObjectURL(blob)
      const link = document.createElement('a')
      link.href = objectUrl
      link.download = `${report.title || `report-${report.id}`}.pdf`
      document.body.appendChild(link)
      link.click()
      link.remove()
      URL.revokeObjectURL(objectUrl)
    } catch {
      window.open(report.public_url, '_blank', 'noopener,noreferrer')
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
  const liveReports = reports.map(report => ({ ...report, isTemplate: false }))
  const allReports = [...TEMPLATE_CARDS, ...liveReports]
  const filtered = allReports.filter(report =>
    String(report.id ?? '').toLowerCase().includes(query) ||
    String(report.user_id ?? '').toLowerCase().includes(query) ||
    String(report.title ?? '').toLowerCase().includes(query)
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
              placeholder="Search by report id, user id, or title…"
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
              <div className="empty-state-desc">Try searching by a different ID, user ID, or title</div>
            </div>
          ) : (
            <div className="grid-3">
              {filtered.map(report => (
                <div key={`${report.isTemplate ? 'template' : 'live'}-${report.id}`} className={`report-card${report.isTemplate ? ' report-card-template' : ''}`}>
                  <div className="mono report-card-id">ID: {report.id ?? '—'}</div>
                  <div className="mono report-card-id" style={{ marginTop: -2 }}>User: {report.user_id || '—'}</div>
                  {report.isTemplate && (
                    <div className="report-card-top" style={{ marginBottom: 8 }}>
                      <span className="badge badge-info">Template</span>
                    </div>
                  )}
                  <div className="report-card-title">{report.title || `Report ${report.id}`}</div>
                  <div className="mono" style={{ fontSize: 12, color: 'var(--text-muted)', marginBottom: 8 }}>
                    Created: {formatDate(report.created_at)}
                  </div>
                  <div className="report-card-url">
                    {report.public_url || 'No public URL available'}
                  </div>
                  <div className="report-card-actions">
                    <button className="btn btn-sm btn-pdf" onClick={() => handleDownload(report)} disabled={!report.public_url}>
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