import { useEffect, useState } from 'react'
import { supabase } from '../src/supabase'

const EMPTY_FORM = {
  serial_number: '',
  model: '',
  inspector: '',
  temperature: '',
  engine_manufacture: '',
  work_order: '',
  simu: '',
  time: '',
  date: '',
  unit_location: '',
  status_of_machine: '',
  visual_inspection: '',
}

const STATUS_OPTIONS = ['Operational', 'Degraded', 'Critical', 'Offline', 'Under Maintenance']

export default function Reports() {
  const [reports, setReports] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [showModal, setShowModal] = useState(false)
  const [viewReport, setViewReport] = useState(null)
  const [form, setForm] = useState(EMPTY_FORM)
  const [saving, setSaving] = useState(false)
  const [syncStatus, setSyncStatus] = useState('synced')
  const [deleteTarget, setDeleteTarget] = useState(null)
  const [error, setError] = useState(null)

  useEffect(() => { fetchReports() }, [])

  async function fetchReports() {
    setLoading(true)
    setError(null)
    const { data, error } = await supabase
      .from('reports')
      .select('*')
      .order('date', { ascending: false })
    if (error) {
      setError('Failed to load reports. Check your connection and try again.')
    } else {
      setReports(data || [])
    }
    setLoading(false)
  }

  function openAdd() {
    setForm(EMPTY_FORM)
    setShowModal(true)
  }

  function setField(key, val) {
    setForm(f => ({ ...f, [key]: val }))
  }

  async function handleSave() {
    if (!form.serial_number) return
    setSaving(true)
    setSyncStatus('pending')
    const { error } = await supabase.from('reports').insert(form)
    if (error) {
      setSyncStatus('failed')
    } else {
      setSyncStatus('synced')
      setShowModal(false)
      fetchReports()
    }
    setSaving(false)
  }

  async function handleDelete() {
    if (!deleteTarget) return
    setSyncStatus('pending')
    const { error } = await supabase.from('reports').delete().eq('serial_number', deleteTarget.serial_number)
    if (!error) {
      setSyncStatus('synced')
      fetchReports()
    } else {
      setSyncStatus('failed')
    }
    setDeleteTarget(null)
  }

  const filtered = reports.filter(r =>
    r.serial_number?.toLowerCase().includes(search.toLowerCase()) ||
    r.inspector?.toLowerCase().includes(search.toLowerCase()) ||
    r.model?.toLowerCase().includes(search.toLowerCase()) ||
    r.unit_location?.toLowerCase().includes(search.toLowerCase())
  )

  const statusBadge = (status) => {
    const map = {
      'Operational': 'badge-success',
      'Degraded': 'badge-warning',
      'Critical': 'badge-critical',
      'Offline': 'badge-critical',
      'Under Maintenance': 'badge-info',
    }
    return (
      <span className={`badge ${map[status] || 'badge-neutral'}`}>
        <span className="badge-dot" />{status || '—'}
      </span>
    )
  }

  return (
    <div>
      <div className="page-header">
        <div>
          <div className="page-title">Inspection Reports</div>
          <div className="page-subtitle">{reports.length} total reports on record</div>
        </div>
        <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
          <span className={`sync-pill ${syncStatus}`}>
            <span className="badge-dot" />
            {syncStatus === 'synced' ? 'Synced' : syncStatus === 'pending' ? 'Saving…' : 'Sync Failed'}
          </span>
          <button className="btn btn-primary" onClick={openAdd}>+ New Report</button>
        </div>
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
              placeholder="Search by serial, inspector, model, location…"
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
                <th>Serial No.</th>
                <th>Model</th>
                <th>Inspector</th>
                <th>Work Order</th>
                <th>Location</th>
                <th>Date</th>
                <th>Machine Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                [...Array(5)].map((_, i) => (
                  <tr key={i}>
                    {[...Array(8)].map((_, j) => (
                      <td key={j}><div className="skeleton" style={{ height: 16, width: j === 1 ? 120 : 80 }} /></td>
                    ))}
                  </tr>
                ))
              ) : filtered.length === 0 ? (
                <tr>
                  <td colSpan={8}>
                    <div className="empty-state">
                      <div className="empty-state-icon">◻</div>
                      <div className="empty-state-title">No reports found</div>
                      <div className="empty-state-desc">Create your first inspection report</div>
                    </div>
                  </td>
                </tr>
              ) : (
                filtered.map(r => (
                  <tr key={r.serial_number}>
                    <td className="mono" style={{ fontWeight: 600 }}>{r.serial_number}</td>
                    <td>{r.model || '—'}</td>
                    <td>{r.inspector || '—'}</td>
                    <td className="mono" style={{ fontSize: 12 }}>{r.work_order || '—'}</td>
                    <td style={{ color: 'var(--text-secondary)' }}>{r.unit_location || '—'}</td>
                    <td className="mono" style={{ fontSize: 12, color: 'var(--text-secondary)' }}>{r.date || '—'}</td>
                    <td>{statusBadge(r.status_of_machine)}</td>
                    <td>
                      <div style={{ display: 'flex', gap: 8 }}>
                        <button className="btn btn-secondary btn-sm" onClick={() => setViewReport(r)}>View</button>
                        <button className="btn btn-danger btn-sm" onClick={() => setDeleteTarget(r)}>Delete</button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* New Report Modal */}
      {showModal && (
        <div className="modal-overlay" onClick={e => e.target === e.currentTarget && setShowModal(false)}>
          <div className="modal" style={{ maxWidth: 680 }}>
            <div className="modal-header">
              <div className="modal-title">New Inspection Report</div>
              <button className="modal-close" onClick={() => setShowModal(false)}>✕</button>
            </div>
            <div className="modal-body">
              <div style={{ fontSize: 12, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.07em', color: 'var(--text-muted)', marginBottom: 12 }}>
                Machine Identification
              </div>
              <div className="grid-2">
                <div className="form-group">
                  <label>Serial Number *</label>
                  <input placeholder="SN-000000" value={form.serial_number} onChange={e => setField('serial_number', e.target.value)} />
                </div>
                <div className="form-group">
                  <label>Model</label>
                  <input placeholder="e.g. CAT 320" value={form.model} onChange={e => setField('model', e.target.value)} />
                </div>
                <div className="form-group">
                  <label>Engine Manufacturer</label>
                  <input placeholder="e.g. Cummins" value={form.engine_manufacture} onChange={e => setField('engine_manufacture', e.target.value)} />
                </div>
                <div className="form-group">
                  <label>Unit Location</label>
                  <input placeholder="e.g. Site B, Bay 3" value={form.unit_location} onChange={e => setField('unit_location', e.target.value)} />
                </div>
              </div>

              <div style={{ fontSize: 12, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.07em', color: 'var(--text-muted)', margin: '16px 0 12px' }}>
                Inspection Details
              </div>
              <div className="grid-2">
                <div className="form-group">
                  <label>Inspector</label>
                  <input placeholder="Inspector name" value={form.inspector} onChange={e => setField('inspector', e.target.value)} />
                </div>
                <div className="form-group">
                  <label>Work Order</label>
                  <input placeholder="WO-000000" value={form.work_order} onChange={e => setField('work_order', e.target.value)} />
                </div>
                <div className="form-group">
                  <label>Date</label>
                  <input type="date" value={form.date} onChange={e => setField('date', e.target.value)} />
                </div>
                <div className="form-group">
                  <label>Time</label>
                  <input type="time" value={form.time} onChange={e => setField('time', e.target.value)} />
                </div>
                <div className="form-group">
                  <label>Temperature (°C/°F)</label>
                  <input placeholder="e.g. 82°C" value={form.temperature} onChange={e => setField('temperature', e.target.value)} />
                </div>
                <div className="form-group">
                  <label>SIMU</label>
                  <input placeholder="SIMU reference" value={form.simu} onChange={e => setField('simu', e.target.value)} />
                </div>
              </div>

              <div style={{ fontSize: 12, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.07em', color: 'var(--text-muted)', margin: '16px 0 12px' }}>
                Condition Assessment
              </div>
              <div className="form-group">
                <label>Status of Machine</label>
                <select value={form.status_of_machine} onChange={e => setField('status_of_machine', e.target.value)}>
                  <option value="">Select status…</option>
                  {STATUS_OPTIONS.map(s => <option key={s} value={s}>{s}</option>)}
                </select>
              </div>
              <div className="form-group">
                <label>Visual Inspection Notes</label>
                <textarea
                  rows={4}
                  placeholder="Describe visual observations, anomalies, or findings…"
                  value={form.visual_inspection}
                  onChange={e => setField('visual_inspection', e.target.value)}
                />
              </div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setShowModal(false)}>Cancel</button>
              <button className="btn btn-primary" onClick={handleSave} disabled={saving || !form.serial_number}>
                {saving ? 'Submitting…' : 'Submit Report'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* View Report Modal */}
      {viewReport && (
        <div className="modal-overlay" onClick={e => e.target === e.currentTarget && setViewReport(null)}>
          <div className="modal" style={{ maxWidth: 680 }}>
            <div className="modal-header">
              <div>
                <div className="modal-title">Inspection Report</div>
                <div style={{ fontSize: 13, color: 'var(--text-muted)', marginTop: 2 }}>Serial: <span className="mono">{viewReport.serial_number}</span></div>
              </div>
              <button className="modal-close" onClick={() => setViewReport(null)}>✕</button>
            </div>
            <div className="modal-body">
              {/* Status Banner */}
              <div style={{ marginBottom: 20 }}>
                {statusBadge(viewReport.status_of_machine)}
              </div>

              {/* Info Grid */}
              {[
                ['Model', viewReport.model],
                ['Engine Manufacturer', viewReport.engine_manufacture],
                ['Unit Location', viewReport.unit_location],
                ['Inspector', viewReport.inspector],
                ['Work Order', viewReport.work_order],
                ['Date', viewReport.date],
                ['Time', viewReport.time],
                ['Temperature', viewReport.temperature],
                ['SIMU', viewReport.simu],
              ].map(([label, val]) => val ? (
                <div key={label} style={{ display: 'flex', gap: 16, padding: '10px 0', borderBottom: '1px solid var(--border)' }}>
                  <div style={{ width: 180, fontSize: 13, fontWeight: 600, color: 'var(--text-secondary)', flexShrink: 0 }}>{label}</div>
                  <div style={{ fontSize: 14, color: 'var(--text-primary)' }}>{val}</div>
                </div>
              ) : null)}

              {viewReport.visual_inspection && (
                <div style={{ marginTop: 20 }}>
                  <div style={{ fontSize: 12, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.07em', color: 'var(--text-muted)', marginBottom: 10 }}>
                    Visual Inspection Notes
                  </div>
                  <div style={{
                    background: 'var(--bg)',
                    border: '1px solid var(--border)',
                    borderRadius: 6,
                    padding: 16,
                    fontSize: 14,
                    lineHeight: 1.7,
                    whiteSpace: 'pre-wrap'
                  }}>
                    {viewReport.visual_inspection}
                  </div>
                </div>
              )}
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setViewReport(null)}>Close</button>
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
                    You are about to permanently delete report for serial <strong>{deleteTarget.serial_number}</strong>.
                    Work order: <strong>{deleteTarget.work_order || 'N/A'}</strong>.
                  </div>
                </div>
              </div>
            </div>
            <div className="modal-footer">
              <button className="btn btn-secondary" onClick={() => setDeleteTarget(null)}>Cancel</button>
              <button className="btn btn-danger" onClick={handleDelete}>Delete Report</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
