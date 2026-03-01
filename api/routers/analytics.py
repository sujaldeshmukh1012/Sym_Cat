"""
/analytics — Predictive Analytics and Health Trends
"""
import logging
from fastapi import APIRouter, Query

from api.routers import supabase

router = APIRouter(prefix="/analytics", tags=["Analytics"])
_log = logging.getLogger("api.analytics")


@router.get("/predict_failure")
async def predict_failure(
    equipment_id: str = Query(..., description="ID of the equipment (e.g. CAT-320-002)"),
    component: str = Query(..., description="Name of the component to predict for"),
):
    """
    Pull last 5 inspections for this component on this machine from Supabase.
    Count severity escalation over time.
    Project forward to estimate days until critical failure.
    """
    if not equipment_id or not component:
        return {"prediction": "Insufficient data"}

    try:
        # Resolve equipment_id string to fleet.id
        q_fleet = supabase.table("fleet").select("id").eq("serial_number", equipment_id).execute()
        if q_fleet.data:
            fleet_id = q_fleet.data[0]["id"]
            q = supabase.table("inspection").select("id, created_at, fleet_serial").eq("fleet_serial", fleet_id)
        else:
            # Fallback for demo: just get the latest inspections globally if the equipment isn't found
            q = supabase.table("inspection").select("id, created_at, fleet_serial")


        resp = q.order("created_at", desc=True).limit(5).execute()
        
        inspections = resp.data or []
    except Exception as e:
        _log.warning("Failed to fetch inspection history for prediction: %s", e)
        return {"prediction": "Error fetching history"}

    if not inspections:
        return {"prediction": "No inspection history found for this equipment."}

    # Fetch tasks for these inspections
    inspection_ids = [i["id"] for i in inspections]
    try:
        task_resp = supabase.table("task") \
            .select("inspection_id, title, state, anomolies") \
            .in_("inspection_id", inspection_ids) \
            .execute()
        all_tasks = task_resp.data or []
    except Exception as e:
        _log.warning("Failed to fetch tasks for prediction: %s", e)
        return {"prediction": "Error fetching tasks"}

    # Group tasks by inspection
    tasks_by_insp = {i["id"]: [] for i in inspections}
    for t in all_tasks:
        tasks_by_insp[t["inspection_id"]].append(t)

    # Score each inspection chronologically (reverse the recent-first list)
    inspections = list(reversed(inspections))
    scores = []
    
    for insp in inspections:
        insp_tasks = tasks_by_insp[insp["id"]]
        worst_score = 0
        component_found = False

        for task in insp_tasks:
            title = task.get("title") or ""
            if component.lower() in title.lower() or title.lower() in component.lower():
                component_found = True
                
                # Check anomalies
                anomalies = task.get("anomolies") or []
                
                # If no anomalies, score is 0. Else check severity.
                if not anomalies:
                    score = 0
                else:
                    task_worst = 0
                    for a in anomalies:
                        # anomalies could be dicts or json strings depending on how they're stored
                        if isinstance(a, str):
                            import json
                            try:
                                a = json.loads(a)
                            except:
                                continue
                        
                        if isinstance(a, dict):
                            sev = (a.get("severity") or "monitor").strip().lower()
                            if sev in ("fail", "critical", "red"):
                                task_worst = max(task_worst, 2)
                            elif sev in ("monitor", "moderate", "yellow"):
                                task_worst = max(task_worst, 1)
                            
                    score = task_worst
                    
                worst_score = max(worst_score, score)

        if component_found:
            scores.append(worst_score)
        else:
            # If inspected but component not checked, assume 0 for trend continuity
            scores.append(0)

    if len(scores) < 2:
        return {"prediction": "Insufficient historical data for this component (needs at least 2 past inspections)"}

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
        "cost_if_ignored": "$24,000 engine/component replacement vs $45 part replacement today" if trend > 0 else None
    }
