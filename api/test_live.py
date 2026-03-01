import asyncio
import argparse
import base64
import json
import os
import traceback

import aiohttp
import pyaudio
import websockets
from google import genai
from google.genai import types

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
GEMINI_API_KEY  = os.getenv("GEMINI_API_KEY", "").strip()
INSPEX_BASE_URL = os.getenv("INSPEX_BASE_URL", "https://manav-sharma-yeet--inspex-core-fastapi-app-dev.modal.run/")
INSPEX_INSPECT_URL = os.getenv("INSPEX_INSPECT_URL", "").strip()
API_BASE_URL    = os.getenv("API_BASE_URL", "http://127.0.0.1:8000")
TEST_IMAGE_PATH = "cat_core/data/test/BrokenRimBolt1.jpg"

FORMAT            = pyaudio.paInt16
CHANNELS          = 1
SEND_SAMPLE_RATE  = 16000
RECEIVE_SAMPLE_RATE = 24000
CHUNK_SIZE        = 1024

MODEL = "gemini-2.5-flash-native-audio-preview-12-2025"
WS_TEXT_MODEL = os.getenv("GEMINI_LIVE_TEXT_MODEL", "gemini-2.5-flash")
LIVE_WS_HOST = os.getenv("LIVE_WS_HOST", "0.0.0.0")
LIVE_WS_PORT = int(os.getenv("LIVE_WS_PORT", "8001"))
LIVE_WS_PATH = os.getenv("LIVE_WS_PATH", "/ws/live-inspection")

client = genai.Client(api_key=GEMINI_API_KEY)
pya    = pyaudio.PyAudio()


async def _post_inspection_request(image_bytes: bytes, voice_text: str, equipment_id: str, equipment_model: str) -> dict:
    def candidate_urls() -> list[str]:
        urls: list[str] = []
        if INSPEX_INSPECT_URL:
            urls.append(INSPEX_INSPECT_URL)
        base = INSPEX_BASE_URL.rstrip("/")
        urls.append(f"{base}/inspect")
        urls.append(base)
        # Common FastAPI prefix fallback
        urls.append(f"{base}/api/inspect")
        # Deduplicate while preserving order
        seen = set()
        unique = []
        for u in urls:
            if u and u not in seen:
                seen.add(u)
                unique.append(u)
        return unique

    form = aiohttp.FormData()
    form.add_field("image", image_bytes, filename="inspection.jpg", content_type="image/jpeg")
    form.add_field("voice_text", voice_text)
    form.add_field("equipment_id", equipment_id)
    form.add_field("equipment_model", equipment_model)

    errors: list[str] = []
    for url in candidate_urls():
        try:
            async with aiohttp.ClientSession() as http:
                # Recreate form each attempt (FormData is one-shot once streamed).
                attempt_form = aiohttp.FormData()
                attempt_form.add_field("image", image_bytes, filename="inspection.jpg", content_type="image/jpeg")
                attempt_form.add_field("voice_text", voice_text)
                attempt_form.add_field("equipment_id", equipment_id)
                attempt_form.add_field("equipment_model", equipment_model)

                async with http.post(
                    url,
                    data=attempt_form,
                    timeout=aiohttp.ClientTimeout(total=180),
                ) as resp:
                    body_text = await resp.text()
                    if resp.status == 200:
                        try:
                            return json.loads(body_text)
                        except Exception:
                            return {"error": f"Inspect endpoint returned non-JSON success at {url}"}
                    errors.append(f"{url} -> {resp.status}: {body_text[:120]}")
                    # Retry other candidates on endpoint-shape mismatch.
                    if "invalid function call" in body_text.lower() or resp.status in (404, 405):
                        continue
                    # For other failures, still continue to next candidate once.
                    continue
        except Exception as e:
            errors.append(f"{url} -> request failed: {e}")

    return {"error": "Inspect endpoint failed. " + " | ".join(errors[:4])}


