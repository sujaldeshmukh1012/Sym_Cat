from datetime import datetime
from typing import Literal, Optional

from fastapi import Depends, FastAPI, Header, HTTPException, status
from supabase import create_client, Client
from pydantic import BaseModel, Field
import os
from dotenv import load_dotenv
import uvicorn

load_dotenv()

app = FastAPI()
supabase_url = os.getenv("SUPABASE_URL")
supabase_key = os.getenv("SUPABASE_KEY")

if not supabase_url or not supabase_key:
    raise RuntimeError("SUPABASE_URL and SUPABASE_KEY must be set in the environment.")

supabase: Client = create_client(supabase_url, supabase_key)


class InventoryUpdate(BaseModel):
    name: Optional[str] = None
    part_number: Optional[str] = None
    brand: Optional[str] = None
    quantity: Optional[int] = Field(default=None, ge=0)


class MachineSpecUpdate(BaseModel):
    name: Optional[str] = None
    location: Optional[str] = None
    usecase: Optional[str] = None
    details: Optional[str] = None
    defect_parts: Optional[list[str]] = None
    parts_changed: Optional[list[str]] = None
    changed_at: Optional[datetime] = None


class LogUpdate(BaseModel):
    machine_spec_id: Optional[int] = None
    inspected_at: Optional[datetime] = None
    status: Optional[Literal["Low", "Moderate", "Critical"]] = None
    problem: Optional[str] = None


class ReportUpdate(BaseModel):
    title: Optional[str] = None
    public_url: Optional[str] = None


def _extract_user_id(user: object) -> str:
    user_id = getattr(user, "id", None)
    if not user_id and isinstance(user, dict):
        user_id = user.get("id")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unable to resolve authenticated user",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return str(user_id)


def _validate_payload(payload: dict):
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No fields provided for update",
        )


def _update_row(table: str, row_id: int, payload: dict, user_id: str):
    response = (
        supabase.table(table)
        .update(payload)
        .eq("id", row_id)
        .eq("user_id", user_id)
        .execute()
    )

    updated_rows = getattr(response, "data", None) or []
    if not updated_rows:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"{table} record not found or not owned by current user",
        )
    return updated_rows[0]


async def get_current_user(authorization: Optional[str] = Header(default=None)):
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = authorization.split(" ", 1)[1].strip()
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        auth_response = supabase.auth.get_user(token)
        user = getattr(auth_response, "user", None)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return user


@app.patch("/inventory/{item_id}")
async def update_inventory(
    item_id: int,
    payload: InventoryUpdate,
    current_user=Depends(get_current_user),
):
    update_data = payload.model_dump(exclude_none=True)
    _validate_payload(update_data)
    user_id = _extract_user_id(current_user)
    updated = _update_row("inventory", item_id, update_data, user_id)
    return {"message": "Inventory updated", "data": updated}


@app.patch("/machine_specs/{spec_id}")
async def update_machine_spec(
    spec_id: int,
    payload: MachineSpecUpdate,
    current_user=Depends(get_current_user),
):
    update_data = payload.model_dump(exclude_none=True)
    if "location" in update_data:
        update_data["Location"] = update_data.pop("location")
    _validate_payload(update_data)
    user_id = _extract_user_id(current_user)
    updated = _update_row("machine_specs", spec_id, update_data, user_id)
    return {"message": "Machine spec updated", "data": updated}


@app.patch("/logs/{log_id}")
async def update_log(
    log_id: int,
    payload: LogUpdate,
    current_user=Depends(get_current_user),
):
    update_data = payload.model_dump(exclude_none=True)
    _validate_payload(update_data)
    user_id = _extract_user_id(current_user)
    updated = _update_row("logs", log_id, update_data, user_id)
    return {"message": "Log updated", "data": updated}


@app.patch("/reports/{report_id}")
async def update_report(
    report_id: int,
    payload: ReportUpdate,
    current_user=Depends(get_current_user),
):
    update_data = payload.model_dump(exclude_none=True)
    _validate_payload(update_data)
    user_id = _extract_user_id(current_user)
    updated = _update_row("reports", report_id, update_data, user_id)
    return {"message": "Report updated", "data": updated}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)