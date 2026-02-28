"""
/orders — CRUD + place/confirm/decline for the order_cart table.

Schema:
    id              UUID PK
    created_at      TIMESTAMPTZ
    inspection_id   UUID FK → inspections(id) ON DELETE CASCADE
    part_number     TEXT FK → inventory(part_number)
    part_name       TEXT NOT NULL
    quantity        INTEGER DEFAULT 1
    urgency         TEXT NOT NULL           -- "Critical" | "Moderate"
    status          TEXT DEFAULT 'pending'  -- "pending" | "ordered" | "declined"
"""
from typing import Any, Dict, List, Literal, Optional

from fastapi import APIRouter, Body, HTTPException, Query
from pydantic import BaseModel, Field

from api.routers import supabase, validate_payload

router = APIRouter(prefix="/orders", tags=["Order Cart"])


# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------

class OrderCartUpdate(BaseModel):
    quantity: Optional[int] = Field(default=None, ge=1)
    status: Optional[Literal["pending", "ordered", "declined"]] = None


class PlaceOrderRequest(BaseModel):
    inspection_id: str
    parts: List[Dict[str, Any]]


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get("")
async def list_order_cart(
    inspection_id: Optional[str] = Query(None),
    order_status: Optional[str] = Query(None, alias="status"),
):
    """List order cart items, optionally filtered by inspection or status."""
    q = supabase.table("order_cart").select("*").order("created_at", desc=True)
    if inspection_id:
        q = q.eq("inspection_id", inspection_id)
    if order_status:
        q = q.eq("status", order_status)
    resp = q.execute()
    return {"data": resp.data}


@router.patch("/{item_id}")
async def update_order_cart_item(item_id: str, payload: OrderCartUpdate):
    update_data = payload.model_dump(exclude_none=True)
    validate_payload(update_data)
    resp = supabase.table("order_cart").update(update_data).eq("id", item_id).execute()
    if not resp.data:
        raise HTTPException(status_code=404, detail="Order cart item not found")
    return {"message": "Order cart item updated", "data": resp.data[0]}


@router.post("/place")
async def place_order(request: PlaceOrderRequest = Body(...)):
    """
    Place an order from an inspection result.  Checks inventory stock for each
    requested part.  Parts with sufficient stock are added to ``order_cart``
    with status ``ordered`` and inventory is decremented.

    Request body::

        {
          "inspection_id": "uuid",
          "parts": [
            {"part_number": "CAT-LUG-001", "part_name": "Lug Nut M22",
             "quantity": 2, "urgency": "Critical"},
            ...
          ]
        }

    Returns ``{ordered, unavailable, cart_items}``.
    """
    ordered: list[str] = []
    unavailable: list[dict] = []
    cart_items: list[dict] = []

    for part in request.parts:
        part_number = part.get("part_number")
        quantity = int(part.get("quantity", 1))
        urgency = part.get("urgency", "Moderate")
        part_name = part.get("part_name", "")

        # Check inventory stock
        inv = (
            supabase.table("inventory")
            .select("part_number, stock_qty")
            .eq("part_number", part_number)
            .execute()
        )
        stock = inv.data[0]["stock_qty"] if inv.data else 0

        if stock >= quantity:
            cart_row = {
                "inspection_id": request.inspection_id,
                "part_number": part_number,
                "part_name": part_name,
                "quantity": quantity,
                "urgency": urgency,
                "status": "ordered",
            }
            resp = supabase.table("order_cart").insert(cart_row).execute()
            ordered.append(part_number)
            cart_items.append(resp.data[0] if resp.data else cart_row)
            # Decrement inventory
            supabase.table("inventory").update(
                {"stock_qty": stock - quantity}
            ).eq("part_number", part_number).execute()
        else:
            unavailable.append({
                "part_number": part_number,
                "requested": quantity,
                "in_stock": stock,
            })

    return {"ordered": ordered, "unavailable": unavailable, "cart_items": cart_items}


@router.post("/{inspection_id}/confirm")
async def confirm_order(inspection_id: str):
    """Mark all pending items for an inspection as 'ordered'."""
    resp = (
        supabase.table("order_cart")
        .update({"status": "ordered"})
        .eq("inspection_id", inspection_id)
        .eq("status", "pending")
        .execute()
    )
    supabase.table("inspections").update(
        {"order_status": "confirmed"}
    ).eq("id", inspection_id).execute()
    return {"message": f"Confirmed {len(resp.data or [])} items", "data": resp.data}


@router.post("/{inspection_id}/decline")
async def decline_order(inspection_id: str):
    """Mark all pending items for an inspection as 'declined'."""
    resp = (
        supabase.table("order_cart")
        .update({"status": "declined"})
        .eq("inspection_id", inspection_id)
        .eq("status", "pending")
        .execute()
    )
    supabase.table("inspections").update(
        {"order_status": "declined"}
    ).eq("id", inspection_id).execute()
    return {"message": f"Declined {len(resp.data or [])} items", "data": resp.data}
