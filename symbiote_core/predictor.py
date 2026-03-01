"""
Predictive Failure Scoring module.

Calculates a projected time to failure based on historical inspection data.
For this demo, it identifies if a component's condition is escalating
and projects the days until a critical failure occurs.
"""
import logging
from db import get_supabase

_log = logging.getLogger(__name__)


def calculate_failure_prediction(equipment_id: str, component: str) -> dict:
    """
    Pull last 5 inspections for this component on this machine from Supabase.
    Count severity escalation over time.
    Project forward.
    """
    if not equipment_id or not component:
        return {"prediction": "Insufficient data"}

    try:
        supabase = get_supabase()
        # Query Supabase for inspection history
        response = supabase.table("inspections") \
            .select("created_at, anomalies") \
            .eq("equipment_id", equipment_id) \
            .order("created_at") \
            .limit(5) \
            .execute()
        
        history = response.data
    except Exception as e:
        _log.warning("Failed to fetch inspection history for prediction: %s", e)
        return {"prediction": "Error fetching history"}

    # Score each inspection: GREEN=0, YELLOW=1, RED=2
    scores = []
    for inspection in history:
        anomalies = inspection.get("anomalies", [])
        if not anomalies:
            continue
        
        # Check if any anomaly relates to our component
        component_anomalies = [a for a in anomalies if component.lower() in a.get("component", "").lower()]
        
        if component_anomalies:
            # Take the worst severity among the relevant anomalies
            worst_score = 0
            for a in component_anomalies:
                severity = a.get("severity", "").lower()
                if severity in ("fail", "critical", "red"):
                    score = 2
                elif severity in ("monitor", "moderate", "yellow"):
                    score = 1
                else:
                    score = 0
                worst_score = max(worst_score, score)
                
            scores.append(worst_score)
        else:
            # If inspected but no anomalies for this component, score is 0
            scores.append(0)

    if len(scores) < 2:
        return {"prediction": "Insufficient data (needs at least 2 past inspections)"}

    # Simple trend: is it getting worse?
    trend = scores[-1] - scores[0]
    days_to_critical = None

    if trend > 0 and scores[-1] < 2:
        # Escalating — project to RED
        rate = trend / len(scores)
        days_to_critical = int((2 - scores[-1]) / rate * 7)

    message = "Stable"
    if trend > 0:
        if days_to_critical:
            message = f"{component.title()} degraded in recent inspections. Critical failure projected in {days_to_critical} days."
        else:
            message = f"{component.title()} is escalating."

    return {
        "trend": "ESCALATING" if trend > 0 else "STABLE",
        "days_to_critical": days_to_critical,
        "message": message,
        "cost_if_ignored": "$24,000 engine replacement vs $45 part replacement today" if trend > 0 else None
    }