async def inspect_image_bytes(
    image_bytes: bytes,
    voice_text: str,
    equipment_id: str = "CAT-320-002",
    equipment_model: str = "CAT 320 Excavator",
) -> dict:
    """Wrapper for the relay server."""
    return await _post_inspection_request(image_bytes, voice_text, equipment_id, equipment_model)


async def ws_gemini_reply(user_text: str, context: dict) -> str:
    task_title = str(context.get("task_title") or "").strip()
    task_description = str(context.get("task_description") or "").strip()
    prompt = (
        "You are an AI inspection assistant for CAT heavy equipment. "
        "Keep responses concise and practical. "
        "Ground every answer in the current task context.\n"
        f"inspection_id={context.get('inspection_id', 'unknown')}, "
        f"task_id={context.get('task_id', 'unknown')}\n"
        f"task_title={task_title or 'N/A'}\n"
        f"task_description={task_description or 'N/A'}\n"
        f"Inspector: {user_text}\n"
        "Assistant:"
    )
    try:
        resp = await client.aio.models.generate_content(
            model=WS_TEXT_MODEL,
            contents=prompt,
        )
        text = (resp.text or "").strip()
        return text or "No response generated."
    except Exception as e:
        return f"Gemini reply failed: {e}"


def summarize_inspection_for_ws(result: dict) -> str:
    if not isinstance(result, dict):
        return "Image analyzed."
    if result.get("error"):
        return str(result["error"])

    component = str(result.get("component_identified") or "component")
    status = str(result.get("overall_status") or "unknown").upper()
    anomalies = result.get("anomalies") or []
    if not anomalies:
        return f"Image analyzed: {component}. Status {status}. No anomalies detected."

    top = anomalies[0] if isinstance(anomalies[0], dict) else {}
    issue = str(top.get("issue") or "anomaly detected")
    severity = str(top.get("severity") or "monitor").upper()
    return f"Image analyzed: {component}. Status {status}. Top finding {severity}: {issue}."


def ws_event(event: str, text: str, **extra) -> str:
    payload = {"event": event, "assistant_text": text}
    if extra:
        payload.update(extra)
    return json.dumps(payload)


async def ws_handle_message(websocket, raw: str, context: dict):
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        await websocket.send(ws_event("error", "Invalid JSON message."))
        return

    message_type = payload.get("type")
    if message_type == "start":
        context["inspection_id"] = payload.get("inspection_id")
        context["task_id"] = payload.get("task_id")
        context["equipment_id"] = payload.get("equipment_id") or "CAT-320-002"
        context["equipment_model"] = payload.get("equipment_model") or "CAT 320 Excavator"
        context["task_title"] = payload.get("task_title") or ""
        context["task_description"] = payload.get("task_description") or ""
        context["image_processing"] = False
        context["last_user_text"] = ""
        title = str(context["task_title"]).strip()
        if title:
            await websocket.send(ws_event("session_started", f"Session started for task: {title}. Talk to AI is active."))
        else:
            await websocket.send(ws_event("session_started", "Session started. Talk to AI is active."))
        return

    if message_type == "user_image":
        if context.get("image_processing"):
            await websocket.send(ws_event("image_processing_busy", "Image is already processing. Wait for feedback."))
            return

        encoded = str(payload.get("image_base64", "")).strip()
        if not encoded:
            await websocket.send(ws_event("image_error", "Image payload missing."))
            return
        try:
            image_bytes = base64.b64decode(encoded, validate=True)
        except Exception:
            await websocket.send(ws_event("image_error", "Invalid image payload."))
            return
        if not image_bytes:
            await websocket.send(ws_event("image_error", "Image payload is empty."))
            return

        context["image_processing"] = True
        await websocket.send(ws_event("image_processing_started", "Image received. Analyzing now."))
        try:
            result = await inspect_image_bytes(
                image_bytes=image_bytes,
                voice_text=str(payload.get("note", "Captured inspection image")),
                equipment_id=str(context.get("equipment_id", "CAT-320-002")),
                equipment_model=str(context.get("equipment_model", "CAT 320 Excavator")),
            )
            await websocket.send(ws_event("image_feedback", summarize_inspection_for_ws(result)))
        finally:
            context["image_processing"] = False
        return

    if message_type != "user_transcript":
        await websocket.send(ws_event("error", f"Unsupported type: {message_type}"))
        return

    user_text = str(payload.get("text", "")).strip()
    if not user_text:
        return
    if context.get("image_processing"):
        await websocket.send(ws_event("image_processing_busy", "Image is processing. Wait for analysis before speaking more."))
        return
    if user_text == context.get("last_user_text"):
        return
    context["last_user_text"] = user_text

    lowered = user_text.lower()
    if "capture photo" in lowered or "take photo" in lowered or "[capture_photo]" in lowered:
        await websocket.send("[capture_photo]")
        return

    reply = await ws_gemini_reply(user_text, context)
    await websocket.send(ws_event("assistant_reply", reply))


