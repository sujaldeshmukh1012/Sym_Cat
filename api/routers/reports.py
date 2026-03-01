import io
import os
import re
from datetime import datetime, timezone
from typing import Any
from urllib.parse import quote, unquote, urlparse

import boto3
from botocore.config import Config
from fastapi import APIRouter, BackgroundTasks, HTTPException, Query, Response
from jinja2 import Environment, FileSystemLoader
from pydantic import BaseModel

from api.routers import supabase
from api.pdf_generator import generate_report_pdf_bytes

router = APIRouter(prefix="/reports", tags=["Reports"])

BUCKET_NAME = os.getenv("SUPABASE_BUCKET_NAME")
SUPABASE_URL = os.getenv("SUPABASE_URL")
if not BUCKET_NAME:
    BUCKET_NAME = "inspection_key"
if not SUPABASE_URL:
    SUPABASE_URL = "https://your-project.supabase.co"

s3_client = boto3.client(
    "s3",
    endpoint_url=os.getenv("SUPABASE_S3_ENDPOINT") or "https://your-project.storage.supabase.co/storage/v1/s3",
    aws_access_key_id=os.getenv("SUPABASE_S3_ACCESS_KEY") or "your_s3_access_key",
    aws_secret_access_key=os.getenv("SUPABASE_S3_SECRET_KEY") or "your_s3_secret_key",
    region_name=os.getenv("SUPABASE_S3_REGION") or "us-west-2",
    config=Config(s3={"addressing_style": "path"}),
)


class ReportGenerateRequest(BaseModel):
    component_identified: str = "Component"
    overall_status: str = "GREEN"
    operational_impact: str = "No operational impact reported."
    anomalies: list[dict[str, Any]] = []
    tasks: list[Any] = []


def _derive_report_title(report_row: dict[str, Any]) -> str:
    tasks = report_row.get("tasks")
    if isinstance(tasks, list):
        for task in tasks:
            if isinstance(task, dict):
                title = task.get("title")
                if title:
                    return str(title)
    inspection_id = report_row.get("inspection_id")
    return f"Inspection {inspection_id} Report" if inspection_id else "Inspection Report"


def _build_public_url(object_key: str) -> str:
    if not SUPABASE_URL or not BUCKET_NAME:
        raise HTTPException(
            status_code=500,
            detail="SUPABASE_URL and SUPABASE_BUCKET_NAME must be set for report links.",
        )
    return f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET_NAME}/{object_key}"


def _extract_object_key(report_pdf: str) -> str:
    if not report_pdf:
        raise HTTPException(status_code=404, detail="Report PDF path is missing")

    normalized = report_pdf.strip()
    if normalized.startswith(("http://", "https://")):
        parsed = urlparse(normalized)
        path = parsed.path.strip("/")
        marker = f"storage/v1/object/public/{BUCKET_NAME}/"
        marker_index = path.find(marker)
        if marker_index != -1:
            return path[marker_index + len(marker) :]
        raise HTTPException(status_code=400, detail="Invalid report_pdf URL format")

    return normalized.lstrip("/")


def _extract_inspection_id_from_key(object_key: str) -> int | None:
    match = re.search(r"inspection_(\d+)", object_key)
    if not match:
        return None
    try:
        return int(match.group(1))
    except ValueError:
        return None


def _extract_report_id_from_key(object_key: str) -> int | None:
    filename = object_key.rsplit("/", 1)[-1]
    match = re.match(r"report_(\d+)_", filename)
    if not match:
        return None
    try:
        return int(match.group(1))
    except ValueError:
        return None


def _list_report_pdf_objects(prefix: str = "reports/") -> list[dict[str, Any]]:
    if not BUCKET_NAME:
        raise HTTPException(status_code=500, detail="SUPABASE_BUCKET_NAME is not configured")

    objects: list[dict[str, Any]] = []
    continuation_token = None

    while True:
        params: dict[str, Any] = {"Bucket": BUCKET_NAME, "Prefix": prefix}
        if continuation_token:
            params["ContinuationToken"] = continuation_token

        response = s3_client.list_objects_v2(**params)
        for obj in response.get("Contents", []):
            key = str(obj.get("Key") or "")
            if key.lower().endswith(".pdf"):
                objects.append(obj)

        if not response.get("IsTruncated"):
            break
        continuation_token = response.get("NextContinuationToken")

    return objects


