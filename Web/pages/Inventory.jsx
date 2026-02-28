import { useEffect, useState } from 'react'
import { supabase } from '../src/supabase'

const EMPTY_FORM = { name: '', part_number: '', brand: '', quantity: '' }

export default function Inventory() {
  const [items, setItems] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [showModal, setShowModal] = useState(false)
  const [editItem, setEditItem] = useState(null)
  const [form, setForm] = useState(EMPTY_FORM)
  const [saving, setSaving] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState(null)
  const [syncStatus, setSyncStatus] = useState('synced')
  const [error, setError] = useState(null)

  useEffect(() => { fetchItems() }, [])

  async function fetchItems() {
    setLoading(true)
    setError(null)
    const { data, error } = await supabase
      .from('inventory')
      .select('*')
      .order('name', { ascending: true })
    if (error) {
      setError('Failed to load inventory. Check your connection and try again.')
    } else {
      setItems(data || [])
    }
    setLoading(false)
  }

  function openEdit(item) {
    setEditItem(item)
    setForm({ name: item.name, part_number: item.part_number || '', brand: item.brand, quantity: item.quantity })
    setShowModal(true)
  }

  async function handleSave() {
    if (!form.name || !form.part_number || form.quantity === '') return
    setSaving(true)
    setSyncStatus('pending')
    const payload = {
      name: form.name,
      part_number: form.part_number,
      brand: form.brand,
      quantity: Number(form.quantity),
    }

    if (!editItem) {
      setSaving(false)
      setSyncStatus('failed')
      return
    }

    const { error } = await supabase.from('inventory').update(payload).eq('id', editItem.id)

    if (error) {
      setSyncStatus('failed')
    } else {
      setSyncStatus('synced')
      setShowModal(false)
      fetchItems()
    }
    setSaving(false)
  }

  async function handleDelete() {
    if (!deleteTarget) return
    setSyncStatus('pending')
    const { error } = await supabase.from('inventory').delete().eq('id', deleteTarget.id)
    if (!error) {
      setSyncStatus('synced')
      fetchItems()
    } else {
      setSyncStatus('failed')
    }
    setDeleteTarget(null)
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

  const stockBadge = (qty) => {
    if (qty === 0) return <span className="badge badge-critical"><span className="badge-dot" />Out of Stock</span>
    if (qty < 10) return <span className="badge badge-warning"><span className="badge-dot" />Low Stock</span>
    return <span className="badge badge-success"><span className="badge-dot" />In Stock</span>
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
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                [...Array(6)].map((_, i) => (
                  <tr key={i}>
                    {[...Array(9)].map((_, j) => (
                      <td key={j}><div className="skeleton" style={{ height: 16, width: j === 1 || j === 2 || j === 3 ? 140 : 80 }} /></td>
                    ))}
                  </tr>
                ))
              ) : filtered.length === 0 ? (
                <tr>
                  <td colSpan={9}>
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
                    <td>{stockBadge(item.quantity)}</td>
                    <td>
                      <div style={{ display: 'flex', gap: 8 }}>
                        <button className="btn btn-secondary btn-sm" onClick={() => openEdit(item)}>Edit</button>
                        <button className="btn btn-danger btn-sm" onClick={() => setDeleteTarget(item)}>Delete</button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Add / Edit Modal */}
      {showModal && (
        <div className="modal-overlay" onClick={e => e.target === e.currentTarget && setShowModal(false)}>
          <div className="modal">
            <div className="modal-header">
              <div className="modal-title">Edit Inventory Item</div>
              <button className="modal-close" onClick={() => setShowModal(false)}>✕</button>
            </div>
            <div className="modal-body">
              <div className="form-group">
                <label>Item Name *</label>
                <input
                  placeholder="e.g. Bearing Assembly"
                  value={form.name}
                  onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
                />
              </div>
              <div className="form-group">
                <label>Part Number *</label>
                <input
                  placeholder="e.g. BRG-4820"
                  value={form.part_number}
                  onChange={e => setForm(f => ({ ...f, part_number: e.target.value }))}
                />
              </div>
              <div className="form-group">
                <label>Brand</label>
                <input
                  placeholder="e.g. SKF"
                  value={form.brand}
                  onChange={e => setForm(f => ({ ...f, brand: e.target.value }))}
                />
              </div>
              <div className="form-group">
                <label>Quantity *</label>
                <input
                  type="number"
                  min="0"
                  placeholder="0"
                  value={form.quantity}
                  onChange={e => setForm(f => ({ ...f, quantity: e.target.value }))}
                />
              </div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setShowModal(false)}>Cancel</button>
              <button className="btn btn-primary" onClick={handleSave} disabled={saving || !form.name || !form.part_number || form.quantity === ''}>
                {saving ? 'Saving…' : 'Save Changes'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Delete Confirmation Modal */}
      {deleteTarget && (
        <div className="modal-overlay">
          <div className="modal">
            <div className="modal-header">
              <div className="modal-title" style={{ color: 'var(--critical)' }}>✕ Confirm Deletion</div>
            </div>
            <div className="modal-body">
              <div className="alert-banner critical" style={{ marginBottom: 16 }}>
                <div>
                  <div className="alert-banner-title">This action cannot be undone</div>
                  <div className="alert-banner-body">
                    You are about to permanently delete <strong>{deleteTarget.name}</strong> ({deleteTarget.part_number || 'No part number'}) from inventory.
                  </div>
                </div>
              </div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setDeleteTarget(null)}>Cancel</button>
              <button className="btn btn-danger" onClick={handleDelete}>Delete Permanently</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