async def ws_relay_server():
    print(f"[WS] starting relay at ws://{LIVE_WS_HOST}:{LIVE_WS_PORT}{LIVE_WS_PATH}")

    async def handler(websocket):
        req = getattr(websocket, "request", None)
        path = getattr(req, "path", "")
        if path != LIVE_WS_PATH:
            await websocket.close(code=1008, reason=f"Invalid path: {path}")
            return

        context = {}
        print("[WS] client connected")
        await websocket.send(ws_event("relay_connected", "Live relay connected."))
        try:
            async for raw in websocket:
                await ws_handle_message(websocket, raw, context)
        except websockets.ConnectionClosed:
            pass
        finally:
            print("[WS] client disconnected")

    async with websockets.serve(
        handler,
        LIVE_WS_HOST,
        LIVE_WS_PORT,
        max_size=8_000_000,
        ping_interval=20,
        ping_timeout=20,
    ):
        print("[WS] ready")
        await asyncio.Future()

# ---------------------------------------------------------------------------
# Tool definitions
# ---------------------------------------------------------------------------
TOOLS = [
    types.Tool(function_declarations=[

        types.FunctionDeclaration(
            name="run_inspection",
            description=(
                "Run an AI inspection on a CAT equipment component. "
                "Call this when the user describes damage or asks to inspect something."
            ),
            parameters=types.Schema(
                type=types.Type.OBJECT,
                properties={
                    "voice_text": types.Schema(
                        type=types.Type.STRING,
                        description="What the inspector said about the damage"
                    ),
                    "equipment_id": types.Schema(
                        type=types.Type.STRING,
                        description="Equipment ID e.g. CAT-320-002"
                    ),
                },
                required=["voice_text"],
            ),
        ),

        types.FunctionDeclaration(
            name="report_anomalies",
            description=(
                "Save the inspection findings (anomalies) to the task database. "
                "Call this AFTER run_inspection when the inspector confirms they want to report the findings."
            ),
            parameters=types.Schema(
                type=types.Type.OBJECT,
                properties={
                    "confirmed": types.Schema(
                        type=types.Type.BOOLEAN,
                        description="True if the inspector confirmed reporting"
                    ),
                },
                required=["confirmed"],
            ),
        ),

        types.FunctionDeclaration(
            name="edit_findings",
            description=(
                "Modify an inspection finding. Use when the inspector wants to correct, "
                "change severity, or remove a finding. Call BEFORE report_anomalies."
            ),
            parameters=types.Schema(
                type=types.Type.OBJECT,
                properties={
                    "action": types.Schema(
                        type=types.Type.STRING,
                        description="'update' to change a finding, 'remove' to delete it"
                    ),
                    "finding_number": types.Schema(
                        type=types.Type.INTEGER,
                        description="Which finding to edit (1, 2, 3, etc.)"
                    ),
                    "new_issue": types.Schema(
                        type=types.Type.STRING,
                        description="New issue text (for update action)"
                    ),
                    "new_severity": types.Schema(
                        type=types.Type.STRING,
                        description="New severity: fail, monitor, normal, or pass"
                    ),
                    "new_description": types.Schema(
                        type=types.Type.STRING,
                        description="New description text (for update action)"
                    ),
                },
                required=["action", "finding_number"],
            ),
        ),

        types.FunctionDeclaration(
            name="order_parts",
            description=(
                "Check inventory and order replacement parts for the inspection. "
                "Call this AFTER report_anomalies when the inspector confirms they want to order parts."
            ),
            parameters=types.Schema(
                type=types.Type.OBJECT,
                properties={
                    "confirmed": types.Schema(
                        type=types.Type.BOOLEAN,
                        description="True if the inspector confirmed ordering parts"
                    ),
                },
                required=["confirmed"],
            ),
        ),

    ])
]

