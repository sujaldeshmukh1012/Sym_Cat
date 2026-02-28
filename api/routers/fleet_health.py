"""
/fleet-health — Fleet health trend analysis.

Fetches recent inspections + tasks for a fleet, parses anomalies,
and returns statistical output showing whether the fleet's health
is degrading, improving, or stable over time.
"""
import json
import logging
from collections import defaultdict
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, HTTPException, Query

from api.routers import supabase

router = APIRouter(prefix="/fleet-health", tags=["Fleet Health"])
_log = logging.getLogger("api.fleet_health")


# ---------------------------------------------------------------------------
# Severity weights — higher = worse
# ---------------------------------------------------------------------------
SEVERITY_WEIGHT = {
    "fail": 3,
    "monitor": 2,
    "normal": 1,
    "pass": 0,
}


def _parse_anomalies(raw_anomalies) -> list[dict]:
    """
    Parse anomalies from the task.anomolies column.
    The column is text[] where each element is a JSON string.
    """
    if not raw_anomalies:
        return []
    results = []
    for item in raw_anomalies:
        if isinstance(item, dict):
            results.append(item)
        elif isinstance(item, str):
            try:
                parsed = json.loads(item)
                if isinstance(parsed, dict):
                    results.append(parsed)
                elif isinstance(parsed, list):
                    results.extend(p for p in parsed if isinstance(p, dict))
            except (json.JSONDecodeError, TypeError):
                pass
    return results


def _compute_inspection_score(tasks: list[dict]) -> float:
    """
    Compute a health score for an inspection based on its tasks.
    Score 0-100 where 100 = perfect health, 0 = critical failures everywhere.
    """
    if not tasks:
        return 100.0

    total_weight = 0
    max_possible = 0

    for task in tasks:
        anomalies = _parse_anomalies(task.get("anomolies"))
        state = (task.get("state") or "pass").strip().lower()

        # Each task contributes to the score
        max_possible += SEVERITY_WEIGHT["fail"]  # worst case per task

        if not anomalies:
            # No anomalies = healthy task
            total_weight += 0
        else:
            # Worst severity among anomalies in this task
            worst = max(
                SEVERITY_WEIGHT.get(
                    (a.get("severity") or "monitor").strip().lower(), 1
                )
                for a in anomalies
            )
            total_weight += worst

        # Also factor in task state
        state_w = SEVERITY_WEIGHT.get(state, 0)
        if state_w > total_weight:
            total_weight = state_w

    if max_possible == 0:
        return 100.0

    # Invert: 0 weight = 100 score, max weight = 0 score
    return round(max(0, (1 - total_weight / max_possible)) * 100, 1)


def _trend_direction(scores: list[float]) -> str:
    """
    Determine trend from a list of chronological scores.
    Returns 'improving', 'degrading', or 'stable'.
    """
    if len(scores) < 2:
        return "stable"

    # Compare first half average vs second half average
    mid = len(scores) // 2
    first_half = scores[:mid] if mid > 0 else scores[:1]
    second_half = scores[mid:]

    avg_first = sum(first_half) / len(first_half)
    avg_second = sum(second_half) / len(second_half)

    diff = avg_second - avg_first
    if diff > 5:
        return "improving"
    elif diff < -5:
        return "degrading"
    return "stable"


