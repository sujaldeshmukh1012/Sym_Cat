import { useEffect, useState } from 'react'
import { supabase } from '../src/supabase'

export default function Inventory() {
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [currentPage, setCurrentPage] = useState(1)
  const [syncStatus, setSyncStatus] = useState('synced')
  const [error, setError] = useState(null)
  const pageSize = 10

  useEffect(() => { fetchItems() }, [])

  async function fetchItems() {
    setLoading(true)
    setError(null)
    const inventoryRes = await supabase
      .from('inventory')
      .select('id, created_at, part_number, part_name, component_tag, stock_qty, unit_price, fleet_serial')
      .order('created_at', { ascending: false })

    if (inventoryRes.error) {
      setError('Failed to load inventory. Check your connection and try again.')
    } else {
      setItems(inventoryRes.data || [])
    }

    setLoading(false)
  }

  const normalizedSearch = search.trim().toLowerCase()
  const isNumericSearch = /^\d+$/.test(normalizedSearch)
  const hasExactFleetMatch = isNumericSearch && items.some(item => String(item.fleet_serial ?? '') === normalizedSearch)

  const filtered = items.filter(item => {
    if (!normalizedSearch) return true

    if (hasExactFleetMatch) {
      return String(item.fleet_serial ?? '') === normalizedSearch
    }

    return (
      String(item.fleet_serial ?? '').toLowerCase().includes(normalizedSearch) ||
      String(item.part_number ?? '').toLowerCase().includes(normalizedSearch) ||
      String(item.part_name ?? '').toLowerCase().includes(normalizedSearch) ||
      String(item.component_tag ?? '').toLowerCase().includes(normalizedSearch)
    )
  })

  const totalPages = Math.max(1, Math.ceil(filtered.length / pageSize))
  const effectivePage = Math.min(currentPage, totalPages)
  const startIndex = (effectivePage - 1) * pageSize
  const endIndex = startIndex + pageSize
  const paginatedItems = filtered.slice(startIndex, endIndex)

  const showStart = filtered.length === 0 ? 0 : startIndex + 1
  const showEnd = filtered.length === 0 ? 0 : Math.min(endIndex, filtered.length)

  useEffect(() => {
    setCurrentPage(1)
  }, [normalizedSearch, hasExactFleetMatch])

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

  function formatCreatedAt(value) {
    if (!value) return '—'
    return new Date(value).toLocaleString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    })
  }

  function formatCurrency(value) {
    if (value === null || value === undefined || value === '') return '—'
    const numeric = Number(value)
    if (Number.isNaN(numeric)) return '—'
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      maximumFractionDigits: 0,
    }).format(numeric)
  }

  function getStockState(value) {
    const qty = Number(value)
    if (Number.isNaN(qty)) return { label: 'Unknown', className: 'badge-neutral' }
    if (qty === 0) return { label: 'Out of Stock', className: 'badge-critical' }
    if (qty <= 5) return { label: 'Low Stock', className: 'badge-warning' }
    return { label: 'In Stock', className: 'badge-success' }
  }

  return (
    <div className="inventory-shell">
      <div className="page-header">
        <div>
          <div className="page-title">Inventory</div>
          <div className="page-subtitle">{items.length} total items tracked</div>
        </div>
        <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
          <button className="btn btn-secondary btn-sm" onClick={fetchItems}>↻ Refresh</button>
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
          <button className="btn btn-secondary btn-sm" style={{ marginLeft: 'auto' }} onClick={fetchItems}>Retry</button>
        </div>
      )}

      <div className="card">
        <div className="card-header">
          <div className="search-bar">
            <span className="search-icon">⌕</span>
            <input
              className="report-search-input"
              placeholder="Search by fleet serial, part number, part name, or component tag…"
              value={search}
              onChange={e => setSearch(e.target.value)}
            />
          </div>
          <span className="inventory-results-count">{filtered.length} results</span>
        </div>

        <div className="table-wrapper" style={{ borderRadius: 0, border: 'none' }}>
          <table>
            <thead>
              <tr>
                <th style={{ textAlign: 'center' }}>Fleet Serial</th>
                <th style={{ textAlign: 'center' }}>Part Number</th>
                <th>Part Name</th>
                <th>Component Tag</th>
                <th style={{ textAlign: 'center' }}>Stock Qty</th>
                <th>Unit Price</th>
                <th>Status</th>
                <th>Created At</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                [...Array(6)].map((_, i) => (
                  <tr key={i}>
                    {[...Array(8)].map((_, j) => (
                      <td key={j}><div className="skeleton" style={{ height: 16, width: j >= 1 && j <= 4 ? 130 : 90 }} /></td>
                    ))}
                  </tr>
                ))
              ) : filtered.length === 0 ? (
                <tr>
                  <td colSpan={8}>
                    <div className="empty-state">
                      <div className="empty-state-icon">▦</div>
                      <div className="empty-state-title">No inventory items found</div>
                      <div className="empty-state-desc">No inventory records are currently available</div>
                    </div>
                  </td>
                </tr>
              ) : (
                paginatedItems.map(item => (
                  <tr key={item.id}>
                    <td className="mono" style={{ color: 'var(--text-muted)', fontSize: 12, textAlign: 'center' }}>{item.fleet_serial ?? '—'}</td>
                    <td className="mono" style={{ color: 'var(--text-secondary)', textAlign: 'center' }}>{item.part_number || '—'}</td>
                    <td style={{ fontWeight: 600 }}>{item.part_name || '—'}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{item.component_tag || '—'}</td>
                    <td className="mono" style={{ textAlign: 'center' }}>{item.stock_qty ?? '—'}</td>
                    <td className="mono">{formatCurrency(item.unit_price)}</td>
                    <td>
                      <span className={`badge ${getStockState(item.stock_qty).className}`}>
                        <span className="badge-dot" /> {getStockState(item.stock_qty).label}
                      </span>
                    </td>
                    <td className="mono" style={{ fontSize: 12, color: 'var(--text-secondary)' }}>{formatCreatedAt(item.created_at)}</td>
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