LIVE_CONFIG = types.LiveConnectConfig(
    response_modalities=["AUDIO"],
    speech_config=types.SpeechConfig(
        voice_config=types.VoiceConfig(
            prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name="Charon")
        )
    ),
    system_instruction=types.Content(parts=[types.Part(text="""
You are an AI inspection assistant for CAT heavy equipment.

FLOW:
1. When the user describes damage or mentions a component, call run_inspection immediately.
   The inspection takes 30-60 seconds (AI vision on GPU). Tell the user
   "Running the inspection now, this will take about 30 seconds" and WAIT
   patiently for the tool response. Do NOT call the tool again.

2. After getting inspection results, read each finding with its NUMBER, severity, and issue.
   Example: "Finding 1: FAIL — severe rim corrosion. Finding 2: MONITOR — missing lug nut."
   Then ask: "Would you like to correct or remove any findings before I save them?"

3. If the inspector wants to change something (e.g. "finding 1 is not rust, it's a scratch",
   "change finding 2 to fail", "remove finding 3"), call edit_findings for each change.
   After editing, read back the updated findings and ask again if they look correct.

4. When the inspector confirms the findings are correct, ask:
   "Should I save these findings to the task database?"
   If yes, call report_anomalies with confirmed=true.
   If no, call report_anomalies with confirmed=false.

5. After reporting, tell the user what parts are needed and ask:
   "Should I check inventory and order replacement parts?"
   If yes, call order_parts with confirmed=true.
   If no, call order_parts with confirmed=false.

Keep responses short and clear.
Current equipment: CAT-320-002, task_id=1, inspection_id=5.
""")]),
    tools=TOOLS,
)


# ---------------------------------------------------------------------------
# Tool executor
# ---------------------------------------------------------------------------
last_inspection_result = None       # full result from /inspect (anomalies, parts, etc.)
TASK_ID = 1
INSPECTION_ID = 5

async def execute_tool(name: str, args: dict) -> dict:
    global last_inspection_result

    print(f"\n[TOOL CALL] {name}")
    print(f"[TOOL ARGS] {json.dumps(args, indent=2)}")

    if name == "run_inspection":
        result = await call_inspect(args)
        # Keep the FULL result for later report/order calls
        last_inspection_result = result.get("_full") or result
        # Return trimmed version to Gemini
        trimmed = result.copy()
        trimmed.pop("_full", None)
        return trimmed

    elif name == "report_anomalies":
        confirmed = args.get("confirmed", False)
        if not confirmed:
            return {"status": "skipped", "message": "Inspector declined to report"}
        return await call_report_anomalies()

    elif name == "order_parts":
        confirmed = args.get("confirmed", False)
        if not confirmed:
            return {"status": "skipped", "message": "Inspector declined to order parts"}
        return await call_order_parts()

    elif name == "edit_findings":
        return edit_findings_in_memory(args)

    return {"error": f"Unknown tool: {name}"}


