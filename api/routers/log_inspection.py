import json
import logging
from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from api.routers import supabase

router = APIRouter(tags=["Log Inspection"])
_log = logging.getLogger("api.log_inspection")


# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------

class AnomalyItem(BaseModel):
    component: str
    issue: str
    description: str
    severity: str          # fail | monitor | normal
    recommended_action: str


class PartItem(BaseModel):
    part_number: str
    part_name: str
    component_tag: str
    quantity: int = 1
    unit_price: float = 0
    stock_qty: int = 0
    lead_days: int = 1
    urgency: str = "monitor"
    in_stock: bool = False


class LogInspectionRequest(BaseModel):
    task_id: Optional[int] = None
    inspection_id: Optional[int] = None
    component: str
    overall_status: str                 # fail | monitor | normal | pass
    operational_impact: str = ""
    anomalies: list[AnomalyItem] = []
    parts: list[PartItem] = []


class LogInspectionResponse(BaseModel):
    task_updated: bool = False
    orders_created: int = 0
    inspection_id: Optional[int] = None
    errors: list[str] = []


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _severity_to_state(overall_status: str) -> str:
    """Map overall_status to task state column."""
    s = overall_status.strip().lower()
    if s == "fail":
        return "fail"
    if s == "monitor":
        return "monitor"
    return "pass"


def _lookup_part_id(part_name: str) -> Optional[int]:
    """Look up the parts table to find the part id matching a part name."""
    try:
        resp = (
            supabase.table("parts")
            .select("id")
            .ilike("part_name", f"%{part_name}%")
            .limit(1)
            .execute()
        )
        if resp.data:
            return resp.data[0]["id"]
    except Exception as exc:
        _log.warning("Parts lookup failed for '%s': %s", part_name, exc)
    return None


def _lookup_inventory_stock(component_tag: str) -> int:
    """Check inventory stock_qty for a component tag. Returns 0 if not found."""
    try:
        resp = (
            supabase.table("inventory")
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


# ---------------------------------------------------------------------------
# Endpoint
# ---------------------------------------------------------------------------

@router.post("/log-inspection")
async def log_inspection(payload: LogInspectionRequest):
    """
    Called by Modal /inspect after AI analysis completes.
    1. Updates task row with anomalies
    2. Checks inventory, creates order_cart entries for insufficient stock
    """
    response = LogInspectionResponse(inspection_id=payload.inspection_id)
    anomalies_dicts = [a.model_dump() for a in payload.anomalies]

    if payload.task_id is not None:
        try:
            task_update = {
                "anomolies": anomalies_dicts,       # column name has typo in schema
                "state": _severity_to_state(payload.overall_status),
                "description": payload.operational_impact,
            }
            resp = (
                supabase.table("task")
                .update(task_update)
                .eq("id", payload.task_id)
                .execute()
            )
            if resp.data:
                response.task_updated = True
                _log.info("Task %s updated with %d anomalies", payload.task_id, len(anomalies_dicts))
            else:
                msg = f"Task {payload.task_id} not found"
                _log.warning(msg)
                response.errors.append(msg)
        except Exception as exc:
            msg = f"Task update failed: {exc}"
            _log.error(msg)
            response.errors.append(msg)

    # --- 2. Check inventory and create order_cart entries ---
    cart_rows = []
    for p in payload.parts:
        stock = _lookup_inventory_stock(p.component_tag)
        if stock < p.quantity:
            part_id = _lookup_part_id(p.part_name)
            if part_id is not None:
                cart_rows.append({
                    "inspection_id": payload.inspection_id,
                    "parts": part_id,           # FK to parts.id
                    "quantity": p.quantity,
                    "urgency": p.urgency == "fail",
                    "status": "pending",
                })
            else:
                _log.warning("No matching part found in parts table for '%s', skipping order", p.part_name)

    if cart_rows:
        try:
            supabase.table("order_cart").insert(cart_rows).execute()
            response.orders_created = len(cart_rows)
            _log.info("Order cart: %d items created for inspection %s", len(cart_rows), payload.inspection_id)
        except Exception as exc:
            msg = f"Order cart insert failed: {exc}"
            _log.error(msg)
            response.errors.append(msg)

    return response
