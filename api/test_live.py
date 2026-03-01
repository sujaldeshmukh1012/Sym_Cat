import asyncio
import base64
import json
import os
import traceback

import aiohttp
import pyaudio
from google import genai
from google.genai import types
from dotenv import load_dotenv

load_dotenv() # Load from .env file

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
GEMINI_API_KEY  = os.environ.get("GEMINI_API_KEY")
INSPEX_BASE_URL = "https://manav-sharma-yeet--inspex-core-fastapi-app-dev.modal.run"
API_BASE_URL    = "http://localhost:8000"   # local FastAPI server
TEST_IMAGE_PATH = "C:/Users/priti/Downloads/Sym_Cat/symbiote_core/data/test/BrokenRimBolt1.jpg"

FORMAT            = pyaudio.paInt16
CHANNELS          = 1
SEND_SAMPLE_RATE  = 16000
RECEIVE_SAMPLE_RATE = 24000
CHUNK_SIZE        = 1024

MODEL = "gemini-2.5-flash-native-audio-preview-12-2025"

SYSTEM_INSTRUCTION = """
You are a highly skilled CAT Equipment Maintenance AI Assistant. 
Your goal is to help service technicians perform inspections and analyze equipment health.

1. **Inspection and Reporting**:
- After `run_inspection`, read the anomalies to the user (e.g. 'I found 2 issues: high rust on rim bolts...').
- Ask if they want to report these findings.
- If they want to change something, use `edit_findings`.
- Once confirmed, call `report_anomalies`.

2. **Predictive Health**:
- When the user asks about fleet health or component failure, use `predict_fleet_health` or `predict_component_health`.
- Explain the data trends and provide a clear recommendation (e.g. 'The hydraulic pump shows a 85% probability of failure within 100 hours. I recommend immediate replacement.').

3. **Inventory & Parts**:
- Finally, ask if they want to check inventory or order parts using `order_parts`.

Keep your verbal responses concise and professional. Use engineering terminology (e.g. 'pitting', 'grouser wear', 'hydraulic seepage').
"""

client = genai.Client(api_key=GEMINI_API_KEY, http_options={'api_version': 'v1alpha'})
pya    = pyaudio.PyAudio()

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
                type="OBJECT",
                properties={
                    "voice_text": types.Schema(
                        type="STRING",
                        description="What the inspector said about the damage"
                    ),
                    "equipment_id": types.Schema(
                        type="STRING",
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
                type="OBJECT",
                properties={
                    "confirmed": types.Schema(
                        type="BOOLEAN",
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
                type="OBJECT",
                properties={
                    "action": types.Schema(
                        type="STRING",
                        description="'update' to change a finding, 'remove' to delete it"
                    ),
                    "finding_number": types.Schema(
                        type="INTEGER",
                        description="Which finding to edit (1, 2, 3, etc.)"
                    ),
                    "new_issue": types.Schema(
                        type="STRING",
                        description="New issue text (for update action)"
                    ),
                    "new_severity": types.Schema(
                        type="STRING",
                        description="New severity: fail, monitor, normal, or pass"
                    ),
                    "new_description": types.Schema(
                        type="STRING",
                        description="New description text (for update action)"
                    ),
                },
                required=["action", "finding_number"],
            ),
        ),

        types.FunctionDeclaration(
            name="predict_fleet_health",
            description=(
                "Analyze the health trend of a fleet. Returns overall trend (improving/degrading), "
                "health score, and top recurring issues. Use when asked 'how is the fleet doing?'."
            ),
            parameters=types.Schema(
                type="OBJECT",
                properties={
                    "equipment_id": types.Schema(
                        type="STRING",
                        description="Equipment ID belonging to the fleet e.g. CAT-320-002"
                    ),
                },
                required=["equipment_id"],
            ),
        ),

        types.FunctionDeclaration(
            name="predict_component_health",
            description=(
                "Predict when a specific component will fail based on historical trends. "
                "Returns days to critical failure. Use when asked 'when will this part break?'."
            ),
            parameters=types.Schema(
                type="OBJECT",
                properties={
                    "equipment_id": types.Schema(
                        type="STRING",
                        description="Equipment ID e.g. CAT-320-002"
                    ),
                    "component": types.Schema(
                        type="STRING",
                        description="Component name e.g. Engine, Hydraulics, Tires"
                    ),
                },
                required=["equipment_id", "component"],
            ),
        ),

    ])
]

