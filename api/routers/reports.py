import io
import os
from datetime import datetime, timezone
from typing import Any

import boto3
from botocore.config import Config
from fastapi import APIRouter, BackgroundTasks, HTTPException, Query
from pydantic import BaseModel

from api.routers import supabase
from api.pdf_generator import generate_report_pdf_bytes

router = APIRouter(prefix="/reports", tags=["Reports"])

BUCKET_NAME = os.getenv("SUPABASE_BUCKET_NAME")
SUPABASE_URL = os.getenv("SUPABASE_URL")
if not BUCKET_NAME:
    BUCKET_NAME = "inspection_key"
if not SUPABASE_URL:
    SUPABASE_URL = "https://axxxkhxsuigimqragicw.supabase.co"

s3_client = boto3.client(
    "s3",
    endpoint_url=os.getenv("SUPABASE_S3_ENDPOINT") or "https://axxxkhxsuigimqragicw.storage.supabase.co/storage/v1/s3",
    aws_access_key_id=os.getenv("SUPABASE_S3_ACCESS_KEY") or "4e5e5c5168fc5b949f648aa5024489ae",
    aws_secret_access_key=os.getenv("SUPABASE_S3_SECRET_KEY") or "454af5f5895e0fee2a9e9052cd55be3064dc84b80a09c18ff6d728c470fc9ac1",
    region_name=os.getenv("SUPABASE_S3_REGION") or "us-west-2",
    config=Config(s3={"addressing_style": "path"}),
)


class ReportGenerateRequest(BaseModel):
    component_identified: str = "Component"
    overall_status: str = "GREEN"
    operational_impact: str = "No operational impact reported."
    anomalies: list[dict[str, Any]] = []
    tasks: list[Any] = []


def _build_public_url(object_key: str) -> str:
    if not SUPABASE_URL or not BUCKET_NAME:
        raise HTTPException(
            status_code=500,
            detail="SUPABASE_URL and SUPABASE_BUCKET_NAME must be set for report links.",
        )
    return f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET_NAME}/{object_key}"


def _create_pdf_bytes(report_data: dict[str, Any]) -> bytes:
    try:
        return generate_report_pdf_bytes(report_data)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to generate report PDF: {exc}")


def _load_inspection_context(inspection_id: int) -> dict[str, str]:
    inspection_resp = (
        supabase.table("inspection")
        .select("id, created_at, customer_name, inspector, fleet_serial")
        .eq("id", inspection_id)
        .limit(1)
        .execute()
    )
    inspection_rows = inspection_resp.data or []
    if not inspection_rows:
        raise HTTPException(status_code=404, detail="Inspection not found")

    inspection_row = inspection_rows[0]
    fleet_serial = inspection_row.get("fleet_serial")

    fleet_row = {}
    if fleet_serial is not None:
        fleet_resp = (
            supabase.table("fleet")
            .select("id, serial_number, model")
            .eq("id", fleet_serial)
            .limit(1)
            .execute()
        )
        fleet_row = (fleet_resp.data or [{}])[0]

    created_at = inspection_row.get("created_at")
    report_date = datetime.now().strftime("%d/%m/%Y")
    if created_at:
        try:
            parsed = datetime.fromisoformat(str(created_at).replace("Z", "+00:00"))
            report_date = parsed.strftime("%d/%m/%Y")
        except Exception:
            pass

    return {
        "customer_name": str(inspection_row.get("customer_name") or "Unknown Customer"),
        "serial_number": str(fleet_row.get("serial_number") or fleet_serial or "N/A"),
        "model": str(fleet_row.get("model") or "N/A"),
        "inspector": str(inspection_row.get("inspector") or "N/A"),
        "date": report_date,
    }


def _process_generation(report_id: int, inspection_id: int, request_data: ReportGenerateRequest):
    context_fields = _load_inspection_context(inspection_id)

    status = (request_data.overall_status or "GREEN").upper()
    normalized_status = "Critical" if status == "RED" else "Normal"

    report_data = {
        **context_fields,
        "inspection_id": inspection_id,
        "component_identified": request_data.component_identified,
        "operational_impact": request_data.operational_impact,
        "overall_status": normalized_status,
        "anomalies": request_data.anomalies,
    }

    pdf_bytes = _create_pdf_bytes(report_data)

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    object_key = f"reports/inspection_{inspection_id}/report_{report_id}_{timestamp}.pdf"

    s3_client.upload_fileobj(
        io.BytesIO(pdf_bytes),
        BUCKET_NAME,
        object_key,
        ExtraArgs={"ContentType": "application/pdf"},
    )

    public_url = _build_public_url(object_key)
    supabase.table("report").update(
        {
            "report_pdf": public_url,
            "pdf_created": datetime.now(timezone.utc).isoformat(),
        }
    ).eq("id", report_id).execute()


@router.get("")
async def list_reports(inspection_id: int | None = Query(default=None)):
    query = supabase.table("report").select("id, inspection_id, report_pdf, pdf_created, created_at")
    if inspection_id is not None:
        query = query.eq("inspection_id", inspection_id)
    response = query.order("created_at", desc=True).execute()
    return {"data": response.data or []}


@router.post("/generate/{inspection_id}")
async def generate_report(
    inspection_id: int,
    payload: ReportGenerateRequest,
    background_tasks: BackgroundTasks,
    run_async: bool = Query(default=True),
):
    inspection_exists = (
        supabase.table("inspection")
        .select("id")
        .eq("id", inspection_id)
        .limit(1)
        .execute()
    )
    if not (inspection_exists.data or []):
        raise HTTPException(status_code=404, detail="Inspection not found")

    insert_resp = (
        supabase.table("report")
        .insert(
            {
                "inspection_id": inspection_id,
                "tasks": payload.tasks,
            }
        )
        .execute()
    )

    created_rows = insert_resp.data or []
    if not created_rows:
        raise HTTPException(status_code=500, detail="Failed to create report record")

    created_report = created_rows[0]
    report_id = created_report["id"]

    if run_async:
        background_tasks.add_task(_process_generation, report_id, inspection_id, payload)
        return {
            "message": "Report generation started",
            "status": "generating",
            "data": created_report,
        }

    _process_generation(report_id, inspection_id, payload)
    final_resp = supabase.table("report").select("*").eq("id", report_id).limit(1).execute()
    final_rows = final_resp.data or []
    return {
        "message": "Report generated",
        "status": "ready",
        "data": final_rows[0] if final_rows else created_report,
    }
