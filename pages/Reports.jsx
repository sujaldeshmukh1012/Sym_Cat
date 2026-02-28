import { useEffect, useState } from 'react'
import { supabase } from '../src/supabase'

const TEMPLATE_CARDS = [
  {
    id: 'T-1001',
    title: 'Hydraulic Pressure Inspection',
    url: 'https://example.com/reports/hydraulic-pressure-inspection.pdf',
  },
  {
    id: 'T-1002',
    title: 'Engine Performance Audit',
    url: 'https://example.com/reports/engine-performance-audit.pdf',
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
      .select('id, url')
      .order('id', { ascending: false })

    if (error) {
      setError('Failed to load reports. Check your connection and try again.')
    } else {
      setReports(data || [])
    }

    setLoading(false)
  }

  async function handleDownload(report) {
    if (!report?.url) return

    try {
      const response = await fetch(report.url)
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
      window.open(report.url, '_blank', 'noopener,noreferrer')
    }
  }

  function extractTitle(report) {
    if (!report?.url) return `Report ${report?.id ?? ''}`.trim()

    try {
      const pathname = new URL(report.url).pathname
      const fileName = pathname.split('/').pop() || ''
      const title = fileName
        .replace(/\.pdf$/i, '')
        .replace(/[-_]+/g, ' ')
        .trim()
      return title
        ? title.replace(/\b\w/g, char => char.toUpperCase())
        : `Report ${report.id}`
    } catch {
      return `Report ${report?.id ?? ''}`.trim()
    }
  }

  const query = search.trim().toLowerCase()
  const reportsWithTitle = reports.map(report => ({
    ...report,
    title: extractTitle(report),
  }))
  const filteredTemplates = TEMPLATE_CARDS.filter(report =>
    String(report.id ?? '').toLowerCase().includes(query) ||
    String(report.title ?? '').toLowerCase().includes(query)
  )
  const filteredLiveReports = reportsWithTitle.filter(report =>
    String(report.id ?? '').toLowerCase().includes(query) ||
    String(report.title ?? '').toLowerCase().includes(query)
  )
  const allFilteredCards = [
    ...filteredTemplates.map(card => ({ ...card, isTemplate: true })),
    ...filteredLiveReports.map(card => ({ ...card, isTemplate: false })),
  ]
  const totalResults = allFilteredCards.length

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
              placeholder="Search by report id or title…"
              value={search}
              onChange={event => setSearch(event.target.value)}
            />
          </div>
          <span style={{ fontSize: 13, color: 'var(--text-muted)' }}>{totalResults} results</span>
        </div>

        <div className="card-body">
          <div className="card-title" style={{ marginBottom: 10 }}>Reports Gallery</div>

          {loading ? (
            <div className="grid-3">
              {[...Array(6)].map((_, index) => (
                <div key={index} className="report-card">
                  <div className="skeleton" style={{ height: 12, width: 90, marginBottom: 10 }} />
                  <div className="skeleton" style={{ height: 22, width: '75%', marginBottom: 8 }} />
                  <div className="skeleton" style={{ height: 14, width: '100%', marginBottom: 6 }} />
                  <div className="skeleton" style={{ height: 14, width: '85%', marginBottom: 14 }} />
                  <div className="report-card-actions">
                    <div className="skeleton" style={{ height: 36, width: 120 }} />
                  </div>
                </div>
              ))}
            </div>
          ) : allFilteredCards.length === 0 ? (
            <div className="empty-state">
              <div className="empty-state-icon">◻</div>
              <div className="empty-state-title">No reports found</div>
              <div className="empty-state-desc">Try searching by a different ID or title</div>
            </div>
          ) : (
            <div className="grid-3">
              {allFilteredCards.map(report => (
                <div key={`${report.isTemplate ? 'template' : 'live'}-${report.id}`} className={`report-card${report.isTemplate ? ' report-card-template' : ''}`}>
                  <div className="mono report-card-id">ID: {report.id ?? '—'}</div>
                  {report.isTemplate && <div className="report-card-top" style={{ marginBottom: 8 }}><span className="badge badge-info">Template</span></div>}
                  <div className="report-card-title">{report.title}</div>
                  <div className="report-card-url">
                    {report.url || 'No URL available'}
                  </div>
                  <div className="report-card-actions">
                    <button className="btn btn-sm btn-pdf" onClick={() => handleDownload(report)} disabled={!report.url}>
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