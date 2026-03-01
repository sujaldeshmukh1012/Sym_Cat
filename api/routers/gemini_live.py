"""
WebSocket relay endpoint for the Gemini Live Multimodal API.

This router exposes `/ws/live` which the iOS Swift client connects to.
The FastAPI server then opens a second WebSocket to Google's Gemini Live API
and relays bidirectional audio/image/tool-call frames between the two.

Wire protocol (iOS ↔ FastAPI):
────────────────────────────────
UPLINK (iOS → FastAPI → Gemini):
  Binary frame:   Raw PCM 16-bit LE mono @ 16 kHz
  JSON frames:
    {"type": "audio",         "data": "<base64 PCM>"}
    {"type": "image",         "data": "<base64 JPEG>", "mime_type": "image/jpeg"}
    {"type": "tool_response", "function_responses": [{...}]}
    {"type": "config",        "model": "...", "voice": "...", "system_prompt": "..."}
    {"type": "end_session"}

DOWNLINK (Gemini → FastAPI → iOS):
  Binary frame:   Raw PCM 16-bit LE mono @ 24 kHz (from Gemini)
  JSON frames:
    {"type": "session_ready", "model": "...", "voice": "..."}
    {"type": "transcript",    "text": "...", "role": "model"}
    {"type": "tool_call",     "function_calls": [{...}]}
    {"type": "turn_complete"}
    {"type": "interrupted"}
    {"type": "error",         "message": "..."}
"""

import json
import logging

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from api.services.gemini_live import (
    GeminiLiveRelay,
    LiveSessionConfig,
    DEFAULT_SYSTEM_PROMPT,
    GEMINI_MODEL,
    GEMINI_VOICE,
    GEMINI_API_KEY,
)

router = APIRouter(tags=["gemini-live"])
logger = logging.getLogger("gemini_live_router")


@router.websocket("/ws/live")
async def gemini_live_relay(ws: WebSocket):
    """
    Full-duplex WebSocket relay between an iOS client and Gemini Live API.

    Connection lifecycle:
      1. iOS client connects to ws://<host>:8000/ws/live
      2. Optionally, client sends a {"type": "config", ...} JSON message
         to configure model/voice/system_prompt before the session starts.
         If not received within 2 s, defaults are used.
      3. FastAPI opens a second WebSocket to Gemini, sends setup, and
         begins relaying frames bidirectionally.
      4. Session ends when either side disconnects.
    """
    await ws.accept()
    logger.info("iOS client connected to /ws/live")

    if not GEMINI_API_KEY:
        await ws.send_json({
            "type": "error",
            "message": "GEMINI_API_KEY not configured on server",
        })
        await ws.close(code=4001, reason="Missing API key")
        return

    # ------------------------------------------------------------------
    # Optional: wait briefly for a config message from the client
    # ------------------------------------------------------------------
    config = LiveSessionConfig()
    try:
        import asyncio

        raw = await asyncio.wait_for(ws.receive_text(), timeout=2.0)
        msg = json.loads(raw)
        if msg.get("type") == "config":
            config = LiveSessionConfig(
                model=msg.get("model", GEMINI_MODEL),
                voice=msg.get("voice", GEMINI_VOICE),
                system_prompt=msg.get("system_prompt", DEFAULT_SYSTEM_PROMPT),
                tools=msg.get("tools", []),
            )
            logger.info("Received client config: model=%s voice=%s", config.model, config.voice)
        else:
            # Not a config message — put it back by processing normally
            # We'll just use defaults and the relay will handle the first message
            logger.info("No config message — using defaults")
    except Exception:
        # Timeout or parse error — use defaults
        logger.info("No config received in 2 s — using defaults")

    # ------------------------------------------------------------------
    # Start the relay
    # ------------------------------------------------------------------
    relay = GeminiLiveRelay(user_ws=ws, config=config)
    try:
        await relay.start()
    except WebSocketDisconnect:
        logger.info("iOS client disconnected from /ws/live")
    except Exception as e:
        logger.exception("Relay session error: %s", e)
    finally:
        await relay.close()
        logger.info("/ws/live session ended")


@router.get("/ws/live/health")
async def gemini_live_health():
    """Quick check that the Gemini Live relay endpoint is available."""
    return {
        "status": "ok" if GEMINI_API_KEY else "missing_api_key",
        "model": GEMINI_MODEL,
        "voice": GEMINI_VOICE,
        "endpoint": "/ws/live",
    }