async def call_inspect(args: dict) -> dict:
    """POST to /inspect on your Modal backend (AI analysis only, no DB writes)."""

    # Load test image from disk (stand-in for camera in terminal test)
    image_path = TEST_IMAGE_PATH
    if not os.path.exists(image_path):
        print(f"[WARNING] Test image not found at {image_path}")
        print("[WARNING] Using placeholder — set TEST_IMAGE env var to a real image")
        # Create a tiny 1x1 white JPEG as fallback
        image_bytes = bytes([
            0xFF,0xD8,0xFF,0xE0,0x00,0x10,0x4A,0x46,0x49,0x46,0x00,0x01,
            0x01,0x00,0x00,0x01,0x00,0x01,0x00,0x00,0xFF,0xDB,0x00,0x43,
            0x00,0x08,0x06,0x06,0x07,0x06,0x05,0x08,0x07,0x07,0x07,0x09,
            0x09,0x08,0x0A,0x0C,0x14,0x0D,0x0C,0x0B,0x0B,0x0C,0x19,0x12,
            0x13,0x0F,0x14,0x1D,0x1A,0x1F,0x1E,0x1D,0x1A,0x1C,0x1C,0x20,
            0x24,0x2E,0x27,0x20,0x22,0x2C,0x23,0x1C,0x1C,0x28,0x37,0x29,
            0x2C,0x30,0x31,0x34,0x34,0x34,0x1F,0x27,0x39,0x3D,0x38,0x32,
            0x3C,0x2E,0x33,0x34,0x32,0xFF,0xC0,0x00,0x0B,0x08,0x00,0x01,
            0x00,0x01,0x01,0x01,0x11,0x00,0xFF,0xC4,0x00,0x1F,0x00,0x00,
            0x01,0x05,0x01,0x01,0x01,0x01,0x01,0x01,0x00,0x00,0x00,0x00,
            0x00,0x00,0x00,0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,
            0x09,0x0A,0x0B,0xFF,0xC4,0x00,0xB5,0x10,0x00,0x02,0x01,0x03,
            0x03,0x02,0x04,0x03,0x05,0x05,0x04,0x04,0x00,0x00,0x01,0x7D,
            0xFF,0xDA,0x00,0x08,0x01,0x01,0x00,0x00,0x3F,0x00,0xFB,0x00,
            0xFF,0xD9
        ])
    else:
        with open(image_path, "rb") as f:
            image_bytes = f.read()

    print(f"[INSPECT] Sending image: {len(image_bytes):,} bytes")
    print(f"[INSPECT] voice_text: {args.get('voice_text', '')}")

    # Use the shared robust request function
    result = await _post_inspection_request(
        image_bytes=image_bytes,
        voice_text=args.get("voice_text", ""),
        equipment_id=args.get("equipment_id", "CAT-320-002"),
        equipment_model="CAT 320 Excavator"
    )

    if result.get("error"):
        print(f"[ERROR] /inspect call failed: {result['error']}")
        return result

    print(f"[INSPECT] Response status: {result.get('overall_status')}")
    print(f"[INSPECT] Anomalies: {len(result.get('anomalies', []))}")
    print(f"[INSPECT] Parts: {len(result.get('parts', []))}")

    # Return trimmed version for Gemini, but stash the full result
    trimmed = _trim_for_speech(result)
    trimmed["_full"] = result
    return trimmed


async def call_report_anomalies() -> dict:
    """POST to /report-anomalies on the local API via ngrok."""
    if not last_inspection_result:
        return {"error": "No inspection results available. Run an inspection first."}

    payload = {
        "task_id": TASK_ID,
        "inspection_id": INSPECTION_ID,
        "overall_status": last_inspection_result.get("overall_status", "monitor"),
        "operational_impact": last_inspection_result.get("operational_impact", ""),
        "anomalies": last_inspection_result.get("anomalies") or [],
    }

    print(f"[REPORT] Sending {len(payload['anomalies'])} anomalies to task {TASK_ID}")

    try:
        async with aiohttp.ClientSession() as http:
            async with http.post(
                f"{API_BASE_URL}/report-anomalies",
                json=payload,
                timeout=aiohttp.ClientTimeout(total=15)
            ) as resp:
                result = await resp.json()

        print(f"[REPORT] Task updated: {result.get('task_updated')}")
        return result

    except Exception as e:
        print(f"[ERROR] /report-anomalies call failed: {e}")
        return {"error": str(e)}


