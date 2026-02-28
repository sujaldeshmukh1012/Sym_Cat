import { useEffect, useState } from 'react'
import { supabase } from '../src/supabase'

const EMPTY_FORM = { name: '', usedWhere: '' }

export default function MachineParts() {
  const [parts, setParts] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [showModal, setShowModal] = useState(false)
  const [editPart, setEditPart] = useState(null)
  const [form, setForm] = useState(EMPTY_FORM)
  const [saving, setSaving] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState(null)
  const [syncStatus, setSyncStatus] = useState('synced')
  const [error, setError] = useState(null)

  useEffect(() => { fetchParts() }, [])

  async function fetchParts() {
    setLoading(true)
    setError(null)
    const { data, error } = await supabase
      .from('machine_parts')
      .select('*')
      .order('name', { ascending: true })
    if (error) {
      setError('Failed to load machine parts. Check your connection and try again.')
    } else {
      setParts(data || [])
    }
    setLoading(false)
  }

  function openAdd() {
    setEditPart(null)
    setForm(EMPTY_FORM)
    setShowModal(true)
  }

  function openEdit(part) {
    setEditPart(part)
    setForm({ name: part.name, usedWhere: part.usedWhere || '' })
    setShowModal(true)
  }

  async function handleSave() {
    if (!form.name) return
    setSaving(true)
    setSyncStatus('pending')

    let error
    if (editPart) {
      ({ error } = await supabase.from('machine_parts').update({ name: form.name, usedWhere: form.usedWhere }).eq('id', editPart.id))
    } else {
      ({ error } = await supabase.from('machine_parts').insert({ name: form.name, usedWhere: form.usedWhere }))
    }

    if (error) {
      setSyncStatus('failed')
    } else {
      setSyncStatus('synced')
      setShowModal(false)
      fetchParts()
    }
    setSaving(false)
  }

  async function handleDelete() {
    if (!deleteTarget) return
    setSyncStatus('pending')
    const { error } = await supabase.from('machine_parts').delete().eq('id', deleteTarget.id)
    if (!error) {
      setSyncStatus('synced')
      fetchParts()
    } else {
      setSyncStatus('failed')
    }
    setDeleteTarget(null)
  }

  const filtered = parts.filter(p =>
    p.name?.toLowerCase().includes(search.toLowerCase()) ||
    p.usedWhere?.toLowerCase().includes(search.toLowerCase())
  )

  return (
    <div>
      <div className="page-header">
        <div>
          <div className="page-title">Machine Parts</div>
          <div className="page-subtitle">{parts.length} parts tracked across all machines</div>
        </div>
        <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
          <span className={`sync-pill ${syncStatus}`}>
            <span className="badge-dot" />
            {syncStatus === 'synced' ? 'Synced' : syncStatus === 'pending' ? 'Saving…' : 'Sync Failed'}
          </span>
          <button className="btn btn-primary" onClick={openAdd}>+ Add Part</button>
        </div>
      </div>

      {error && (
        <div className="alert-banner critical" style={{ marginBottom: 16 }}>
          <span>✕</span>
          <div>
            <div className="alert-banner-title">Load Error</div>
            <div className="alert-banner-body">{error}</div>
          </div>
          <button className="btn btn-secondary btn-sm" style={{ marginLeft: 'auto' }} onClick={fetchParts}>Retry</button>
        </div>
      )}

      <div className="card">
        <div className="card-header">
          <div className="search-bar">
            <span className="search-icon">⌕</span>
            <input
              placeholder="Search by name or location…"
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
                <th>Part Name</th>
                <th>Used Where</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                [...Array(6)].map((_, i) => (
                  <tr key={i}>
                    {[...Array(4)].map((_, j) => (
                      <td key={j}><div className="skeleton" style={{ height: 16, width: j === 1 ? 160 : 100 }} /></td>
                    ))}
                  </tr>
                ))
              ) : filtered.length === 0 ? (
                <tr>
                  <td colSpan={4}>
                    <div className="empty-state">
                      <div className="empty-state-icon">⚙</div>
                      <div className="empty-state-title">No machine parts found</div>
                      <div className="empty-state-desc">Add parts to track them here</div>
                    </div>
                  </td>
                </tr>
              ) : (
                filtered.map(part => (
                  <tr key={part.id}>
                    <td className="mono" style={{ color: 'var(--text-muted)', fontSize: 12 }}>{part.id}</td>
                    <td style={{ fontWeight: 600 }}>{part.name}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{part.usedWhere || '—'}</td>
                    <td>
                      <div style={{ display: 'flex', gap: 8 }}>
                        <button className="btn btn-secondary btn-sm" onClick={() => openEdit(part)}>Edit</button>
                        <button className="btn btn-danger btn-sm" onClick={() => setDeleteTarget(part)}>Delete</button>
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
              <div className="modal-title">{editPart ? 'Edit Machine Part' : 'Add Machine Part'}</div>
              <button className="modal-close" onClick={() => setShowModal(false)}>✕</button>
            </div>
            <div className="modal-body">
              <div className="form-group">
                <label>Part Name *</label>
                <input
                  placeholder="e.g. Drive Shaft"
                  value={form.name}
                  onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
                />
              </div>
              <div className="form-group">
                <label>Used Where</label>
                <input
                  placeholder="e.g. Conveyor Belt Assembly, Zone 3"
                  value={form.usedWhere}
                  onChange={e => setForm(f => ({ ...f, usedWhere: e.target.value }))}
                />
              </div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setShowModal(false)}>Cancel</button>
              <button className="btn btn-primary" onClick={handleSave} disabled={saving || !form.name}>
                {saving ? 'Saving…' : editPart ? 'Save Changes' : 'Add Part'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Delete Confirmation */}
      {deleteTarget && (
        <div className="modal-overlay">
          <div className="modal">
            <div className="modal-header">
              <div className="modal-title" style={{ color: 'var(--critical)' }}>✕ Confirm Deletion</div>
            </div>
            <div className="modal-body">
              <div className="alert-banner critical">
                <div>
                  <div className="alert-banner-title">This action cannot be undone</div>
                  <div className="alert-banner-body">
                    You are about to permanently delete <strong>{deleteTarget.name}</strong> from machine parts.
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
