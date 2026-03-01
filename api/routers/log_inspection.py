import json
import logging
from typing import Optional
from datetime import datetime

from fastapi import APIRouter, File, Form, UploadFile
from pydantic import BaseModel

from api.routers import supabase

router = APIRouter(tags=["Inspection Actions"])
_log = logging.getLogger("api.inspection_actions")


# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------

class AnomalyItem(BaseModel):
    component: str
    issue: str
    description: str = ""
    severity: str = "monitor"          # fail | monitor | normal | pass
    recommended_action: str = ""


class ReportAnomaliesRequest(BaseModel):
    task_id: int
    inspection_id: Optional[int] = None
    overall_status: str = "monitor"
    operational_impact: str = ""
    anomalies: list[AnomalyItem] = []


class ReportAnomaliesResponse(BaseModel):
    task_updated: bool = False
    anomalies_count: int = 0
    error: str = ""


class PartItem(BaseModel):
    part_name: str
    component_tag: str = ""
    quantity: int = 1
    urgency: str = "monitor"


class OrderPartsRequest(BaseModel):
    inspection_id: Optional[int] = None
    parts: list[PartItem] = []


class OrderPartsResponse(BaseModel):
    orders_created: int = 0
    details: list[str] = []
    errors: list[str] = []


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _severity_to_state(overall_status: str) -> str:
    s = overall_status.strip().lower()
    if s == "fail":
        return "fail"
    if s == "monitor":
        return "monitor"
    return "pass"


def _fuzzy_find_part_id(name: str) -> Optional[int]:
    """
    Find a part in the `parts` table using progressively looser matching:
      1. Direct ilike  ('Rim Assembly' matches 'Rim Assembly')
      2. Keyword fallback (try each significant word >= 4 chars)
    """
    try:
        # 1. Direct ilike
        resp = supabase.table("parts").select("id, part_name").ilike("part_name", f"%{name}%").limit(1).execute()
        if resp.data:
            _log.debug("Part match: '%s' -> id=%s", name, resp.data[0]["id"])
            return resp.data[0]["id"]

        # 2. Keyword fallback
        words = [w for w in name.split() if len(w) >= 4 and w.lower() not in ("inch", "with", "assembly")]
        for word in words:
            resp = supabase.table("parts").select("id, part_name").ilike("part_name", f"%{word}%").limit(1).execute()
            if resp.data:
                _log.debug("Part keyword match: '%s' (word '%s') -> id=%s '%s'", name, word, resp.data[0]["id"], resp.data[0]["part_name"])
                return resp.data[0]["id"]
    except Exception as exc:
        _log.warning("Parts lookup failed for '%s': %s", name, exc)
    return None


def _fuzzy_inventory_lookup(component_tag: str, part_name: str = "") -> list[dict]:
    """
    Find inventory rows matching a component. Tries progressively:
      1. Exact eq on component_tag
      2. ilike on component_tag
      3. ilike on part_name in inventory table
      4. Keyword search on component_tag words
      5. Keyword search on part_name words
    """
    try:
        cols = "id, component_tag, part_name, stock_qty"

        # 1. Exact match
        resp = supabase.table("inventory").select(cols).eq("component_tag", component_tag).execute()
        if resp.data:
            return resp.data

        # 2. ilike on component_tag
        resp = supabase.table("inventory").select(cols).ilike("component_tag", f"%{component_tag}%").execute()
        if resp.data:
            return resp.data

        # 3. ilike on part_name
        search = part_name or component_tag
        resp = supabase.table("inventory").select(cols).ilike("part_name", f"%{search}%").execute()
        if resp.data:
            return resp.data

        # 4. Keyword search on component_tag
        for word in [w for w in component_tag.split() if len(w) >= 3 and w.lower() not in ("the", "and", "for")]:
            resp = supabase.table("inventory").select(cols).ilike("component_tag", f"%{word}%").execute()
            if resp.data:
                return resp.data

        # 5. Keyword search on part_name
        for word in [w for w in (part_name or "").split() if len(w) >= 4]:
            resp = supabase.table("inventory").select(cols).ilike("part_name", f"%{word}%").execute()
            if resp.data:
                return resp.data
    except Exception as exc:
        _log.warning("Inventory lookup failed for tag='%s' name='%s': %s", component_tag, part_name, exc)
    return []


