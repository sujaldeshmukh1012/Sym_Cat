import { useEffect, useState } from 'react'
import { supabase } from '../src/supabase'

export default function OrderCart() {
  const [orders, setOrders] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [syncStatus, setSyncStatus] = useState('synced')
  const [error, setError] = useState(null)

  useEffect(() => {
    fetchOrders()
  }, [])

  async function fetchOrders() {
    setLoading(true)
    setError(null)
    setSyncStatus('pending')

    const ordersRes = await supabase
      .from('order_cart')
      .select('id, created_at, inspection_id, parts, quantity, urgency, status')
      .order('created_at', { ascending: false })

    if (ordersRes.error) {
      setError('Failed to load order cart. Check your connection and try again.')
      setSyncStatus('failed')
    } else {
      setOrders(ordersRes.data || [])
      setSyncStatus('synced')
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

  function normalizeStatus(value) {
    return String(value ?? '').replace(/^"|"$/g, '').trim()
  }

  function getStatusClass(statusValue) {
    const normalized = normalizeStatus(statusValue).toLowerCase()
    if (normalized === 'completed' || normalized === 'approved' || normalized === 'fulfilled') return 'badge-success'
    if (normalized === 'pending' || normalized === 'in_progress' || normalized === 'in progress') return 'badge-warning'
    if (normalized === 'cancelled' || normalized === 'rejected' || normalized === 'failed') return 'badge-critical'
    return 'badge-info'
  }

  const query = search.trim().toLowerCase()
  const filtered = orders.filter(order =>
    String(order.id ?? '').toLowerCase().includes(query) ||
    String(order.inspection_id ?? '').toLowerCase().includes(query) ||
    String(order.parts ?? '').toLowerCase().includes(query) ||
    String(order.quantity ?? '').toLowerCase().includes(query) ||
    String(order.urgency ?? '').toLowerCase().includes(query) ||
    normalizeStatus(order.status).toLowerCase().includes(query)
  )

  return (
    <div className="order-cart-shell">
      <div className="page-header">
        <div>
          <div className="page-title">Order Cart</div>
          <div className="page-subtitle">{orders.length} total order cart entries</div>
        </div>
        <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
          <button className="btn btn-secondary btn-sm" onClick={fetchOrders}>↻ Refresh</button>
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
          <button className="btn btn-secondary btn-sm" style={{ marginLeft: 'auto' }} onClick={fetchOrders}>Retry</button>
        </div>
      )}

      <div className="card">
        <div className="card-header">
          <div className="search-bar">
            <span className="search-icon">⌕</span>
            <input
              placeholder="Search by order id, inspection id, part id, quantity, urgency, or status…"
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
                <th style={{ textAlign: 'center' }}>Order ID</th>
                <th style={{ textAlign: 'center' }}>Inspection ID</th>
                <th style={{ textAlign: 'center' }}>Part ID</th>
                <th style={{ textAlign: 'center' }}>Quantity</th>
                <th>Urgency</th>
                <th>Status</th>
                <th>Created At</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                [...Array(6)].map((_, i) => (
                  <tr key={i}>
                    {[...Array(7)].map((_, j) => (
                      <td key={j}><div className="skeleton" style={{ height: 16, width: 110 }} /></td>
                    ))}
                  </tr>
                ))
              ) : filtered.length === 0 ? (
                <tr>
                  <td colSpan={7}>
                    <div className="empty-state">
                      <div className="empty-state-icon">🛒</div>
                      <div className="empty-state-title">No order cart entries found</div>
                      <div className="empty-state-desc">Orders will appear here once created</div>
                    </div>
                  </td>
                </tr>
              ) : (
                filtered.map(order => (
                  <tr key={order.id}>
                    <td className="mono" style={{ color: 'var(--text-secondary)', textAlign: 'center' }}>{order.id ?? '—'}</td>
                    <td className="mono" style={{ color: 'var(--text-secondary)', textAlign: 'center' }}>{order.inspection_id ?? '—'}</td>
                    <td className="mono" style={{ color: 'var(--text-secondary)', textAlign: 'center' }}>{order.parts ?? '—'}</td>
                    <td className="mono" style={{ textAlign: 'center' }}>{order.quantity ?? '—'}</td>
                    <td>
                      <span className={`badge ${order.urgency ? 'badge-critical' : 'badge-info'}`}>
                        <span className="badge-dot" /> {order.urgency ? 'Urgent' : 'Normal'}
                      </span>
                    </td>
                    <td>
                      <span className={`badge ${getStatusClass(order.status)}`}>
                        <span className="badge-dot" /> {normalizeStatus(order.status) || '—'}
                      </span>
                    </td>
                    <td className="mono" style={{ fontSize: 12, color: 'var(--text-secondary)' }}>{formatDate(order.created_at)}</td>
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