"""
/machines — CRUD for the machine table.

Schema:
    id              UUID PK
    created_at      TIMESTAMPTZ
    name            TEXT NOT NULL
    serial_number   TEXT UNIQUE
    type            TEXT
"""
from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from api.routers import supabase, validate_payload

router = APIRouter(prefix="/machines", tags=["Machines"])


# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------

class MachineCreate(BaseModel):
    name: str
    serial_number: Optional[str] = None
    type: Optional[str] = None


class MachineUpdate(BaseModel):
    name: Optional[str] = None
    serial_number: Optional[str] = None
    type: Optional[str] = None


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("")
async def list_machines(
    type: Optional[str] = Query(None),
    limit: int = Query(50, le=200),
):
    """List all machines, optionally filtered by type."""
    q = supabase.table("machine").select("*").order("created_at", desc=True).limit(limit)
    if type:
        q = q.eq("type", type)
    resp = q.execute()
    return {"data": resp.data}


@router.get("/{machine_id}")
async def get_machine(machine_id: str):
    resp = supabase.table("machine").select("*").eq("id", machine_id).execute()
    if not resp.data:
        raise HTTPException(status_code=404, detail="Machine not found")
    return {"data": resp.data[0]}


@router.post("")
async def create_machine(machine: MachineCreate):
    resp = supabase.table("machine").insert(machine.model_dump(exclude_none=True)).execute()
    return {"message": "Machine created", "data": resp.data[0] if resp.data else None}


@router.patch("/{machine_id}")
async def update_machine(machine_id: str, payload: MachineUpdate):
    update_data = payload.model_dump(exclude_none=True)
    validate_payload(update_data)
    resp = supabase.table("machine").update(update_data).eq("id", machine_id).execute()
    if not resp.data:
        raise HTTPException(status_code=404, detail="Machine not found")
    return {"message": "Machine updated", "data": resp.data[0]}


@router.delete("/{machine_id}")
async def delete_machine(machine_id: str):
    resp = supabase.table("machine").delete().eq("id", machine_id).execute()
    if not resp.data:
        raise HTTPException(status_code=404, detail="Machine not found")
    return {"message": "Machine deleted"}
