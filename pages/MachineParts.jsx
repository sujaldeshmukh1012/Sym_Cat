import { useEffect, useState } from 'react'
import { supabase } from '../src/supabase'

const EMPTY_FORM = {
  name: '',
  location: '',
  usecase: '',
  details: '',
  defect_parts: '',
  parts_changed: '',
  changed_at: '',
}

export default function MachineParts() {
  const [specs, setSpecs] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [showModal, setShowModal] = useState(false)
  const [editSpec, setEditSpec] = useState(null)
  const [form, setForm] = useState(EMPTY_FORM)
  const [saving, setSaving] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState(null)
  const [syncStatus, setSyncStatus] = useState('synced')
  const [error, setError] = useState(null)

  useEffect(() => { fetchSpecs() }, [])

  async function fetchSpecs() {
    setLoading(true)
    setError(null)
    const { data, error } = await supabase
      .from('machine_specs')
      .select('*')
      .order('created_at', { ascending: false })

    if (error) {
      setError('Failed to load machine specs. Check your connection and try again.')
    } else {
      setSpecs(data || [])
    }
    setLoading(false)
  }

  function toDateTimeLocal(value) {
    if (!value) return ''
    const date = new Date(value)
    const timezoneOffset = date.getTimezoneOffset() * 60000
    return new Date(date.getTime() - timezoneOffset).toISOString().slice(0, 16)
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

  function openAdd() {
    setEditSpec(null)
    setForm(EMPTY_FORM)
    setShowModal(true)
  }

  function openEdit(spec) {
    setEditSpec(spec)
    setForm({
      name: spec.name || '',
      location: spec.location || '',
      usecase: spec.usecase || '',
      details: spec.details || '',
      defect_parts: spec.defect_parts || '',
      parts_changed: spec.parts_changed || '',
      changed_at: toDateTimeLocal(spec.changed_at),
    })
    setShowModal(true)
  }

  async function handleSave() {
    if (!form.name) return
    setSaving(true)
    setSyncStatus('pending')

    const payload = {
      name: form.name,
      location: form.location,
      usecase: form.usecase,
      details: form.details,
      defect_parts: form.defect_parts,
      parts_changed: form.parts_changed,
      changed_at: form.changed_at ? new Date(form.changed_at).toISOString() : null,
    }

    let error
    if (editSpec) {
      ({ error } = await supabase.from('machine_specs').update(payload).eq('id', editSpec.id))
    } else {
      ({ error } = await supabase.from('machine_specs').insert(payload))
    }

    if (error) {
      setSyncStatus('failed')
    } else {
      setSyncStatus('synced')
      setShowModal(false)
      fetchSpecs()
    }
    setSaving(false)
  }

  async function handleDelete() {
    if (!deleteTarget) return
    setSyncStatus('pending')
    const { error } = await supabase.from('machine_specs').delete().eq('id', deleteTarget.id)
    if (!error) {
      setSyncStatus('synced')
      fetchSpecs()
    } else {
      setSyncStatus('failed')
    }
    setDeleteTarget(null)
  }

  const query = search.toLowerCase()
  const filtered = specs.filter(spec =>
    String(spec.id ?? '').toLowerCase().includes(query) ||
    String(spec.user_id ?? '').toLowerCase().includes(query) ||
    String(spec.name ?? '').toLowerCase().includes(query) ||
    String(spec.location ?? '').toLowerCase().includes(query) ||
    String(spec.usecase ?? '').toLowerCase().includes(query) ||
    String(spec.details ?? '').toLowerCase().includes(query) ||
    String(spec.defect_parts ?? '').toLowerCase().includes(query) ||
    String(spec.parts_changed ?? '').toLowerCase().includes(query)
  )

  return (
    <div>
      <div className="page-header">
        <div>
          <div className="page-title">Machine Specs</div>
          <div className="page-subtitle">{specs.length} machine specs tracked</div>
        </div>
        <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
          <span className={`sync-pill ${syncStatus}`}>
            <span className="badge-dot" />
            {syncStatus === 'synced' ? 'Synced' : syncStatus === 'pending' ? 'Saving…' : 'Sync Failed'}
          </span>
          <button className="btn btn-primary" onClick={openAdd}>+ Add Spec</button>
        </div>
      </div>

      {error && (
        <div className="alert-banner critical" style={{ marginBottom: 16 }}>
          <span>✕</span>
          <div>
            <div className="alert-banner-title">Load Error</div>
            <div className="alert-banner-body">{error}</div>
          </div>
          <button className="btn btn-secondary btn-sm" style={{ marginLeft: 'auto' }} onClick={fetchSpecs}>Retry</button>
        </div>
      )}

      <div className="card">
        <div className="card-header">
          <div className="search-bar">
            <span className="search-icon">⌕</span>
            <input
              placeholder="Search specs by id, user, name, location, usecase, defect parts…"
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
                <th>Name</th>
                <th>Location</th>
                <th>Usecase</th>
                <th>Details</th>
                <th>Defect Parts</th>
                <th>Parts Changed</th>
                <th>Changed At</th>
                <th>Created At</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                [...Array(6)].map((_, i) => (
                  <tr key={i}>
                    {[...Array(11)].map((_, j) => (
                      <td key={j}><div className="skeleton" style={{ height: 16, width: j >= 2 && j <= 7 ? 140 : 90 }} /></td>
                    ))}
                  </tr>
                ))
              ) : filtered.length === 0 ? (
                <tr>
                  <td colSpan={11}>
                    <div className="empty-state">
                      <div className="empty-state-icon">⚙</div>
                      <div className="empty-state-title">No machine specs found</div>
                      <div className="empty-state-desc">Add your first machine spec to get started</div>
                    </div>
                  </td>
                </tr>
              ) : (
                filtered.map(spec => (
                  <tr key={spec.id}>
                    <td className="mono" style={{ color: 'var(--text-muted)', fontSize: 12 }}>{spec.id}</td>
                    <td className="mono" style={{ color: 'var(--text-muted)', fontSize: 12 }}>{spec.user_id || '—'}</td>
                    <td style={{ fontWeight: 600 }}>{spec.name || '—'}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{spec.location || '—'}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{spec.usecase || '—'}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{spec.details || '—'}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{spec.defect_parts || '—'}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{spec.parts_changed || '—'}</td>
                    <td className="mono" style={{ fontSize: 12, color: 'var(--text-secondary)' }}>{formatDate(spec.changed_at)}</td>
                    <td className="mono" style={{ fontSize: 12, color: 'var(--text-secondary)' }}>{formatDate(spec.created_at)}</td>
                    <td>
                      <div style={{ display: 'flex', gap: 8 }}>
                        <button className="btn btn-secondary btn-sm" onClick={() => openEdit(spec)}>Edit</button>
                        <button className="btn btn-danger btn-sm" onClick={() => setDeleteTarget(spec)}>Delete</button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {showModal && (
        <div className="modal-overlay" onClick={e => e.target === e.currentTarget && setShowModal(false)}>
          <div className="modal" style={{ maxWidth: 680 }}>
            <div className="modal-header">
              <div className="modal-title">{editSpec ? 'Edit Machine Spec' : 'Add Machine Spec'}</div>
              <button className="modal-close" onClick={() => setShowModal(false)}>✕</button>
            </div>
            <div className="modal-body">
              <div className="grid-2">
                <div className="form-group">
                  <label>Name *</label>
                  <input
                    placeholder="e.g. Excavator Alpha"
                    value={form.name}
                    onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
                  />
                </div>
                <div className="form-group">
                  <label>Location</label>
                  <input
                    placeholder="e.g. Zone 3"
                    value={form.location}
                    onChange={e => setForm(f => ({ ...f, location: e.target.value }))}
                  />
                </div>
                <div className="form-group">
                  <label>Usecase</label>
                  <input
                    placeholder="e.g. Material handling"
                    value={form.usecase}
                    onChange={e => setForm(f => ({ ...f, usecase: e.target.value }))}
                  />
                </div>
                <div className="form-group">
                  <label>Changed At</label>
                  <input
                    type="datetime-local"
                    value={form.changed_at}
                    onChange={e => setForm(f => ({ ...f, changed_at: e.target.value }))}
                  />
                </div>
              </div>

              <div className="form-group">
                <label>Details</label>
                <textarea
                  rows={3}
                  placeholder="Machine details..."
                  value={form.details}
                  onChange={e => setForm(f => ({ ...f, details: e.target.value }))}
                />
              </div>
              <div className="form-group">
                <label>Defect Parts</label>
                <textarea
                  rows={2}
                  placeholder="List defective parts..."
                  value={form.defect_parts}
                  onChange={e => setForm(f => ({ ...f, defect_parts: e.target.value }))}
                />
              </div>
              <div className="form-group">
                <label>Parts Changed</label>
                <textarea
                  rows={2}
                  placeholder="List changed parts..."
                  value={form.parts_changed}
                  onChange={e => setForm(f => ({ ...f, parts_changed: e.target.value }))}
                />
              </div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setShowModal(false)}>Cancel</button>
              <button className="btn btn-primary" onClick={handleSave} disabled={saving || !form.name}>
                {saving ? 'Saving…' : editSpec ? 'Save Changes' : 'Add Spec'}
              </button>
            </div>
          </div>
        </div>
      )}

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
                    You are about to permanently delete <strong>{deleteTarget.name || `Spec ${deleteTarget.id}`}</strong> from machine specs.
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