@router.post("/report-anomalies")
async def report_anomalies(payload: ReportAnomaliesRequest):
    """
    Save anomalies to the task table.
    Called by Gemini when the inspector confirms reporting findings.
    """
    response = ReportAnomaliesResponse()
    anomalies_dicts = [a.model_dump() for a in payload.anomalies]

    _log.info("report-anomalies: task_id=%s, %d anomalies, status=%s",
              payload.task_id, len(anomalies_dicts), payload.overall_status)

    try:
        # Each anomaly is stored as a JSON string element in the text[] array
        anomalies_json_strings = [json.dumps(a) for a in anomalies_dicts]
        task_update = {
            "anomalies": anomalies_json_strings,   # text[] column (schema typo)
            "state": _severity_to_state(payload.overall_status),
            "description": payload.operational_impact,
        }
        _log.info("task_update payload: %d anomalies, state=%s", len(anomalies_json_strings), task_update["state"])

        resp = (
            supabase.table("task")
            .update(task_update)
            .eq("id", payload.task_id)
            .execute()
        )
        if resp.data:
            response.task_updated = True
            response.anomalies_count = len(anomalies_dicts)
            _log.info("Task %s updated with %d anomalies", payload.task_id, len(anomalies_dicts))
        else:
            response.error = f"Task {payload.task_id} not found"
            _log.warning(response.error)
    except Exception as exc:
        response.error = f"Task update failed: {exc}"
        _log.error(response.error)

    return response


@router.post("/order-parts")
async def order_parts(payload: OrderPartsRequest):
    """
    Check inventory and create order_cart entries for parts with insufficient stock.
    Uses fuzzy matching to handle name mismatches between AI output and DB tables.
    """
    response = OrderPartsResponse()

    cart_rows = []
    for p in payload.parts:
        _log.info("order-parts: part_name='%s' component_tag='%s'", p.part_name, p.component_tag)

        # Step 1: Find matching inventory rows (fuzzy)
        inv_rows = _fuzzy_inventory_lookup(p.component_tag, p.part_name)
        if not inv_rows:
            msg = f"No inventory match for '{p.component_tag}' / '{p.part_name}'"
            _log.warning(msg)
            response.errors.append(msg)
            continue

        # Step 2: Check total stock
        total_stock = sum(int(r.get("stock_qty", 0)) for r in inv_rows)
        if total_stock >= p.quantity:
            response.details.append(f"'{p.part_name}' in stock ({total_stock} available)")
            continue

        # Step 3: Find part_id — try inventory's part_name first, then AI's
        part_id = None
        for inv_row in inv_rows:
            part_id = _fuzzy_find_part_id(inv_row.get("part_name", ""))
            if part_id:
                break
        if not part_id:
            part_id = _fuzzy_find_part_id(p.part_name)

        if part_id is not None:
            cart_rows.append({
                "inspection_id": payload.inspection_id,
                "parts": part_id,
                "quantity": p.quantity,
                "urgency": p.urgency == "fail",
                "status": "pending",
            })
            response.details.append(f"'{p.part_name}' -> part_id={part_id}, stock={total_stock}, ordering {p.quantity}")
        else:
            msg = f"No matching part in parts table for '{p.part_name}'"
            _log.warning(msg)
            response.errors.append(msg)

    if cart_rows:
        try:
            supabase.table("order_cart").insert(cart_rows).execute()
            response.orders_created = len(cart_rows)
            _log.info("Order cart: %d items for inspection %s", len(cart_rows), payload.inspection_id)
        except Exception as exc:
            msg = f"Order cart insert failed: {exc}"
            _log.error(msg)
            response.errors.append(msg)

    return response


# ---------------------------------------------------------------------------
# Quick Log — voice-activated single-issue logging
# ---------------------------------------------------------------------------

def _severity_to_task_state(severity: str) -> str:
    """Map quick-log severity labels to task state values."""
    s = severity.strip().lower()
    if s in ("moderate", "monitor", "fail"):
        return "monitor"
    if s == "pass":
        return "pass"
    return "pending"  # Normal → pending (no action needed yet)


