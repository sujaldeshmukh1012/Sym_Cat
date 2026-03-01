import { useEffect, useMemo, useState } from 'react'
import { supabase } from '../src/supabase'

const STATE_WEIGHT = {
  pending: 1,
  queued: 1,
  in_progress: 0.7,
  'in progress': 0.7,
  'in-progress': 0.7,
  inprogress: 0.7,
  monitor: 0.6,
  completed: 0,
  approved: 0,
  confirmed: 0,
  resolved: 0,
  pass: 0,
  fail: 2,
  failed: 2,
  rejected: 2,
}

function normalizeState(value) {
  return String(value ?? '').replace(/^"|"$/g, '').toLowerCase().trim()
}

function parseFleetObject(value) {
  if (value && typeof value === 'object') return value

  const raw = String(value ?? '').trim()
  if (!raw) return null

  try {
    const parsed = JSON.parse(raw)
    if (Array.isArray(parsed) && parsed.length > 0 && parsed[0] && typeof parsed[0] === 'object') {
      return parsed[0]
    }
    if (parsed && typeof parsed === 'object') return parsed
  } catch {
    return null
  }

  return null
}

function cleanFleetName(rawName, fallbackId) {
  const parsed = parseFleetObject(rawName)
  if (parsed?.name) return String(parsed.name).trim()

  const text = String(rawName ?? '').trim()
  if (!text) return `Fleet ${fallbackId}`

  if (text.startsWith('[') || text.startsWith('{')) return `Fleet ${fallbackId}`
  if (/^\d+$/.test(text)) return `Fleet ${fallbackId}`

  return text
}

function cleanFleetSerial(rawSerial, rawName) {
  const parsedSerial = parseFleetObject(rawSerial)
  if (parsedSerial?.serial_number) return String(parsedSerial.serial_number).trim()

  const parsedName = parseFleetObject(rawName)
  if (parsedName?.serial_number) return String(parsedName.serial_number).trim()

  const serialText = String(rawSerial ?? '').trim()
  if (!serialText) return ''
  if (serialText.startsWith('[') || serialText.startsWith('{')) return ''
  if (/^\d+$/.test(serialText)) return ''

  return serialText
}

function scoreToHeatClass(score) {
  if (score >= 85) return 'good'
  if (score >= 70) return 'ok'
  if (score >= 50) return 'warn'
  return 'bad'
}

