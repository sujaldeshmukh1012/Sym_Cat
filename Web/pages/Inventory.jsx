import { useEffect, useState } from 'react'
import { supabase } from '../src/supabase'

export default function Inventory() {
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [syncStatus, setSyncStatus] = useState('synced')
  const [error, setError] = useState(null)

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

  const filtered = items.filter(i =>
    String(i.id ?? '').toLowerCase().includes(search.toLowerCase()) ||
    String(i.fleet_serial ?? '').toLowerCase().includes(search.toLowerCase()) ||
    String(i.part_number ?? '').toLowerCase().includes(search.toLowerCase()) ||
    String(i.part_name ?? '').toLowerCase().includes(search.toLowerCase()) ||
    String(i.component_tag ?? '').toLowerCase().includes(search.toLowerCase())
  )

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

  return (
    <div>
      <div className="page-header">
        <div>
          <div className="page-title">Inventory</div>
          <div className="page-subtitle">{items.length} total items tracked</div>
        </div>
        <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
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
              placeholder="Search by id, fleet serial, part number, part name, or component tag…"
              value={search}
              onChange={e => setSearch(e.target.value)}
            />
          </div>
          <span style={{ fontSize: 13, color: 'var(--text-muted)' }}>{filtered.length} results</span>
        </div>

        <div className="table-wrapper" style={{ borderRadius: 0, border: 'none' }}>
          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>Fleet Serial</th>
                <th>Part Number</th>
                <th>Part Name</th>
                <th>Component Tag</th>
                <th>Stock Qty</th>
                <th>Unit Price</th>
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
                filtered.map(item => (
                  <tr key={item.id}>
                    <td className="mono" style={{ color: 'var(--text-muted)', fontSize: 12 }}>{item.id}</td>
                    <td className="mono" style={{ color: 'var(--text-muted)', fontSize: 12 }}>{item.fleet_serial ?? '—'}</td>
                    <td className="mono" style={{ color: 'var(--text-secondary)' }}>{item.part_number || '—'}</td>
                    <td style={{ fontWeight: 600 }}>{item.part_name || '—'}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{item.component_tag || '—'}</td>
                    <td className="mono">{item.stock_qty ?? '—'}</td>
                    <td className="mono">{item.unit_price ?? '—'}</td>
                    <td className="mono" style={{ fontSize: 12, color: 'var(--text-secondary)' }}>{formatCreatedAt(item.created_at)}</td>
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
