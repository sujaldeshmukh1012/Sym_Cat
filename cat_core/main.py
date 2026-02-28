"""
Front door: FastAPI on Modal. Engineer sends image (and optional voice/text) → inspect.
Pipeline: router → analyzer → inventory → logger → response.
"""
import base64
import json

import modal
from fastapi import FastAPI, File, Form, UploadFile

from analyzer import Inspector, app
from inventory import check_parts
from router import Router

# Lightweight image for the web endpoint (GPU + model live in analyzer.Inspector)
web_image = (
    modal.Image.debian_slim(python_version="3.11")
    .pip_install("fastapi", "uvicorn[standard]", "python-multipart")
    .add_local_python_source("analyzer", "router", "inventory", "logger", "db", "prompts")
)

api = FastAPI(title="CAT Inspect Core", description="AI-powered equipment inspection")


@api.post("/classify")
async def classify(
    image: UploadFile = File(...),
    text: str = Form(""),
):
    image_bytes = await image.read()
    router = Router()
    info = router.classify(image_bytes, text)
    return info


@api.post("/inspect")
async def inspect(
    image: UploadFile = File(...),
    voice_text: str = Form(""),
    manual_description: str = Form(""),
    task_id: int = Form(None),
    inspection_id: int = Form(None),
):
    image_bytes = await image.read()
    image_b64 = base64.b64encode(image_bytes).decode("ascii")

    # Step 1: Route to correct subsection prompt (prevents FAIL 1)
    router = Router()
    component, subsection_prompt = router.identify(image_bytes, voice_text or manual_description)

    inspector = Inspector()

    # If we can't confidently classify the component, fall back to baseline prompts
    if component == "Unknown" or not subsection_prompt:
        from prompts.baseline import SYSTEM_PROMPT as BASELINE_SYSTEM_PROMPT

        raw_result = inspector.run_inspection.remote(
            image_b64,
            BASELINE_SYSTEM_PROMPT,
            "Unknown",
        )
        # Do not try to force JSON; return baseline text and flag for review
        return {
            "component_identified": "Unknown",
            "component_route": "Unknown",
            "overall_status": "YELLOW",
            "anomalies": [],
            "baseline_text": raw_result[:2000],
            "flagged_for_review": True,
            "logged": False,
        }

    # Step 2: Analyze (analyzer called here, with image + correct prompt)
    try:
        raw_result = inspector.run_inspection.remote(
            image_b64,
            subsection_prompt,
            component,
        )
    except Exception as e:  # defensive: always return JSON even if remote crashes
        return {
            "status": "error",
            "detail": str(e),
            "component_route": component,
        }

    # Step 3: Parse JSON result (strip markdown code fences if present)
    text = raw_result.strip()
    if text.startswith("```"):
        lines = text.split("\n")
        if lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        text = "\n".join(lines)
    try:
        result = json.loads(text)
    except json.JSONDecodeError:
        result = {
            "component_identified": component,
            "anomalies": [],
            "overall_status": "YELLOW",
            "raw_response": raw_result[:500],
        }

    # Step 4: Check inventory
    result["parts"] = check_parts(result.get("anomalies") or [])

    # Step 5: Build final response matching the canonical JSON shape
    result["inspection_id"] = inspection_id
    result["task_id"] = task_id
    result["machine"] = result.get("machine", "Excavator")
    # Normalize overall_status to fail/monitor/normal/pass
    raw_status = (result.get("overall_status") or "").strip().lower()
    if raw_status in ("critical", "red", "fail"):
        result["overall_status"] = "fail"
    elif raw_status in ("moderate", "yellow", "monitor"):
        result["overall_status"] = "monitor"
    elif raw_status in ("minor", "green", "normal"):
        result["overall_status"] = "normal"
    elif raw_status in ("good", "pass", "none", ""):
        result["overall_status"] = "pass"

    # High-level route vs model-specific label (for debugging classification)
    result["component_identified"] = result.get("component_identified") or component
    result["component_route"] = component
    return result


# Serve API as Modal ASGI app (same app as Inspector)
@app.function(
    image=web_image,
)
@modal.asgi_app()
def fastapi_app():
    return api


# Default when you run: modal run main.py (avoids Modal picking run_inspection and asking for CLI args)
@app.local_entrypoint()
def main():
    """Serve the CAT Inspect API. Web URL is printed below."""
    if hasattr(fastapi_app, "serve"):
        fastapi_app.serve()
    else:
        print("Run the API with: modal serve main.py")
        print("Then open the shown URL and POST to /inspect with image + optional voice_text/manual_description.")
