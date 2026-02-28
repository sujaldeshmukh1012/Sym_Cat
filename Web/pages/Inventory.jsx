import { useEffect, useState } from 'react'
import { supabase } from '../src/supabase'

export default function Inventory() {
  const [items, setItems] = useState([])
  const [latestStatusByInventoryId, setLatestStatusByInventoryId] = useState({})
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [syncStatus, setSyncStatus] = useState('synced')
  const [error, setError] = useState(null)

  useEffect(() => { fetchItems() }, [])

  async function fetchItems() {
    setLoading(true)
    setError(null)
    const [inventoryRes, logsRes] = await Promise.all([
      supabase
        .from('inventory')
        .select('*')
        .order('name', { ascending: true }),
      supabase
        .from('logs')
        .select('inventory_id, status, inspected_at, created_at')
        .order('inspected_at', { ascending: false }),
    ])

    if (inventoryRes.error) {
      setError('Failed to load inventory. Check your connection and try again.')
    } else {
      setItems(inventoryRes.data || [])
    }

    if (!logsRes.error && Array.isArray(logsRes.data)) {
      const statusMap = {}
      for (const log of logsRes.data) {
        const key = String(log.inventory_id ?? '')
        if (!key || statusMap[key]) continue
        statusMap[key] = log.status
      }
      setLatestStatusByInventoryId(statusMap)
    } else {
      setLatestStatusByInventoryId({})
    }

    setLoading(false)
  }

  const filtered = items.filter(i =>
    i.name?.toLowerCase().includes(search.toLowerCase()) ||
    i.part_number?.toLowerCase().includes(search.toLowerCase()) ||
    i.user_id?.toLowerCase().includes(search.toLowerCase()) ||
    i.brand?.toLowerCase().includes(search.toLowerCase())
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

  const statusBadgeFromLog = (inventoryId) => {
    const status = latestStatusByInventoryId[String(inventoryId)]
    if (!status) return <span className="badge badge-neutral"><span className="badge-dot" />No Log</span>

    const normalized = String(status).toLowerCase()
    if (normalized === 'critical') {
      return <span className="badge badge-critical"><span className="badge-dot" />{status}</span>
    }
    if (normalized === 'moderate') {
      return <span className="badge badge-warning"><span className="badge-dot" />{status}</span>
    }
    if (normalized === 'low') {
      return <span className="badge badge-success"><span className="badge-dot" />{status}</span>
    }

    return <span className="badge badge-info"><span className="badge-dot" />{status}</span>
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
              placeholder="Search by id, user, name, part number, or brand…"
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
                <th>User ID</th>
                <th>Item Name</th>
                <th>Part Number</th>
                <th>Brand</th>
                <th>Quantity</th>
                <th>Created At</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                [...Array(6)].map((_, i) => (
                  <tr key={i}>
                    {[...Array(8)].map((_, j) => (
                      <td key={j}><div className="skeleton" style={{ height: 16, width: j === 1 || j === 2 || j === 3 ? 140 : 80 }} /></td>
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
                    <td className="mono" style={{ color: 'var(--text-muted)', fontSize: 12 }}>{item.user_id || '—'}</td>
                    <td style={{ fontWeight: 600 }}>{item.name}</td>
                    <td className="mono" style={{ color: 'var(--text-secondary)' }}>{item.part_number || '—'}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{item.brand || '—'}</td>
                    <td className="mono">{item.quantity ?? '—'}</td>
                    <td className="mono" style={{ fontSize: 12, color: 'var(--text-secondary)' }}>{formatCreatedAt(item.created_at)}</td>
                    <td>{statusBadgeFromLog(item.id)}</td>
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
