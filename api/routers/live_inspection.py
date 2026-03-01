import json
import os
from typing import Any

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

router = APIRouter(tags=["Live Inspection"])


SYSTEM_PROMPT = """You are an AI inspection assistant for CAT heavy equipment.
Keep responses short and practical.
If the inspector asks to capture a photo, respond with [capture_photo].
Otherwise answer with one concise sentence."""


async def _gemini_text_reply(user_text: str, context: dict[str, Any]) -> str:
    api_key = os.getenv("GEMINI_API_KEY", "").strip()
    if not api_key:
        return "Gemini key is missing on server. Set GEMINI_API_KEY."

    try:
        from google import genai
    except Exception:
        return "Server missing google-genai package. Install dependency and restart."

    model = os.getenv("GEMINI_LIVE_TEXT_MODEL", "gemini-2.5-flash")
    inspection_id = context.get("inspection_id", "unknown")
    task_id = context.get("task_id", "unknown")
    prompt = (
        f"{SYSTEM_PROMPT}\n\n"
        f"inspection_id={inspection_id}, task_id={task_id}\n"
        f"Inspector said: {user_text}\n"
        "Assistant:"
    )

    try:
        client = genai.Client(api_key=api_key)
        response = await client.aio.models.generate_content(
            model=model,
            contents=prompt,
        )
        text = (response.text or "").strip()
        return text or "No response generated."
    except Exception as exc:
        return f"Gemini request failed: {exc}"


@router.websocket("/ws/live-inspection")
async def live_inspection_socket(websocket: WebSocket):
    await websocket.accept()
    context: dict[str, Any] = {}
    print("[LiveRelay] connected")

    await websocket.send_text(json.dumps({
        "assistant_text": "Live inspection relay connected."
    }))

    try:
        while True:
            raw = await websocket.receive_text()
            print(f"[LiveRelay] recv={raw[:400]}")

            try:
                payload = json.loads(raw)
            except json.JSONDecodeError:
                await websocket.send_text(json.dumps({
                    "assistant_text": "Invalid message format."
                }))
                continue

            message_type = payload.get("type")
            if message_type == "start":
                context["inspection_id"] = payload.get("inspection_id")
                context["task_id"] = payload.get("task_id")
                await websocket.send_text(json.dumps({
                    "assistant_text": "Session started. Talk to AI is active."
                }))
                continue

            if message_type != "user_transcript":
                await websocket.send_text(json.dumps({
                    "assistant_text": f"Unsupported message type: {message_type}"
                }))
                continue

            user_text = str(payload.get("text", "")).strip()
            if not user_text:
                continue

            lowered = user_text.lower()
            if "capture photo" in lowered or "take photo" in lowered or "[capture_photo]" in lowered:
                await websocket.send_text("[capture_photo]")
                continue

            assistant_text = await _gemini_text_reply(user_text, context)
            await websocket.send_text(json.dumps({"assistant_text": assistant_text}))
    except WebSocketDisconnect:
        print("[LiveRelay] disconnected")
    except Exception as exc:
        print(f"[LiveRelay] error={exc}")
        try:
            await websocket.send_text(json.dumps({"assistant_text": f"Relay error: {exc}"}))
        except Exception:
            pass
