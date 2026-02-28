"""
Logging layer: write inspection results to Supabase `inspections` table
and auto-populate `order_cart` for parts that need ordering.
Also keeps local Python logging for debugging.
"""
import json
import logging
from datetime import datetime
from typing import Any

_log = logging.getLogger("inspex")


def _severity_to_status(overall: str) -> str:
    """Map model output status to DB enum (RED/YELLOW/GREEN)."""
    s = (overall or "").strip().upper()
    if s in ("CRITICAL", "RED"):
        return "RED"
    if s in ("MODERATE", "YELLOW"):
        return "YELLOW"
    return "GREEN"


def log_inspection(
    component: str,
    subsection_prompt_used: str | None,
    result: dict[str, Any],
    equipment_id: str = "EQ-UNKNOWN",
    machine: str = "Excavator",
) -> str | None:
    """
    Persist inspection to Supabase and create order_cart rows for parts.
    Returns the new inspection UUID, or None if DB insert fails.
    """
    ts = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    anomalies = result.get("anomalies") or []

    # Always log locally
    _log.info(
        "INSPECTION | %s | Component: %s | Prompt: %s | Status: %s | Anomalies: %s",
        ts, component,
        subsection_prompt_used or "N/A",
        result.get("overall_status", "N/A"),
        len(anomalies),
    )

    # --- Write to Supabase ---
    try:
        from db import get_supabase
        sb = get_supabase()

        row = {
            "equipment_id": equipment_id,
            "machine": machine,
            "component": component,
            "overall_status": _severity_to_status(result.get("overall_status", "")),
            "operational_impact": result.get("operational_impact"),
            "anomalies": json.dumps(anomalies),  # JSONB column
        }

        resp = sb.table("inspections").insert(row).execute()
        if not resp.data:
            _log.error("Supabase insert returned no data: %s", resp)
            return None

        inspection_id: str = resp.data[0]["id"]
        _log.info("Inspection saved → %s", inspection_id)

        # --- Populate order_cart for matched parts ---
        parts = result.get("parts") or []
        cart_rows = []
        for p in parts:
            cart_rows.append({
                "inspection_id": inspection_id,
                "part_number": p["part_number"],
                "part_name": p.get("part_name", ""),
                "quantity": p.get("quantity", 1),
                "urgency": p.get("urgency", "Moderate"),
                "status": "pending",
            })
        if cart_rows:
            sb.table("order_cart").insert(cart_rows).execute()
            _log.info("Order cart: %d items created for inspection %s", len(cart_rows), inspection_id)

        return inspection_id

    except Exception as exc:
        _log.error("Failed to persist inspection to Supabase: %s", exc)
        return None

