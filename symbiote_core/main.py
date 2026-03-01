"""
Front door: FastAPI on Modal. Engineer sends image (and optional voice/text) → inspect.
Pipeline: router → analyzer → inventory → response.

Speed optimizations:
- Image resized before base64 encoding (smaller payload to GPU)
- Router skips GPU classify when voice hint is strong enough
- Inspector uses SDPA attention + bfloat16 + keep_warm
- Voice text passed to inspection for better accuracy
"""
import base64
import io
import json

import modal
from fastapi import FastAPI, File, Form, UploadFile
from PIL import Image

from analyzer import Inspector, app
from inventory import check_parts
from router import Router

# Lightweight image for the web endpoint (GPU + model live in analyzer.Inspector)
web_image = (
    modal.Image.debian_slim(python_version="3.11")
    .pip_install("fastapi", "uvicorn[standard]", "python-multipart", "pillow")
    .add_local_python_source("analyzer", "router", "inventory", "logger", "db", "prompts")
)

api = FastAPI(title="CAT Inspect Core", description="AI-powered equipment inspection")


MAX_IMAGE_DIM = 1536  # resize raw camera images before encoding


def _preprocess_image(image_bytes: bytes) -> tuple[bytes, str]:
    """
    Resize + compress raw camera image. Returns (processed_bytes, base64_string).
    Phone cameras produce 4000x3000+ images. Resizing to 1536px max dim:
    - Cuts base64 payload from ~8MB to ~500KB
    - Speeds up vision encoding significantly
    - Keeps enough detail for anomaly detection
    """
    pil = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    w, h = pil.size
    if max(w, h) > MAX_IMAGE_DIM:
        scale = MAX_IMAGE_DIM / max(w, h)
        pil = pil.resize((int(w * scale), int(h * scale)), Image.LANCZOS)

    buf = io.BytesIO()
    pil.save(buf, format="JPEG", quality=90)
    processed = buf.getvalue()
    return processed, base64.b64encode(processed).decode("ascii")


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
    equipment_id: str = Form(""),
    equipment_model: str = Form(""),
):
    image_bytes = await image.read()

    # Preprocess: resize + compress before encoding (big speed win)
    processed_bytes, image_b64 = _preprocess_image(image_bytes)

    combined_text = voice_text or manual_description or ""

    # Step 1: Route to correct subsection prompt
    router = Router()
    component, subsection_prompt = router.identify(processed_bytes, combined_text)

    inspector = Inspector()

    # If we can't confidently classify the component, fall back to baseline prompts
    if component == "Unknown" or not subsection_prompt:
        from prompts.baseline import SYSTEM_PROMPT as BASELINE_SYSTEM_PROMPT

        raw_result = inspector.run_inspection.remote(
            image_b64,
            BASELINE_SYSTEM_PROMPT,
            "Unknown",
            voice_text=combined_text,
        )
        return {
            "component_identified": "Unknown",
            "component_route": "Unknown",
            "overall_status": "YELLOW",
            "anomalies": [],
            "baseline_text": raw_result[:2000],
            "flagged_for_review": True,
            "logged": False,
        }

    # Step 2: Analyze with image + correct prompt + voice context
    try:
        raw_result = inspector.run_inspection.remote(
            image_b64,
            subsection_prompt,
            component,
            voice_text=combined_text,
        )
    except Exception as e:
        return {
            "status": "error",
            "detail": str(e),
            "component_route": component,
        }

    # Step 3: Parse JSON result — analyzer already runs strip_to_json,
    # but handle edge cases where it still fails
    text = raw_result.strip()
    try:
        result = json.loads(text)
    except json.JSONDecodeError:
        # Try stripping markdown fences
        import re
        text = re.sub(r"```(?:json|JSON)?\s*", "", text).replace("```", "").strip()
        start = text.find("{")
        end = text.rfind("}")
        if start != -1 and end > start:
            try:
                result = json.loads(text[start:end+1])
            except json.JSONDecodeError:
                # Last resort: fix trailing commas
                fixed = re.sub(r",\s*([}\]])", r"\1", text[start:end+1])
                try:
                    result = json.loads(fixed)
                except json.JSONDecodeError:
                    result = {
                        "component_identified": component,
                        "anomalies": [],
                        "overall_status": "YELLOW",
                        "raw_response": raw_result[:500],
                    }
        else:
            result = {
                "component_identified": component,
                "anomalies": [],
                "overall_status": "YELLOW",
                "raw_response": raw_result[:500],
            }

    # Step 4: Validate and clean anomalies
    anomalies = result.get("anomalies") or []
    cleaned_anomalies = []
    for a in anomalies:
        if isinstance(a, dict) and a.get("issue"):
            # Normalize severity
            sev = (a.get("severity") or "monitor").strip().lower()
            if sev in ("critical", "red", "fail"):
                a["severity"] = "fail"
            elif sev in ("moderate", "yellow", "monitor"):
                a["severity"] = "monitor"
            elif sev in ("minor", "green", "normal"):
                a["severity"] = "normal"
            else:
                a["severity"] = "monitor"
            cleaned_anomalies.append(a)
    result["anomalies"] = cleaned_anomalies

    # Step 5: Check inventory
    result["parts"] = check_parts(cleaned_anomalies)

    # Step 6: Build final response matching the canonical JSON shape
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

    result["component_identified"] = result.get("component_identified") or component
    result["component_route"] = component

    return result


@api.get("/health")
async def health():
    return {"status": "ok", "model": "Qwen2-VL-7B-Instruct", "gpu": "A10G"}


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
