import os
import io
from datetime import datetime
from typing import Any

from dotenv import load_dotenv
from jinja2 import Environment, FileSystemLoader
from supabase import Client, create_client

try:
    from xhtml2pdf import pisa
except ImportError:
    pisa = None  # Python 3.14 compatibility — pycairo not yet available

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(dotenv_path=os.path.join(BASE_DIR, ".env"))

# TODO: Call the llm here and save the data in llm_data
# grab task, filter by inspection id [0]
llm_data = {
    "inspection_id": "5",
    "component_identified": "Tire Rim",
    "overall_status": "RED",
    "operational_impact": "Equipment must not operate. Coolant loss risk.",
    "anomalies": [
        {
            "component": "Rim",
            "issue": "Severe Rim Corrosion",
            "description": "Extensive rust and pitting observed on the rim structure, affecting integrity and mounting surfaces.",
            "severity": "Critical",
            "recommended_action": "Immediate replacement of the rim to prevent structural failure.",
        },
        {
            "component": "Wheel Hardware",
            "issue": "Loose or Missing Wheel Hardware",
            "description": "One lug nut is visibly missing, compromising wheel stability and increasing the risk of wheel separation.",
            "severity": "Critical",
            "recommended_action": "Immediate inspection and replacement of missing lug nut; verify all hardware is secure.",
        },
        {
            "component": "Tire",
            "issue": "Moderate Tire Wear",
            "description": "Tread appears worn but still functional; no critical damage to the sidewalls or surface.",
            "severity": "Moderate",
            "recommended_action": "Monitor tread wear and schedule replacement as needed.",
        },
    ],
}

DEFAULT_REPORT_FIELDS = {
    "customer_name": "BORAL RESOURCES P/L",
    "serial_number": "W8210127",
    "model": "982",
    "inspector": "John Doe",
    "date": "28/06/2025",
}


def get_supabase_client() -> Client | None:
    supabase_url = (
        os.getenv("SUPABASE_URL")
        or os.getenv("VITE_SUPABASE_URL")
        or "https://axxxkhxsuigimqragicw.supabase.co"
    )
    supabase_key = (
        os.getenv("SUPABASE_KEY")
        or os.getenv("SUPABASE_ANON_KEY")
        or os.getenv("VITE_SUPABASE_ANON_KEY")
        or "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4eHhraHhzdWlnaW1xcmFnaWN3Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjI1NzYyMywiZXhwIjoyMDg3ODMzNjIzfQ.8xTJC_hCRGdpv3J58UgzDe7BQiWaL5YR-jM7twPvsIQ"
    )

    if not supabase_url or not supabase_key:
        return None

    return create_client(supabase_url, supabase_key)


def build_filter_candidates(value: Any) -> list[Any]:
    candidates = [value]
    if isinstance(value, str) and value.isdigit():
        candidates.append(int(value))
    return candidates


def fetch_row(
    client: Client,
    table_candidates: list[str],
    columns: str,
    filter_column: str,
    filter_value: Any,
) -> tuple[dict[str, Any], str | None]:
    if filter_value is None:
        return {}, None

    for table_name in table_candidates:
        table_query_ok = False
        for candidate in build_filter_candidates(filter_value):
            try:
                response = (
                    client.table(table_name)
                    .select(columns)
                    .eq(filter_column, candidate)
                    .limit(1)
                    .execute()
                )
                table_query_ok = True
                rows = getattr(response, "data", None) or []
                if rows:
                    return rows[0], table_name
            except Exception:
                pass

        if table_query_ok:
            break

    return {}, None


def format_date(created_at: Any) -> str:
    if not created_at:
        return DEFAULT_REPORT_FIELDS["date"]
    try:
        parsed = datetime.fromisoformat(str(created_at).replace("Z", "+00:00"))
        return parsed.strftime("%d/%m/%Y")
    except Exception:
        return DEFAULT_REPORT_FIELDS["date"]


def load_report_fields(inspection_id: str) -> dict[str, str]:
    client = get_supabase_client()
    if not client:
        return DEFAULT_REPORT_FIELDS.copy()

    report_row, report_source = fetch_row(
        client,
        table_candidates=["report", "reports"],
        columns="inspection_id, created_at",
        filter_column="inspection_id",
        filter_value=inspection_id,
    )

    linked_inspection_id = report_row.get("inspection_id") or inspection_id

    inspection_row, inspection_source = fetch_row(
        client,
        table_candidates=["inspection", "inspections"],
        columns="id, created_at, customer_name, inspector, fleet_serial",
        filter_column="id",
        filter_value=linked_inspection_id,
    )

    fleet_row, fleet_source = fetch_row(
        client,
        table_candidates=["fleet", "fleets"],
        columns="id, serial_number, model",
        filter_column="id",
        filter_value=inspection_row.get("fleet_serial"),
    )

    fields = {
        "customer_name": inspection_row.get("customer_name") or DEFAULT_REPORT_FIELDS["customer_name"],
        "serial_number": (
            fleet_row.get("serial_number")
            or inspection_row.get("fleet_serial")
            or DEFAULT_REPORT_FIELDS["serial_number"]
        ),
        "model": str(fleet_row.get("model") or DEFAULT_REPORT_FIELDS["model"]),
        "inspector": str(inspection_row.get("inspector") or DEFAULT_REPORT_FIELDS["inspector"]),
        "date": format_date(report_row.get("created_at") or inspection_row.get("created_at")),
    }

    return fields


supabase_fields = load_report_fields(llm_data["inspection_id"])

report_data = {
    "customer_name": supabase_fields["customer_name"],
    "serial_number": supabase_fields["serial_number"],
    "model": supabase_fields["model"],
    "inspector": supabase_fields["inspector"],
    "date": supabase_fields["date"],
    "inspection_id": llm_data["inspection_id"],
    "component_identified": llm_data["component_identified"],
    "operational_impact": llm_data["operational_impact"],
    "overall_status": "Critical" if llm_data["overall_status"] == "RED" else "Normal",
    "anomalies": llm_data["anomalies"],
}

TEMPLATE_DIR = os.path.join(BASE_DIR, "templates")
template_env = Environment(loader=FileSystemLoader(TEMPLATE_DIR))
template = template_env.get_template("report_template.html")

html_out = template.render(**report_data)
output_filename = "final_inspection_report.pdf"


def generate_report_pdf_bytes(report_payload: dict[str, Any]) -> bytes:
    rendered_html = template.render(**report_payload)
    buffer = io.BytesIO()
    pisa_status = pisa.CreatePDF(rendered_html, dest=buffer)
    if pisa_status.err:
        raise RuntimeError("Failed to generate report PDF")
    return buffer.getvalue()


def convert_html_to_pdf(source_html, output_path):
    try:
        with open(output_path, "wb") as result_file:
            pisa_status = pisa.CreatePDF(source_html, dest=result_file)
        return pisa_status.err
    except PermissionError:
        print(f"\n[ERROR] Close the PDF viewer first! Cannot overwrite {output_path}.\n")
        return True


if __name__ == "__main__":
    if not convert_html_to_pdf(html_out, output_filename):
        print(f"Successfully generated: {output_filename}")