LIVE_CONFIG = types.LiveConnectConfig(
    response_modalities=["AUDIO"],
    system_instruction=types.Content(
        parts=[types.Part(text=SYSTEM_INSTRUCTION)]
    ),
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

    elif name == "predict_fleet_health":
        eq_id = args.get("equipment_id")
        if not isinstance(eq_id, str):
            return {"error": "equipment_id must be a string"}
        return await call_fleet_health(eq_id)

    elif name == "predict_component_health":
        eq_id = args.get("equipment_id")
        comp = args.get("component")
        if not isinstance(eq_id, str) or not isinstance(comp, str):
            return {"error": "equipment_id and component must be strings"}
        return await call_predict_component(eq_id, comp)

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

    form = aiohttp.FormData()
    form.add_field(
        "image", image_bytes,
        filename="inspection.jpg",
        content_type="image/jpeg"
    )
    form.add_field("voice_text",     args.get("voice_text", ""))
    form.add_field("equipment_id",   args.get("equipment_id", "CAT-320-002"))
    form.add_field("equipment_model","CAT 320 Excavator")


    try:
        async with aiohttp.ClientSession() as http:
            async with http.post(
                f"{INSPEX_BASE_URL}/inspect",
                data=form,
                timeout=aiohttp.ClientTimeout(total=180)
            ) as resp:
                try:
                    result = await resp.json()
                except Exception as json_err:
                    raw_text = await resp.text()
                    print(f"[DEBUG] Raw response text: {raw_text}")
                    print(f"[ERROR] JSON decode failed: {json_err}")
                    return {"error": str(json_err), "raw_response": raw_text}

        print(f"[INSPECT] Result: {result.get('overall_status')}")
        print(f"[INSPECT] Anomalies: {len(result.get('anomalies', []))}")
        print(f"[INSPECT] Parts: {len(result.get('parts', []))}")

        trimmed = _trim_for_speech(result)
        trimmed["_full"] = result
        return trimmed

    except Exception as e:
        print(f"[ERROR] /inspect call failed: {e}")
        return {"error": str(e)}


async def call_fleet_health(equipment_id: str) -> dict:
    """Fetch fleet health trend from the local API."""
    if not equipment_id:
        return {"error": "Missing equipment_id"}

    # Resolve equipment_id to fleet_id via database
    import sys
    from pathlib import Path
    # Ensure project root is in path for relative imports if needed
    root = Path(__file__).parent.parent
    if str(root) not in sys.path:
        sys.path.append(str(root))
        
    try:
        from api.routers import supabase
    except ImportError:
        return {"error": "Could not import supabase from api.routers"}

    try:
        resp = supabase.table("fleet").select("id").eq("serial_number", equipment_id).execute()
        if not resp.data:
            return {"error": f"Fleet for {equipment_id} not found"}
        fleet_id = resp.data[0]["id"]
    except Exception as e:
        return {"error": f"Failed to resolve fleet: {e}"}

    # Call the fleet-health endpoint
    url = API_BASE_URL
    async with aiohttp.ClientSession() as session:
        async with session.get(f"{url}/fleet-health/{fleet_id}") as resp:
            if resp.status != 200:
                return {"error": f"Fleet health API error: {resp.status}"}
            return await resp.json()


async def call_predict_component(equipment_id: str, component: str) -> dict:
    """Fetch predictive failure scores from the local API."""
    if not equipment_id or not component:
        return {"error": "Missing equipment_id or component"}

    url = API_BASE_URL
    params = {"equipment_id": equipment_id, "component": component}
    async with aiohttp.ClientSession() as session:
        async with session.get(f"{url}/analytics/predict_failure", params=params) as resp:
            if resp.status != 200:
                return {"error": f"Prediction API error: {resp.status}"}
            return await resp.json()


async def call_report_anomalies() -> dict:
    """POST to /report-anomalies on the local API via ngrok."""
    if not last_inspection_result:
        return {"error": "No inspection results available. Run an inspection first."}

    payload = {
        "task_id": TASK_ID,
        "inspection_id": INSPECTION_ID,
        "overall_status": last_inspection_result.get("overall_status", "monitor"),
        "operational_impact": last_inspection_result.get("operational_impact", ""),
        "anomolies": last_inspection_result.get("anomalies") or [],
    }

    print(f"[REPORT] Sending {len(payload['anomolies'])} anomolies to task {TASK_ID}")

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
    Gemini Live has strict payload limits - keep this VERY short.
    Numbers each finding so the inspector can reference them for editing.
    """
    if not isinstance(result, dict):
        return {"error": "Invalid result format from inspector"}

    status = result.get("overall_status", "unknown")
    component = result.get("component_identified", "unknown")
    impact = (result.get("operational_impact") or "")[:120]

    # Numbered findings so inspector can say "change finding 2"
    findings = []
    # backend uses 'anomalies' but returns them as 'anomolies' sometimes in raw response? 
    # Actually analyzer.py uses 'anomalies' (with 'a').
    raw_anoms = result.get("anomalies") or result.get("anomolies") or []
    for i, a in enumerate(raw_anoms[:5], 1):
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
    """Capture mic audio -> input queue."""
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
    """Input queue -> Gemini.  Pauses while speaker is playing or tool call is in flight."""
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
            print("[ERROR] Could not send error tool response - session may be closed")
    finally:
        _tool_idle.set()   # resume mic regardless of success/failure
        print("[TOOL] Mic resumed")


async def receive_from_gemini(session):
    """Receive Gemini responses - audio and tool calls."""
    global _gemini_session
    _gemini_session = session

    while True:
        try:
            turn = session.receive()
            async for response in turn:

                # Audio response -> output queue
                if response.server_content and response.server_content.model_turn:
                    for part in response.server_content.model_turn.parts:
                        if part.inline_data and isinstance(part.inline_data.data, bytes):
                            audio_output_queue.put_nowait(part.inline_data.data)
                        # Print transcript to terminal
                        if hasattr(part, "text") and part.text:
                            print(f"\n[GEMINI] {part.text}")

                # Tool call -> fire as background task so we don't block the receive loop
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
    """Output queue -> speaker.  Sets is_playing flag to mute mic during playback."""
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
    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        print("\nStopped by user.")