@router.get("/{fleet_id}")
async def get_fleet_health(
    fleet_id: int,
    limit: int = Query(10, ge=1, le=50, description="Number of recent inspections to analyze"),
):
    """
    Analyze the health trend of a fleet based on its recent inspections.

    Returns:
    - Fleet info
    - Per-inspection health scores (chronological)
    - Overall trend: improving / degrading / stable
    - Component-level breakdown with severity counts
    - Summary statistics
    """

    # 1. Fetch fleet info
    fleet_resp = supabase.table("fleet").select("*").eq("id", fleet_id).execute()
    if not fleet_resp.data:
        raise HTTPException(status_code=404, detail=f"Fleet {fleet_id} not found")
    fleet = fleet_resp.data[0]

    # 2. Fetch recent inspections for this fleet
    insp_resp = (
        supabase.table("inspection")
        .select("id, created_at, completed_on, customer_name, work_order, location")
        .eq("fleet_serial", fleet_id)
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
    )
    inspections = insp_resp.data or []

    if not inspections:
        return {
            "fleet": fleet,
            "inspections_analyzed": 0,
            "trend": "stable",
            "message": "No inspections found for this fleet.",
            "health_score": None,
            "timeline": [],
            "component_breakdown": {},
            "summary": {},
        }

    inspection_ids = [i["id"] for i in inspections]

    # 3. Fetch all tasks for these inspections
    all_tasks = []
    # Supabase `in_` filter — fetch in batches if needed
    for i in range(0, len(inspection_ids), 20):
        batch = inspection_ids[i : i + 20]
        task_resp = (
            supabase.table("task")
            .select("id, title, state, anomolies, inspection_id, created_at")
            .in_("inspection_id", batch)
            .execute()
        )
        all_tasks.extend(task_resp.data or [])

    # Group tasks by inspection
    tasks_by_inspection: dict[int, list[dict]] = defaultdict(list)
    for t in all_tasks:
        tasks_by_inspection[t["inspection_id"]].append(t)

    # 4. Compute per-inspection scores + component stats
    timeline = []
    component_stats: dict[str, dict] = defaultdict(
        lambda: {"fail": 0, "monitor": 0, "normal": 0, "pass": 0, "total_anomalies": 0, "inspections_seen": 0}
    )
    all_anomalies_flat = []
    severity_totals = {"fail": 0, "monitor": 0, "normal": 0, "pass": 0}

    # Process in chronological order (oldest first)
    for insp in reversed(inspections):
        insp_id = insp["id"]
        insp_tasks = tasks_by_inspection.get(insp_id, [])
        score = _compute_inspection_score(insp_tasks)

        task_summaries = []
        for task in insp_tasks:
            anomalies = _parse_anomalies(task.get("anomolies"))
            state = (task.get("state") or "pass").strip().lower()
            component = task.get("title") or "Unknown"

            # Track component-level stats
            component_stats[component]["inspections_seen"] += 1
            component_stats[component][state] = component_stats[component].get(state, 0) + 1
            component_stats[component]["total_anomalies"] += len(anomalies)

            for a in anomalies:
                sev = (a.get("severity") or "monitor").strip().lower()
                if sev in severity_totals:
                    severity_totals[sev] += 1
                all_anomalies_flat.append(a)

            task_summaries.append({
                "task_id": task["id"],
                "component": component,
                "state": state,
                "anomaly_count": len(anomalies),
                "issues": [a.get("issue", "") for a in anomalies],
            })

        timeline.append({
            "inspection_id": insp_id,
            "date": insp.get("created_at"),
            "health_score": score,
            "task_count": len(insp_tasks),
            "anomaly_count": sum(t["anomaly_count"] for t in task_summaries),
            "tasks": task_summaries,
        })

    # 5. Compute trend
    scores = [t["health_score"] for t in timeline]
    trend = _trend_direction(scores)
    current_score = scores[-1] if scores else None
    previous_score = scores[-2] if len(scores) >= 2 else None

    # 6. Top recurring issues
    issue_counts: dict[str, int] = defaultdict(int)
    for a in all_anomalies_flat:
        issue = a.get("issue", "").strip()
        if issue:
            issue_counts[issue] += 1
    top_issues = sorted(issue_counts.items(), key=lambda x: -x[1])[:10]

    # 7. Component health ranking (worst first)
    component_breakdown = {}
    for comp, stats in component_stats.items():
        fail_rate = stats["fail"] / max(stats["inspections_seen"], 1)
        component_breakdown[comp] = {
            **stats,
            "fail_rate": round(fail_rate, 2),
            "health": "critical" if fail_rate > 0.5 else "warning" if fail_rate > 0.2 else "good",
        }
    # Sort: worst (highest fail_rate) first
    component_breakdown = dict(
        sorted(component_breakdown.items(), key=lambda x: -x[1]["fail_rate"])
    )

    # 8. Build summary
    summary = {
        "inspections_analyzed": len(inspections),
        "total_tasks": len(all_tasks),
        "total_anomalies": len(all_anomalies_flat),
        "severity_distribution": severity_totals,
        "avg_health_score": round(sum(scores) / len(scores), 1) if scores else None,
        "current_health_score": current_score,
        "previous_health_score": previous_score,
        "score_change": round(current_score - previous_score, 1) if current_score is not None and previous_score is not None else None,
        "top_recurring_issues": [{"issue": issue, "count": count} for issue, count in top_issues],
    }

    return {
        "fleet": fleet,
        "trend": trend,
        "health_score": current_score,
        "timeline": timeline,
        "component_breakdown": component_breakdown,
        "summary": summary,
    }