async def call_order_parts() -> dict:
    """POST to /order-parts on the local API via ngrok."""
    if not last_inspection_result:
        return {"error": "No inspection results available. Run an inspection first."}

    raw_parts = last_inspection_result.get("parts") or []
    # Convert to the API's PartItem shape
    parts_payload = []
    for p in raw_parts:
        parts_payload.append({
            "part_name": p.get("part_name", ""),
            "component_tag": p.get("component_tag", ""),
            "quantity": p.get("quantity", 1),
            "urgency": p.get("urgency", "monitor"),
        })

    payload = {
        "inspection_id": INSPECTION_ID,
        "parts": parts_payload,
    }

    print(f"[ORDER] Sending {len(parts_payload)} parts to order-parts")

    try:
        async with aiohttp.ClientSession() as http:
            async with http.post(
                f"{API_BASE_URL}/order-parts",
                json=payload,
                timeout=aiohttp.ClientTimeout(total=15)
            ) as resp:
                result = await resp.json()

        print(f"[ORDER] Orders created: {result.get('orders_created')}")
        return result

    except Exception as e:
        print(f"[ERROR] /order-parts call failed: {e}")
        return {"error": str(e)}


def edit_findings_in_memory(args: dict) -> dict:
    """
    Modify the stored inspection findings before they get reported to the DB.
    The inspector can correct AI hallucinations (e.g. "that's not rust, it's a scratch")
    or adjust severity, or remove a finding entirely.
    """
    global last_inspection_result

    if not last_inspection_result:
        return {"error": "No inspection results to edit. Run an inspection first."}

    anomalies = last_inspection_result.get("anomalies") or []
    action = args.get("action", "update")
    idx = int(args.get("finding_number", 0)) - 1  # convert 1-based to 0-based

    if idx < 0 or idx >= len(anomalies):
        return {"error": f"Finding #{idx+1} does not exist. There are {len(anomalies)} findings."}

    if action == "remove":
        removed = anomalies.pop(idx)
        last_inspection_result["anomalies"] = anomalies
        print(f"[EDIT] Removed finding #{idx+1}: {removed.get('issue')}")
        # Re-check parts after removing an anomaly
        _refresh_parts()
        return {
            "status": "removed",
            "removed": removed.get("issue", ""),
            "remaining_findings": [f"#{i+1} {a.get('severity','?')}: {a.get('issue','?')}" for i, a in enumerate(anomalies)],
        }

    elif action == "update":
        finding = anomalies[idx]
        changes = []
        if "new_issue" in args and args["new_issue"]:
            old = finding.get("issue", "")
            finding["issue"] = args["new_issue"]
            changes.append(f"issue: '{old}' → '{args['new_issue']}'")
        if "new_severity" in args and args["new_severity"]:
            old = finding.get("severity", "")
            finding["severity"] = args["new_severity"]
            changes.append(f"severity: '{old}' → '{args['new_severity']}'")
        if "new_description" in args and args["new_description"]:
            finding["description"] = args["new_description"]
            changes.append(f"description updated")

        anomalies[idx] = finding
        last_inspection_result["anomalies"] = anomalies
        print(f"[EDIT] Updated finding #{idx+1}: {', '.join(changes)}")
        # Re-check parts after modifying anomalies
        _refresh_parts()
        return {
            "status": "updated",
            "changes": changes,
            "updated_findings": [f"#{i+1} {a.get('severity','?')}: {a.get('issue','?')}" for i, a in enumerate(anomalies)],
        }

    return {"error": f"Unknown action: {action}. Use 'update' or 'remove'."}


def _refresh_parts():
    """
    After anomaly edits, remove parts whose component no longer has a matching anomaly.
    This keeps parts_needed in sync with the edited findings.
    """
    global last_inspection_result
    if not last_inspection_result:
        return
    anomaly_components = {a.get("component", "") for a in (last_inspection_result.get("anomalies") or [])}
    original_parts = last_inspection_result.get("parts") or []
    filtered = [p for p in original_parts if p.get("component_tag", "") in anomaly_components]
    last_inspection_result["parts"] = filtered
    print(f"[EDIT] Parts filtered: {len(original_parts)} → {len(filtered)} (matching {len(anomaly_components)} components)")


