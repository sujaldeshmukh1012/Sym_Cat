"""
Logging layer: write inspection results to Supabase `task` table (anomalies update)
and auto-populate `order_cart` for parts that need ordering.
Also keeps local Python logging for debugging.
"""
import json
import logging
from datetime import datetime
from typing import Any

_log = logging.getLogger("inspex")


def _normalize_severity(severity: str) -> str:
    """Normalize model severity output to fail/monitor/normal/pass."""
    s = (severity or "").strip().lower()
    if s in ("critical", "red", "fail"):
        return "fail"
    if s in ("moderate", "yellow", "monitor"):
        return "monitor"
    if s in ("minor", "green", "normal"):
        return "normal"
    if s in ("good", "pass", "none"):
        return "pass"
    return "normal"


def _severity_to_state(overall: str) -> str:
    """Map overall_status to task state."""
    s = _normalize_severity(overall)
    if s == "fail":
        return "fail"
    if s == "monitor":
        return "monitor"
    return "pass"


def _lookup_part_id(sb, component_name: str) -> int | None:
    """Look up the parts table to find the part id matching a component name."""
    try:
        resp = (
            sb.table("parts")
            .select("id")
            .ilike("part_name", f"%{component_name}%")
            .limit(1)
            .execute()
        )
        if resp.data:
            return resp.data[0]["id"]
    except Exception as exc:
        _log.warning("Parts lookup failed for '%s': %s", component_name, exc)
    return None


def _lookup_inventory_stock(sb, component_tag: str) -> int:
    """Check inventory stock_qty for a component tag. Returns 0 if not found."""
    try:
        resp = (
            sb.table("inventory")
            .select("stock_qty")
            .eq("component_tag", component_tag)
            .limit(1)
            .execute()
        )
        if resp.data:
            return int(resp.data[0].get("stock_qty", 0))
    except Exception as exc:
        _log.warning("Inventory lookup failed for '%s': %s", component_tag, exc)
    return 0


def log_inspection(
    component: str,
    subsection_prompt_used: str | None,
    result: dict[str, Any],
    task_id: int | None = None,
    inspection_id: int | None = None,
    equipment_id: str = "EQ-UNKNOWN",
    machine: str = "Excavator",
) -> dict[str, Any]:
    """
    1. Update the task table entry with anomalies (matching task_id).
    2. Check inventory for insufficient parts and create order_cart entries.
    3. Return dict with task_updated, orders_created, and inspection_id.
    """
    ts = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    anomalies = result.get("anomalies") or []

    # Normalize severity in each anomaly
    for a in anomalies:
        a["severity"] = _normalize_severity(a.get("severity", ""))

    # Normalize overall_status
    result["overall_status"] = _normalize_severity(result.get("overall_status", ""))

    # Always log locally
    _log.info(
        "INSPECTION | %s | Component: %s | Prompt: %s | Status: %s | Anomalies: %s",
        ts, component,
        subsection_prompt_used or "N/A",
        result.get("overall_status", "N/A"),
        len(anomalies),
    )

    response = {
        "task_updated": False,
        "orders_created": 0,
        "inspection_id": inspection_id,
    }

    try:
        from db import get_supabase
        sb = get_supabase()

        # --- 1. Update the task table entry with anomalies ---
        if task_id is not None:
            task_update = {
                "anomolies": json.dumps(anomalies),  # column is "anomolies" (typo in schema)
                "state": _severity_to_state(result.get("overall_status", "")),
                "description": result.get("operational_impact", ""),
            }
            resp = sb.table("task").update(task_update).eq("id", task_id).execute()
            if resp.data:
                response["task_updated"] = True
                _log.info("Task %s updated with %d anomalies", task_id, len(anomalies))
            else:
                _log.warning("Task %s not found or update failed", task_id)

        # --- 2. Check inventory and create order_cart entries ---
        parts = result.get("parts") or []
        cart_rows = []
        for p in parts:
            component_tag = p.get("component_tag", "")
            stock = _lookup_inventory_stock(sb, component_tag)

            # Only order if stock is insufficient (0 or less than needed)
            needed_qty = p.get("quantity", 1)
            if stock < needed_qty:
                # Look up the part_id from the parts table (FK requirement)
                part_id = _lookup_part_id(sb, p.get("part_name", ""))
                if part_id is not None:
                    cart_rows.append({
                        "inspection_id": inspection_id,
                        "parts": part_id,  # FK to parts.id
                        "quantity": needed_qty,
                        "urgency": p.get("urgency", "monitor") == "fail",
                        "status": "pending",
                    })

        if cart_rows:
            sb.table("order_cart").insert(cart_rows).execute()
            response["orders_created"] = len(cart_rows)
            _log.info("Order cart: %d items created for inspection %s", len(cart_rows), inspection_id)

        return response

    except Exception as exc:
        _log.error("Failed to persist inspection to Supabase: %s", exc)
        response["error"] = str(exc)
        return response