export default function FleetHealthAnalytics() {
  const [fleets, setFleets] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [syncStatus, setSyncStatus] = useState('synced')

  useEffect(() => {
    fetchAnalytics()
  }, [])

  async function fetchAnalytics() {
    setLoading(true)
    setError('')
    setSyncStatus('pending')

    try {
      const fleetsRes = await supabase
        .from('fleet')
        .select('id, name, serial_number')
        .order('id', { ascending: true })
        .limit(12)

      if (fleetsRes.error) throw new Error(fleetsRes.error.message)
      const rawFleets = fleetsRes.data || []

      if (rawFleets.length === 0) {
        setFleets([])
        setSyncStatus('synced')
        return
      }

      const fleetResults = await Promise.all(
        rawFleets.map(async fleet => {
          const controller = new AbortController()
          const timeoutId = window.setTimeout(() => controller.abort(), 12000)

          try {
            const response = await fetch(`/fleet-health/${fleet.id}?limit=6`, { signal: controller.signal })
            if (!response.ok) return null
            const payload = await response.json()

            const timeline = Array.isArray(payload?.timeline) ? payload.timeline : []
            const normalizedTimeline = timeline.map(item => ({
              ...item,
              health_score: Number(item.health_score ?? 0),
              anomaly_count: Number(item.anomaly_count ?? 0),
            }))

            const totalAnomalies = normalizedTimeline.reduce((sum, row) => sum + row.anomaly_count, 0)
            const statePenalty = normalizedTimeline.reduce((sum, row) => {
              const tasks = Array.isArray(row.tasks) ? row.tasks : []
              const rowPenalty = tasks.reduce((innerSum, task) => {
                const normalizedState = normalizeState(task?.state)
                return innerSum + (STATE_WEIGHT[normalizedState] ?? 0)
              }, 0)
              return sum + rowPenalty
            }, 0)

            return {
              fleet_id: fleet.id,
              fleet_name: cleanFleetName(fleet.name, fleet.id),
              serial_number: cleanFleetSerial(fleet.serial_number, fleet.name),
              health_score: Number(payload?.health_score ?? payload?.summary?.current_health_score ?? 0),
              trend: payload?.trend || 'stable',
              timeline: normalizedTimeline,
              risk_index: Number((statePenalty + totalAnomalies * 1.2).toFixed(1)),
              total_anomalies: totalAnomalies,
            }
          } catch {
            return null
          } finally {
            window.clearTimeout(timeoutId)
          }
        })
      )

      const valid = fleetResults.filter(Boolean)
      setFleets(valid)
      setSyncStatus('synced')
    } catch (err) {
      if (err?.name === 'AbortError') {
        setError('Fleet analytics request timed out. Please retry.')
      } else {
        setError('Failed to load fleet analytics.')
      }
      setFleets([])
      setSyncStatus('failed')
    } finally {
      setLoading(false)
    }
  }

  const fleetsWithTimeline = useMemo(
    () => fleets.filter(fleet => Array.isArray(fleet.timeline) && fleet.timeline.length > 0),
    [fleets]
  )

  const fleetNameCounts = useMemo(
    () => fleetsWithTimeline.reduce((accumulator, fleet) => {
      const normalized = String(fleet.fleet_name || '').trim().toLowerCase()
      if (!normalized) return accumulator
      accumulator[normalized] = (accumulator[normalized] || 0) + 1
      return accumulator
    }, {}),
    [fleetsWithTimeline]
  )

  const displayFleets = useMemo(
    () => fleetsWithTimeline.map(fleet => {
      const fleetName = String(fleet.fleet_name || `Fleet ${fleet.fleet_id}`).trim()
      const serial = String(fleet.serial_number || '').trim()
      const normalized = fleetName.toLowerCase()
      const isDuplicate = (fleetNameCounts[normalized] || 0) > 1

      const displayName = isDuplicate
        ? serial
          ? `${fleetName} (${serial})`
          : fleetName
        : fleetName

      return {
        ...fleet,
        display_name: displayName,
        display_serial: serial || '—',
      }
    }),
    [fleetsWithTimeline, fleetNameCounts]
  )

  const rankedRisk = useMemo(
    () => [...displayFleets].sort((a, b) => b.risk_index - a.risk_index).slice(0, 6),
    [displayFleets]
  )

  const maxRisk = Math.max(1, ...rankedRisk.map(item => item.risk_index || 0))

  const summary = useMemo(() => {
    if (displayFleets.length === 0) {
      return {
        fleetCount: 0,
        avgHealth: 0,
        totalAnomalies: 0,
        totalRisk: 0,
      }
    }

    const avgHealth = displayFleets.reduce((sum, row) => sum + (Number(row.health_score) || 0), 0) / displayFleets.length
    const totalAnomalies = displayFleets.reduce((sum, row) => sum + (Number(row.total_anomalies) || 0), 0)
    const totalRisk = displayFleets.reduce((sum, row) => sum + (Number(row.risk_index) || 0), 0)

    return {
      fleetCount: displayFleets.length,
      avgHealth,
      totalAnomalies,
      totalRisk,
    }
  }, [displayFleets])

  const maxTimelineLength = Math.max(0, ...displayFleets.map(fleet => fleet.timeline.length))

  return (
    <div className="fleet-health-shell">
      <div className="page-header">
        <div>
          <div className="page-title">Fleet Health Analytics</div>
          <div className="page-subtitle">Health trend heatmap, risk ranking, and anomaly insights by fleet</div>
        </div>
        <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
          <button className="btn btn-secondary btn-sm" onClick={fetchAnalytics}>↻ Refresh</button>
          <span className={`sync-pill ${syncStatus}`}>
            <span className="badge-dot" />
            {syncStatus === 'synced' ? 'Synced' : syncStatus === 'pending' ? 'Loading…' : 'Sync Failed'}
          </span>
        </div>
      </div>

      {error && (
        <div className="alert-banner critical" style={{ marginBottom: 16 }}>
          <span>✕</span>
          <div>
            <div className="alert-banner-title">Analytics Error</div>
            <div className="alert-banner-body">{error}</div>
          </div>
        </div>
      )}

      <div className="kpi-strip" style={{ marginBottom: 18 }}>
        <div className="kpi-card">
          <div className="kpi-label">Fleets Analyzed</div>
          <div className="kpi-value">{summary.fleetCount}</div>
        </div>
        <div className="kpi-card">
          <div className="kpi-label">Average Health</div>
          <div className="kpi-value">{summary.avgHealth.toFixed(1)}</div>
        </div>
        <div className="kpi-card">
          <div className="kpi-label">Total Anomalies</div>
          <div className="kpi-value">{summary.totalAnomalies}</div>
        </div>
        <div className="kpi-card">
          <div className="kpi-label">Operational Risk Index</div>
          <div className="kpi-value">{summary.totalRisk.toFixed(1)}</div>
        </div>
      </div>

      <div className="grid-2" style={{ alignItems: 'start' }}>
        <div className="card">
          <div className="card-header" style={{ alignItems: 'center' }}>
            <span className="card-title">Health Score Heatmap</span>
            <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>latest {maxTimelineLength} inspections</span>
          </div>
          <div className="card-body" style={{ paddingTop: 14 }}>
            {loading ? (
              <div>
                {[...Array(6)].map((_, i) => <div key={i} className="skeleton skeleton-row" style={{ marginBottom: 6 }} />)}
              </div>
            ) : displayFleets.length === 0 ? (
              <div className="empty-state" style={{ padding: 20 }}>
                <div className="empty-state-icon">◉</div>
                <div className="empty-state-title">No fleet analytics available</div>
                <div className="empty-state-desc">Run inspections to generate health timeline data</div>
              </div>
            ) : (
              <div className="fleet-heatmap">
                <div className="fleet-heatmap-legend">
                  <span className="fleet-legend-item"><span className="fleet-legend-swatch good" /> 85+</span>
                  <span className="fleet-legend-item"><span className="fleet-legend-swatch ok" /> 70-84</span>
                  <span className="fleet-legend-item"><span className="fleet-legend-swatch warn" /> 50-69</span>
                  <span className="fleet-legend-item"><span className="fleet-legend-swatch bad" /> &lt;50</span>
                </div>
                <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
                  Each box = one inspection score. If you see six <span className="mono">100</span> values, it means the last 6 inspections were all scored 100.
                </div>

                <div style={{ display: 'grid', gap: 8 }}>
                  {displayFleets.map(fleet => (
                    <div key={fleet.fleet_id} className="fleet-heatmap-row">
                      <div className="fleet-heatmap-label" title={fleet.display_name}>
                        <div style={{ fontWeight: 600 }}>{fleet.display_name}</div>
                        <div className="mono" style={{ fontSize: 11, color: 'var(--text-muted)' }}>{fleet.display_serial}</div>
                      </div>
                      <div className="fleet-heatmap-cells">
                        {fleet.timeline.map(item => {
                          const score = Number(item.health_score) || 0
                          const stateClass = scoreToHeatClass(score)
                          return (
                            <div
                              key={`${fleet.fleet_id}-${item.inspection_id}`}
                              className={`fleet-heatmap-cell ${stateClass}`}
                              title={`Inspection ${item.inspection_id} · Score ${score.toFixed(1)} · Anomalies ${item.anomaly_count}`}
                            >
                              {score.toFixed(0)}
                            </div>
                          )
                        })}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>

        <div className="card">
          <div className="card-header" style={{ alignItems: 'center' }}>
            <span className="card-title">Risk Ranking & Insights</span>
            <span className="badge badge-warning"><span className="badge-dot" /> Higher means more attention</span>
          </div>
          <div className="card-body" style={{ paddingTop: 14 }}>
            {loading ? (
              <div>
                {[...Array(6)].map((_, i) => <div key={i} className="skeleton skeleton-row" style={{ marginBottom: 6 }} />)}
              </div>
            ) : rankedRisk.length === 0 ? (
              <div className="empty-state" style={{ padding: 20 }}>
                <div className="empty-state-icon">△</div>
                <div className="empty-state-title">No risk ranking yet</div>
                <div className="empty-state-desc">Risk bars appear after fleet inspection data is available</div>
              </div>
            ) : (
              <div style={{ display: 'grid', gap: 12 }}>
                {rankedRisk.map(fleet => (
                  <div key={`risk-${fleet.fleet_id}`}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8, marginBottom: 4 }}>
                      <span style={{ fontWeight: 600, color: 'var(--text-primary)' }}>{fleet.display_name}</span>
                      <span className="badge badge-info-soft"><span className="badge-dot" /> {fleet.risk_index.toFixed(1)}</span>
                    </div>
                    <div style={{ width: '100%', height: 10, background: 'var(--bg)', border: '1px solid var(--border)', borderRadius: 999 }}>
                      <div
                        style={{
                          height: '100%',
                          width: `${Math.max(8, (fleet.risk_index / maxRisk) * 100)}%`,
                          borderRadius: 999,
                          background: 'var(--warning)',
                        }}
                      />
                    </div>
                    <div style={{ marginTop: 5, fontSize: 12, color: 'var(--text-secondary)' }}>
                      Health {Number(fleet.health_score || 0).toFixed(1)} · Trend {fleet.trend} · Anomalies {fleet.total_anomalies}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