def _trim_for_speech(result: dict) -> dict:
    """
    Cut down the full inspection JSON to a minimal dict that Gemini can speak.
    Gemini Live has strict payload limits — keep this VERY short.
    Numbers each finding so the inspector can reference them for editing.
    """
    status = result.get("overall_status", "unknown")
    component = result.get("component_identified", "unknown")
    impact = (result.get("operational_impact") or "")[:120]

    # Numbered findings so inspector can say "change finding 2"
    findings = []
    for i, a in enumerate((result.get("anomalies") or [])[:5], 1):
        sev = a.get("severity", "?")
        issue = a.get("issue", "unknown issue")
        findings.append(f"#{i} {sev}: {issue}")

    # Max 3 parts
    parts = []
    for p in (result.get("parts") or [])[:3]:
        name = p.get("part_name", "part")
        parts.append(name)

    return {
        "status": status,
        "component": component,
        "impact": impact,
        "findings": findings,
        "parts_needed": parts,
    }


# ---------------------------------------------------------------------------
# Audio queues
# ---------------------------------------------------------------------------
audio_output_queue = asyncio.Queue()
audio_input_queue  = asyncio.Queue(maxsize=10)
audio_stream_in    = None
is_playing         = False          # True while Gemini audio is being spoken

# Event: set = no tool in flight, clear = tool running (mic paused)
_tool_idle = asyncio.Event()
_tool_idle.set()  # idle initially


async def listen_mic():
    """Capture mic audio → input queue."""
    global audio_stream_in
    mic_info = pya.get_default_input_device_info()
    audio_stream_in = await asyncio.to_thread(
        pya.open,
        format=FORMAT,
        channels=CHANNELS,
        rate=SEND_SAMPLE_RATE,
        input=True,
        input_device_index=mic_info["index"],
        frames_per_buffer=CHUNK_SIZE,
    )
    print("[MIC] Listening... speak now")
    while True:
        data = await asyncio.to_thread(audio_stream_in.read, CHUNK_SIZE, exception_on_overflow=False)
        await audio_input_queue.put({"data": data, "mime_type": "audio/pcm"})


async def send_mic_to_gemini(session):
    """Input queue → Gemini.  Pauses while speaker is playing or tool call is in flight."""
    while True:
        chunk = await audio_input_queue.get()
        if is_playing or not _tool_idle.is_set():
            continue          # drop mic frames while Gemini speaks or tool is running
        await session.send_realtime_input(audio=chunk)


# Store session ref so background tasks can send tool responses
_gemini_session = None


async def _handle_tool_call(session, fn_call):
    """Execute a tool call in the background and send the response back to Gemini."""
    _tool_idle.clear()   # pause mic while tool is running
    print(f"[TOOL] Mic paused while '{fn_call.name}' executes...")
    try:
        tool_result = await execute_tool(fn_call.name, dict(fn_call.args))

        # Safety: ensure the serialized response is under 2KB to avoid 1008 policy errors
        serialized = json.dumps(tool_result, default=str)
        if len(serialized) > 2000:
            print(f"[WARN] Tool response too large ({len(serialized)} chars), truncating")
            tool_result = {
                "status": tool_result.get("status", "complete"),
                "component": tool_result.get("component", ""),
                "summary": serialized[:800],
            }

        print(f"[TOOL] Sending tool response to Gemini ({len(json.dumps(tool_result))} chars)")
        await session.send_tool_response(
            function_responses=[
                types.FunctionResponse(
                    id=fn_call.id,
                    name=fn_call.name,
                    response=tool_result,
                )
            ]
        )
        print("[TOOL] Tool response sent successfully")
    except Exception as e:
        print(f"\n[ERROR] Tool call '{fn_call.name}' failed: {e}")
        # Try to send an error response so Gemini doesn't hang
        try:
            await session.send_tool_response(
                function_responses=[
                    types.FunctionResponse(
                        id=fn_call.id,
                        name=fn_call.name,
                        response={"error": f"Tool call failed: {e}"},
                    )
                ]
            )
        except Exception:
            print("[ERROR] Could not send error tool response — session may be closed")
    finally:
        _tool_idle.set()   # resume mic regardless of success/failure
        print("[TOOL] Mic resumed")


