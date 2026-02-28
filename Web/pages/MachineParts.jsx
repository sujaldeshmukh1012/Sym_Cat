import { useEffect, useState } from 'react'
import { supabase } from '../src/supabase'

export default function MachineParts() {
  const [specs, setSpecs] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
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
              </tr>
            </thead>
            <tbody>
              {loading ? (
                [...Array(6)].map((_, i) => (
                  <tr key={i}>
                    {[...Array(10)].map((_, j) => (
                      <td key={j}><div className="skeleton" style={{ height: 16, width: j >= 2 && j <= 7 ? 140 : 90 }} /></td>
                    ))}
                  </tr>
                ))
              ) : filtered.length === 0 ? (
                <tr>
                  <td colSpan={10}>
                    <div className="empty-state">
                      <div className="empty-state-icon">⚙</div>
                      <div className="empty-state-title">No machine specs found</div>
                      <div className="empty-state-desc">No machine spec records are currently available</div>
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