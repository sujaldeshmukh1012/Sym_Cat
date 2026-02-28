"""
/inspections — CRUD for the inspections table.

Schema:
    id                  UUID PK
    created_at          TIMESTAMPTZ
    equipment_id        TEXT NOT NULL
    machine             TEXT NOT NULL DEFAULT 'Excavator'
    component           TEXT NOT NULL
    overall_status      TEXT NOT NULL           -- "RED" | "YELLOW" | "GREEN"
    anomalies           JSONB NOT NULL DEFAULT '[]'
    order_status        TEXT DEFAULT 'awaiting_confirmation'
    report_url          TEXT
"""
from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from api.routers import supabase, validate_payload

router = APIRouter(prefix="/inspections", tags=["Inspections"])


# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------

class InspectionCreate(BaseModel):
    equipment_id: str
    machine: str = "Excavator"
    component: str
    overall_status: str                    # RED | YELLOW | GREEN
    anomalies: list | dict = []
    order_status: str = "awaiting_confirmation"
    report_url: Optional[str] = None


class InspectionUpdate(BaseModel):
    order_status: Optional[str] = None
    report_url: Optional[str] = None


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("")
async def list_inspections(
    equipment_id: Optional[str] = Query(None),
    overall_status: Optional[str] = Query(None),
    component: Optional[str] = Query(None),
    limit: int = Query(50, le=200),
):
    """List inspections, optionally filtered."""
    q = supabase.table("inspection").select("*").order("created_at", desc=True).limit(limit)
    if equipment_id:
        q = q.eq("equipment_id", equipment_id)
    if overall_status:
        q = q.eq("overall_status", overall_status.upper())
    if component:
        q = q.eq("component", component)
    resp = q.execute()
    return {"data": resp.data}


@router.get("/{inspection_id}")
async def get_inspection(inspection_id: str):
    resp = supabase.table("inspections").select("*").eq("id", inspection_id).execute()
    if not resp.data:
        raise HTTPException(status_code=404, detail="Inspection not found")
    return {"data": resp.data[0]}


@router.post("")
async def create_inspection(inspection: InspectionCreate):
    resp = supabase.table("inspections").insert(inspection.model_dump()).execute()
    return {"message": "Inspection created", "data": resp.data[0] if resp.data else None}


@router.patch("/{inspection_id}")
async def update_inspection(inspection_id: str, payload: InspectionUpdate):
    update_data = payload.model_dump(exclude_none=True)
    validate_payload(update_data)
    resp = supabase.table("inspections").update(update_data).eq("id", inspection_id).execute()
    if not resp.data:
        raise HTTPException(status_code=404, detail="Inspection not found")
    return {"message": "Inspection updated", "data": resp.data[0]}


@router.delete("/{inspection_id}")
async def delete_inspection(inspection_id: str):
    resp = supabase.table("inspections").delete().eq("id", inspection_id).execute()
    if not resp.data:
        raise HTTPException(status_code=404, detail="Inspection not found")
    return {"message": "Inspection deleted"}