async def receive_from_gemini(session):
    """Receive Gemini responses — audio and tool calls."""
    global _gemini_session
    _gemini_session = session

    while True:
        try:
            turn = session.receive()
            async for response in turn:

                # Audio response → output queue
                if response.server_content and response.server_content.model_turn:
                    for part in response.server_content.model_turn.parts:
                        if part.inline_data and isinstance(part.inline_data.data, bytes):
                            audio_output_queue.put_nowait(part.inline_data.data)
                        # Print transcript to terminal
                        if hasattr(part, "text") and part.text:
                            print(f"\n[GEMINI] {part.text}")

                # Tool call → fire as background task so we don't block the receive loop
                if response.tool_call:
                    for fn_call in response.tool_call.function_calls:
                        asyncio.create_task(_handle_tool_call(session, fn_call))

                # If the server signals turn is complete, check for interruption
                if response.server_content and response.server_content.interrupted:
                    # User genuinely interrupted — flush remaining audio
                    while not audio_output_queue.empty():
                        audio_output_queue.get_nowait()

        except Exception as e:
            print(f"\n[ERROR] receive_from_gemini: {e}")
            break


async def play_speaker():
    """Output queue → speaker.  Sets is_playing flag to mute mic during playback."""
    global is_playing
    stream = await asyncio.to_thread(
        pya.open,
        format=FORMAT,
        channels=CHANNELS,
        rate=RECEIVE_SAMPLE_RATE,
        output=True,
    )
    while True:
        chunk = await audio_output_queue.get()
        is_playing = True
        await asyncio.to_thread(stream.write, chunk)
        # If no more chunks are queued right now, mark playback done
        if audio_output_queue.empty():
            await asyncio.sleep(0.15)       # small grace period for next chunk
            if audio_output_queue.empty():
                is_playing = False


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
async def run():
    print("=" * 60)
    print("  inspex-live terminal test")
    print("=" * 60)
    print(f"  Modal backend : {INSPEX_BASE_URL}")
    print(f"  Test image    : {TEST_IMAGE_PATH}")
    print(f"  Gemini model  : {MODEL}")
    print("=" * 60)
    print("\nTry saying:")
    print('  "The front left rim looks rusty and I think a lug nut is missing"')
    print('  "Inspect the cooling system hose, it looks cracked"')
    print('  "What is the status of the hydraulics?"')
    print("\nUse headphones. Press Ctrl+C to stop.\n")

    try:
        async with client.aio.live.connect(model=MODEL, config=LIVE_CONFIG) as session:
            print("[GEMINI] Connected. Start speaking!\n")

            tasks = [
                asyncio.create_task(listen_mic()),
                asyncio.create_task(send_mic_to_gemini(session)),
                asyncio.create_task(receive_from_gemini(session)),
                asyncio.create_task(play_speaker()),
            ]

            # Wait until any task finishes (e.g. connection drop) then cancel the rest
            done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_EXCEPTION)
            for t in pending:
                t.cancel()
            # Re-raise if a task failed
            for t in done:
                if t.exception():
                    raise t.exception()

    except asyncio.CancelledError:
        pass
    except KeyboardInterrupt:
        pass
    except Exception as e:
        print(f"\n[ERROR] {e}")
        traceback.print_exc()
    finally:
        if audio_stream_in:
            try:
                audio_stream_in.close()
            except Exception:
                pass
        pya.terminate()
        print("\n[DONE] Connection closed.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--mode",
        choices=["terminal", "ws-relay"],
        default="terminal",
        help="terminal: local mic test, ws-relay: websocket endpoint for iOS app",
    )
    args = parser.parse_args()

    try:
        if args.mode == "ws-relay":
            asyncio.run(ws_relay_server())
        else:
            asyncio.run(run())
    except KeyboardInterrupt:
        print("\nStopped by user.")