def _count_report_pdfs_in_s3(prefix: str = "reports/") -> int:
    if not BUCKET_NAME:
        raise HTTPException(status_code=500, detail="SUPABASE_BUCKET_NAME is not configured")

    total = 0
    continuation_token = None

    while True:
        params: dict[str, Any] = {"Bucket": BUCKET_NAME, "Prefix": prefix}
        if continuation_token:
            params["ContinuationToken"] = continuation_token

        response = s3_client.list_objects_v2(**params)
        for obj in response.get("Contents", []):
            key = str(obj.get("Key") or "")
            if key.lower().endswith(".pdf"):
                total += 1

        if not response.get("IsTruncated"):
            break
        continuation_token = response.get("NextContinuationToken")

    return total


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
    pdf_objects = _list_report_pdf_objects(prefix="reports/")

    data = []
    for obj in pdf_objects:
        object_key = str(obj.get("Key") or "")
        parsed_inspection_id = _extract_inspection_id_from_key(object_key)
        if inspection_id is not None and parsed_inspection_id != inspection_id:
            continue

        report_id = _extract_report_id_from_key(object_key)
        created_at = None
        if obj.get("LastModified"):
            try:
                created_at = obj["LastModified"].isoformat()
            except Exception:
                created_at = None

        file_name = object_key.rsplit("/", 1)[-1]
        item = {
            "report_id": report_id,
            "inspection_id": parsed_inspection_id,
            "created_at": created_at,
            "created_by": "—",
            "title": file_name,
            "pdf_link": f"/reports/pdf?key={quote(object_key, safe='')}",
            "report_pdf": _build_public_url(object_key),
        }
        data.append(item)

    data.sort(key=lambda row: row.get("created_at") or "", reverse=True)

    return {"data": data}


@router.get("/pdf")
async def pull_report_pdf_by_key(key: str, download: bool = Query(default=True)):
    if not BUCKET_NAME:
        raise HTTPException(status_code=500, detail="SUPABASE_BUCKET_NAME is not configured")

    object_key = unquote(key).lstrip("/")
    if not object_key:
        raise HTTPException(status_code=400, detail="Missing report object key")

    try:
        s3_object = s3_client.get_object(Bucket=BUCKET_NAME, Key=object_key)
    except Exception:
        raise HTTPException(status_code=404, detail="Report PDF not found in S3")

    file_name = object_key.rsplit("/", 1)[-1] or "report.pdf"
    content = s3_object["Body"].read()
    headers = {}
    if download:
        headers["Content-Disposition"] = f'attachment; filename="{file_name}"'

    return Response(content=content, media_type="application/pdf", headers=headers)


@router.get("/stats")
async def reports_stats():
    db_report_count = 0
    db_error = None
    try:
        db_count_resp = supabase.table("report").select("id", count="exact").limit(0).execute()
        db_report_count = int(db_count_resp.count or 0)
    except Exception as exc:
        db_error = str(exc)

    s3_pdf_count = 0
    s3_error = None
    try:
        s3_pdf_count = int(_count_report_pdfs_in_s3(prefix="reports/"))
    except Exception as exc:
        s3_error = str(exc)

    return {
        "data": {
            "db_report_count": db_report_count,
            "s3_pdf_count": s3_pdf_count,
            "db_error": db_error,
            "s3_error": s3_error,
        }
    }


@router.get("/{report_id}/pdf")
async def pull_report_pdf(report_id: int, download: bool = Query(default=True)):
    if not BUCKET_NAME:
        raise HTTPException(status_code=500, detail="SUPABASE_BUCKET_NAME is not configured")

    report_resp = (
        supabase.table("report")
        .select("id, report_pdf")
        .eq("id", report_id)
        .limit(1)
        .execute()
    )
    rows = report_resp.data or []
    if not rows:
        raise HTTPException(status_code=404, detail="Report not found")

    report_pdf = rows[0].get("report_pdf")
    object_key = _extract_object_key(str(report_pdf or ""))

    try:
        s3_object = s3_client.get_object(Bucket=BUCKET_NAME, Key=object_key)
    except Exception:
        raise HTTPException(status_code=404, detail="Report PDF not found in S3")

    file_name = object_key.rsplit("/", 1)[-1] or f"report_{report_id}.pdf"
    content = s3_object["Body"].read()
    headers = {}
    if download:
        headers["Content-Disposition"] = f'attachment; filename="{file_name}"'

    return Response(content=content, media_type="application/pdf", headers=headers)


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
