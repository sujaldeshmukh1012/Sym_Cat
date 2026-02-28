"""
/inventory — CRUD for the inventory table.

Schema:
    part_number     TEXT PK
    part_name       TEXT NOT NULL
    component_tag   TEXT NOT NULL
    stock_qty       INTEGER DEFAULT 0
    unit_price      NUMERIC(10,2)
    machine_id      UUID FK → machine(id) ON DELETE SET NULL
"""
from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from api.routers import supabase, validate_payload

router = APIRouter(prefix="/inventory", tags=["Inventory"])


# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------

class InventoryCreate(BaseModel):
    part_number: str
    part_name: str
    component_tag: str
    stock_qty: int = 0
    unit_price: Optional[float] = None
    machine_id: Optional[str] = None       # UUID of the machine this part belongs to


class InventoryUpdate(BaseModel):
    part_name: Optional[str] = None
    component_tag: Optional[str] = None
    stock_qty: Optional[int] = Field(default=None, ge=0)
    unit_price: Optional[float] = None
    machine_id: Optional[str] = None


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("")
async def list_inventory(
    component_tag: Optional[str] = Query(None),
    machine_id: Optional[str] = Query(None),
):
    """List inventory, optionally filtered by component_tag or machine_id."""
    q = supabase.table("inventory").select("*")
    if component_tag:
        q = q.eq("component_tag", component_tag)
    if machine_id:
        q = q.eq("machine_id", machine_id)
    resp = q.execute()
    return {"data": resp.data}


@router.get("/{part_number}")
async def get_inventory_item(part_number: str):
    resp = supabase.table("inventory").select("*").eq("part_number", part_number).execute()
    if not resp.data:
        raise HTTPException(status_code=404, detail="Part not found")
    return {"data": resp.data[0]}


@router.post("")
async def create_inventory_item(item: InventoryCreate):
    resp = supabase.table("inventory").insert(item.model_dump(exclude_none=True)).execute()
    return {"message": "Part added", "data": resp.data[0] if resp.data else None}


@router.patch("/{part_number}")
async def update_inventory_item(part_number: str, payload: InventoryUpdate):
    update_data = payload.model_dump(exclude_none=True)
    validate_payload(update_data)
    resp = supabase.table("inventory").update(update_data).eq("part_number", part_number).execute()
    if not resp.data:
        raise HTTPException(status_code=404, detail="Part not found")
    return {"message": "Part updated", "data": resp.data[0]}


@router.delete("/{part_number}")
async def delete_inventory_item(part_number: str):
    resp = supabase.table("inventory").delete().eq("part_number", part_number).execute()
    if not resp.data:
        raise HTTPException(status_code=404, detail="Part not found")
    return {"message": "Part deleted"}
