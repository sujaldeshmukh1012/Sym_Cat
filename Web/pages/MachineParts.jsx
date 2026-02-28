import { useEffect, useState } from 'react'
import { supabase } from '../src/supabase'

export default function MachineParts() {
  const [parts, setParts] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [syncStatus, setSyncStatus] = useState('synced')
  const [error, setError] = useState(null)

  useEffect(() => { fetchParts() }, [])

  async function fetchParts() {
    setLoading(true)
    setError(null)
    const { data, error } = await supabase
      .from('parts')
      .select('id, created_at, part_name, part_description, serial_number')
      .order('created_at', { ascending: false })

    if (error) {
      setError('Failed to load machine parts. Check your connection and try again.')
    } else {
      setParts(data || [])
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
  const filtered = parts.filter(part =>
    String(part.id ?? '').toLowerCase().includes(query) ||
    String(part.part_name ?? '').toLowerCase().includes(query) ||
    String(part.part_description ?? '').toLowerCase().includes(query) ||
    String(part.serial_number ?? '').toLowerCase().includes(query)
  )

  return (
    <div>
      <div className="page-header">
        <div>
          <div className="page-title">Machine Parts</div>
          <div className="page-subtitle">{parts.length} parts tracked</div>
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
          <button className="btn btn-secondary btn-sm" style={{ marginLeft: 'auto' }} onClick={fetchParts}>Retry</button>
        </div>
      )}

      <div className="card">
        <div className="card-header">
          <div className="search-bar">
            <span className="search-icon">⌕</span>
            <input
              placeholder="Search parts by id, name, description, or serial number…"
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
                <th>Part Description</th>
                <th>Serial Number</th>
                <th>Created At</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                [...Array(6)].map((_, i) => (
                  <tr key={i}>
                    {[...Array(5)].map((_, j) => (
                      <td key={j}><div className="skeleton" style={{ height: 16, width: j === 2 ? 220 : 120 }} /></td>
                    ))}
                  </tr>
                ))
              ) : filtered.length === 0 ? (
                <tr>
                  <td colSpan={5}>
                    <div className="empty-state">
                      <div className="empty-state-icon">⚙</div>
                      <div className="empty-state-title">No machine parts found</div>
                      <div className="empty-state-desc">No parts records are currently available</div>
                    </div>
                  </td>
                </tr>
              ) : (
                filtered.map(part => (
                  <tr key={part.id}>
                    <td className="mono" style={{ color: 'var(--text-muted)', fontSize: 12 }}>{part.id}</td>
                    <td style={{ fontWeight: 600 }}>{part.part_name || '—'}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{part.part_description || '—'}</td>
                    <td className="mono" style={{ color: 'var(--text-secondary)' }}>{part.serial_number || '—'}</td>
                    <td className="mono" style={{ fontSize: 12, color: 'var(--text-secondary)' }}>{formatDate(part.created_at)}</td>
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