@router.post("/quick-log")
async def quick_log(
    issue: str = Form(...),
    severity: str = Form("Normal"),
    component: str = Form("Unknown"),
    equipment_id: str = Form("CAT-320-002"),
    inspection_id: Optional[int] = Form(None),
    photo: Optional[UploadFile] = File(None),
):
    """
    Quick-log a single issue from the AI passive-listening mode.
    Creates a task row directly — one issue = one task.
    Optionally uploads a photo to Supabase Storage.
    """
    _log.info(
        "quick-log: issue='%s' severity='%s' component='%s' equipment='%s' inspection=%s photo=%s",
        issue, severity, component, equipment_id, inspection_id,
        photo.filename if photo else "none",
    )

    image_urls = []

    # Upload photo if provided
    if photo and photo.filename:
        try:
            photo_bytes = await photo.read()
            bucket = "inspection_key"
            timestamp = int(datetime.now().timestamp())
            remote_path = f"quicklogs/{equipment_id}/{timestamp}_{photo.filename}"
            supabase.storage.from_(bucket).upload(
                remote_path,
                photo_bytes,
                {"content-type": photo.content_type or "image/jpeg"},
            )
            public_url = f"{supabase.supabase_url}/storage/v1/object/public/{bucket}/{remote_path}"
            image_urls.append(public_url)
            _log.info("quick-log: photo uploaded -> %s", public_url)
        except Exception as exc:
            _log.warning("quick-log: photo upload failed: %s", exc)

    # Build task row
    anomaly_json = json.dumps({
        "component": component,
        "issue": issue,
        "severity": severity.lower(),
        "description": issue,
        "recommended_action": "",
    })

    task_state = _severity_to_task_state(severity)
    feedback_text = f"[AI Quick Log] {issue} — {component} ({severity})"

    task_payload = {
        "title": f"Quick Log: {component}",
        "state": task_state,
        "images": image_urls,
        "anomolies": [anomaly_json],
        "description": issue,
        "feedback": feedback_text,
    }

    # Link to inspection if provided
    if inspection_id is not None:
        task_payload["inspection_id"] = inspection_id

    # Resolve fleet_serial from equipment_id
    try:
        fleet_resp = (
            supabase.table("fleet")
            .select("id")
            .ilike("serial_number", f"%{equipment_id}%")
            .limit(1)
            .execute()
        )
        if fleet_resp.data:
            task_payload["fleet_serial"] = fleet_resp.data[0]["id"]
    except Exception as exc:
        _log.warning("quick-log: fleet lookup failed: %s", exc)

    # Figure out next task index
    if inspection_id is not None:
        try:
            existing = (
                supabase.table("task")
                .select("index")
                .eq("inspection_id", inspection_id)
                .order("index", desc=True)
                .limit(1)
                .execute()
            )
            max_idx = existing.data[0]["index"] if existing.data and existing.data[0].get("index") else 0
            task_payload["index"] = (max_idx or 0) + 1
        except Exception:
            task_payload["index"] = 1
    else:
        task_payload["index"] = 1

    # Insert task
    try:
        resp = supabase.table("task").insert(task_payload).execute()
        task_id = resp.data[0]["id"] if resp.data else None
        _log.info("quick-log: task created id=%s", task_id)

        # If linked to an inspection, append to its tasks array
        if inspection_id is not None and task_id is not None:
            try:
                insp = supabase.table("inspection").select("tasks").eq("id", inspection_id).execute()
                current_tasks = insp.data[0].get("tasks") or [] if insp.data else []
                current_tasks.append(task_id)
                supabase.table("inspection").update({"tasks": current_tasks}).eq("id", inspection_id).execute()
            except Exception as exc:
                _log.warning("quick-log: failed to link task to inspection: %s", exc)

        return {
            "success": True,
            "task_id": task_id,
            "issue": issue,
            "severity": severity,
            "component": component,
            "photo_url": image_urls[0] if image_urls else None,
        }

    except Exception as exc:
        _log.error("quick-log: task insert failed: %s", exc)
        return {
            "success": False,
            "error": str(exc),
        }
