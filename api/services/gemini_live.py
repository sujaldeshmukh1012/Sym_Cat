"""
Gemini Live API — session manager for the Multimodal Live (BidiGenerateContent) relay.

This module manages persistent WebSocket connections to Google's Generative AI
Live API and implements the relay protocol between an iOS client and Gemini 2.0 Flash.

Architecture:
    iOS (AVAudioEngine) ──WebSocket──▶ FastAPI ──WebSocket──▶ Gemini Live API
    iOS (AVAudioSourceNode) ◀──WebSocket── FastAPI ◀──WebSocket── Gemini Live API
"""

import os
import json
import base64
import asyncio
import logging
from typing import Optional, Any
from dataclasses import dataclass, field

import websockets
from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger("gemini_live")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
GEMINI_MODEL = os.getenv(
    "GEMINI_MODEL", "gemini-2.5-flash-native-audio-preview-12-2025"
)
GEMINI_VOICE = os.getenv("GEMINI_VOICE", "Charon")

GEMINI_WS_URL = (
    "wss://generativelanguage.googleapis.com/ws/"
    "google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
    f"?key={GEMINI_API_KEY}"
)

# ---------------------------------------------------------------------------
# Data models
# ---------------------------------------------------------------------------


@dataclass
class LiveSessionConfig:
    """Configuration for a single Gemini Live session."""

    model: str = GEMINI_MODEL
    voice: str = GEMINI_VOICE
    system_prompt: str = ""
    tools: list[dict] = field(default_factory=list)
    response_modalities: list[str] = field(
        default_factory=lambda: ["AUDIO"]
    )


# ---------------------------------------------------------------------------
# Tool declarations (server-side — Gemini calls these, FastAPI executes)
# ---------------------------------------------------------------------------

DEFAULT_TOOL_DECLARATIONS: dict[str, Any] = {
    "function_declarations": [
        {
            "name": "run_inspection",
            "description": (
                "Run an AI inspection on a CAT equipment component. "
                "Call this when the user describes damage or asks to inspect something."
            ),
            "parameters": {
                "type": "OBJECT",
                "properties": {
                    "voice_text": {
                        "type": "STRING",
                        "description": "What the inspector said about the damage",
                    },
                    "equipment_id": {
                        "type": "STRING",
                        "description": "Equipment ID e.g. CAT-320-002",
                    },
                },
                "required": ["voice_text"],
            },
        },
        {
            "name": "report_anomalies",
            "description": (
                "Save the inspection findings (anomalies) to the task database. "
                "Call this AFTER run_inspection when the inspector confirms "
                "they want to report the findings."
            ),
            "parameters": {
                "type": "OBJECT",
                "properties": {
                    "confirmed": {
                        "type": "BOOLEAN",
                        "description": "True if the inspector confirmed reporting",
                    }
                },
                "required": ["confirmed"],
            },
        },
        {
            "name": "edit_findings",
            "description": (
                "Modify an inspection finding. Use when the inspector wants to correct, "
                "change severity, or remove a finding. Call BEFORE report_anomalies."
            ),
            "parameters": {
                "type": "OBJECT",
                "properties": {
                    "action": {
                        "type": "STRING",
                        "description": "'update' to change a finding, 'remove' to delete it",
                    },
                    "finding_number": {
                        "type": "INTEGER",
                        "description": "Which finding to edit (1, 2, 3, etc.)",
                    },
                    "new_issue": {
                        "type": "STRING",
                        "description": "New issue text (for update action)",
                    },
                    "new_severity": {
                        "type": "STRING",
                        "description": "New severity: fail, monitor, normal, or pass",
                    },
                    "new_description": {
                        "type": "STRING",
                        "description": "New description text (for update action)",
                    },
                },
                "required": ["action", "finding_number"],
            },
        },
        {
            "name": "order_parts",
            "description": (
                "Check inventory and order replacement parts for the inspection. "
                "Call this AFTER report_anomalies when the inspector confirms "
                "they want to order parts."
            ),
            "parameters": {
                "type": "OBJECT",
                "properties": {
                    "confirmed": {
                        "type": "BOOLEAN",
                        "description": "True if the inspector confirmed ordering parts",
                    }
                },
                "required": ["confirmed"],
            },
        },
    ]
}

DEFAULT_SYSTEM_PROMPT = """\
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
"""


# ---------------------------------------------------------------------------
# Build the Gemini setup message
# ---------------------------------------------------------------------------

def build_setup_message(config: LiveSessionConfig) -> dict:
    """Build the initial `setup` message for the Gemini Live API."""
    return {
        "setup": {
            "model": f"models/{config.model}",
            "generation_config": {
                "response_modalities": config.response_modalities,
                "speech_config": {
                    "voice_config": {
                        "prebuilt_voice_config": {
                            "voice_name": config.voice,
                        }
                    }
                },
            },
            "system_instruction": {
                "parts": [{"text": config.system_prompt or DEFAULT_SYSTEM_PROMPT}]
            },
            "tools": [
                config.tools if config.tools else DEFAULT_TOOL_DECLARATIONS
            ],
        }
    }


# ---------------------------------------------------------------------------
# Relay session — the core two-way bridge
# ---------------------------------------------------------------------------

class GeminiLiveRelay:
    """
    Manages a single bidirectional relay session:
        user_ws (FastAPI WebSocket) <──> gemini_ws (Google WebSocket)

    Lifecycle:
        1. Client opens /ws/live on FastAPI.
        2. Relay opens a connection to Gemini and sends the setup message.
        3. Two concurrent async tasks shuttle frames:
           - uplink:  user_ws → gemini_ws  (audio chunks, images, tool responses)
           - downlink: gemini_ws → user_ws (audio, text, tool calls, turn signals)
        4. When either side disconnects, both tasks are cancelled.
    """

    def __init__(self, user_ws, config: Optional[LiveSessionConfig] = None):
        self.user_ws = user_ws  # FastAPI WebSocket
        self.gemini_ws: Optional[websockets.WebSocketClientProtocol] = None
        self.config = config or LiveSessionConfig()
        self._tasks: list[asyncio.Task] = []
        self._closed = False

    # ------------------------------------------------------------------
    # Public
    # ------------------------------------------------------------------

    async def start(self):
        """Open the Gemini connection, send setup, then run the relay loops."""
        try:
            logger.info("Opening Gemini WebSocket → %s", GEMINI_WS_URL[:80])
            self.gemini_ws = await websockets.connect(
                GEMINI_WS_URL,
                additional_headers={"Content-Type": "application/json"},
                max_size=16 * 1024 * 1024,  # 16 MB for image frames
                ping_interval=20,
                ping_timeout=60,
                close_timeout=10,
            )

            # ----- Send setup -----
            setup_msg = build_setup_message(self.config)
            await self.gemini_ws.send(json.dumps(setup_msg))
            logger.info("Sent Gemini setup message (model=%s)", self.config.model)

            # Wait for setupComplete
            raw = await asyncio.wait_for(self.gemini_ws.recv(), timeout=15)
            setup_resp = json.loads(raw) if isinstance(raw, str) else json.loads(raw.decode())
            logger.info("Gemini setup response: %s", str(setup_resp)[:200])

            # Notify the iOS client that we're ready
            await self.user_ws.send_json({
                "type": "session_ready",
                "model": self.config.model,
                "voice": self.config.voice,
            })

            # ----- Run relay -----
            uplink = asyncio.create_task(self._uplink_loop(), name="uplink")
            downlink = asyncio.create_task(self._downlink_loop(), name="downlink")
            self._tasks = [uplink, downlink]

            # Wait until either task ends (disconnect or error)
            done, pending = await asyncio.wait(
                self._tasks, return_when=asyncio.FIRST_COMPLETED
            )

            # Cancel the surviving task
            for t in pending:
                t.cancel()
                try:
                    await t
                except asyncio.CancelledError:
                    pass

            # Propagate any real exceptions from finished tasks
            for t in done:
                if t.exception() and not isinstance(t.exception(), asyncio.CancelledError):
                    logger.error("Relay task %s failed: %s", t.get_name(), t.exception())

        except websockets.exceptions.ConnectionClosed as e:
            logger.warning("Gemini WS closed: %s", e)
        except asyncio.TimeoutError:
            logger.error("Gemini setup timed out")
            await self._send_user_error("Gemini setup timed out — check API key")
        except Exception as e:
            logger.exception("Relay start error: %s", e)
            await self._send_user_error(str(e))
        finally:
            await self.close()

    async def close(self):
        """Gracefully tear down both sides."""
        if self._closed:
            return
        self._closed = True
        for t in self._tasks:
            t.cancel()
        if self.gemini_ws:
            try:
                await self.gemini_ws.close()
            except Exception:
                pass
        logger.info("Relay session closed")

    # ------------------------------------------------------------------
    # Uplink: iOS → Gemini
    # ------------------------------------------------------------------

    async def _uplink_loop(self):
        """
        Read frames from the iOS client and forward to Gemini.

        Expected iOS message types:
        - {"type": "audio", "data": "<base64 PCM>"}
        - {"type": "image", "data": "<base64 JPEG>", "mime_type": "image/jpeg"}
        - {"type": "tool_response", "function_responses": [...]}
        - Raw binary (PCM audio shortcut — avoids base64 overhead)
        """
        try:
            while True:
                raw = await self.user_ws.receive()

                # --- Binary shortcut: raw PCM audio ---
                if "bytes" in raw and raw["bytes"]:
                    pcm_bytes: bytes = raw["bytes"]
                    b64 = base64.b64encode(pcm_bytes).decode("ascii")
                    gemini_msg = {
                        "realtime_input": {
                            "media_chunks": [
                                {
                                    "data": b64,
                                    "mime_type": "audio/pcm;rate=16000",
                                }
                            ]
                        }
                    }
                    await self.gemini_ws.send(json.dumps(gemini_msg))
                    continue

                # --- JSON text messages ---
                text = raw.get("text")
                if not text:
                    continue

                msg = json.loads(text)
                msg_type = msg.get("type", "")

                if msg_type == "audio":
                    # Base64-encoded PCM audio from iOS
                    gemini_msg = {
                        "realtime_input": {
                            "media_chunks": [
                                {
                                    "data": msg["data"],
                                    "mime_type": msg.get(
                                        "mime_type", "audio/pcm;rate=16000"
                                    ),
                                }
                            ]
                        }
                    }
                    await self.gemini_ws.send(json.dumps(gemini_msg))

                elif msg_type == "image":
                    # JPEG image (initial visual context or on-demand capture)
                    gemini_msg = {
                        "realtime_input": {
                            "media_chunks": [
                                {
                                    "data": msg["data"],
                                    "mime_type": msg.get(
                                        "mime_type", "image/jpeg"
                                    ),
                                }
                            ]
                        }
                    }
                    await self.gemini_ws.send(json.dumps(gemini_msg))
                    logger.info(
                        "Sent image frame to Gemini (%d bytes b64)",
                        len(msg.get("data", "")),
                    )

                elif msg_type == "tool_response":
                    # Client-side tool responses (e.g. take_photo result)
                    tool_resp = {
                        "tool_response": {
                            "function_responses": msg["function_responses"]
                        }
                    }
                    await self.gemini_ws.send(json.dumps(tool_resp))
                    logger.info("Forwarded tool_response to Gemini")

                elif msg_type == "end_session":
                    logger.info("Client requested session end")
                    return

                else:
                    # Forward unknown messages as-is (future-proof)
                    await self.gemini_ws.send(json.dumps(msg))

        except Exception as e:
            if not self._closed:
                logger.warning("Uplink ended: %s", e)

    # ------------------------------------------------------------------
    # Downlink: Gemini → iOS
    # ------------------------------------------------------------------

    async def _downlink_loop(self):
        """
        Read frames from Gemini and forward to the iOS client.

        Gemini sends:
        - serverContent.modelTurn.parts[].inlineData  (audio chunks)
        - serverContent.turnComplete                    (end of turn)
        - toolCall.functionCalls[]                      (tool invocations)
        - setupComplete                                 (session ack)
        """
        try:
            async for raw in self.gemini_ws:
                if isinstance(raw, bytes):
                    data = json.loads(raw.decode("utf-8"))
                else:
                    data = json.loads(raw)

                server_content = data.get("serverContent")
                tool_call = data.get("toolCall")

                # ---- Audio / text from Gemini's model turn ----
                if server_content:
                    model_turn = server_content.get("modelTurn")
                    if model_turn and "parts" in model_turn:
                        for part in model_turn["parts"]:
                            inline_data = part.get("inlineData")
                            if inline_data:
                                # Forward audio as binary for zero-copy speed
                                audio_b64 = inline_data.get("data", "")
                                mime = inline_data.get("mimeType", "audio/pcm;rate=24000")

                                # Send as binary frame (raw PCM) for low latency
                                try:
                                    pcm_bytes = base64.b64decode(audio_b64)
                                    await self.user_ws.send_bytes(pcm_bytes)
                                except Exception:
                                    # Fallback to JSON if binary send fails
                                    await self.user_ws.send_json({
                                        "type": "audio",
                                        "data": audio_b64,
                                        "mime_type": mime,
                                    })

                            # Text parts (sometimes Gemini sends inline text)
                            if "text" in part:
                                await self.user_ws.send_json({
                                    "type": "transcript",
                                    "text": part["text"],
                                    "role": "model",
                                })

                    # Turn complete signal
                    if server_content.get("turnComplete"):
                        await self.user_ws.send_json({
                            "type": "turn_complete",
                        })

                    # Interrupted (barge-in detected by Gemini)
                    if server_content.get("interrupted"):
                        await self.user_ws.send_json({
                            "type": "interrupted",
                        })

                # ---- Tool calls ----
                if tool_call:
                    function_calls = tool_call.get("functionCalls", [])
                    await self.user_ws.send_json({
                        "type": "tool_call",
                        "function_calls": function_calls,
                    })
                    logger.info(
                        "Forwarded %d tool call(s) to client",
                        len(function_calls),
                    )

        except websockets.exceptions.ConnectionClosed as e:
            if not self._closed:
                logger.warning("Gemini WS closed: %s", e)
        except Exception as e:
            if not self._closed:
                logger.warning("Downlink ended: %s", e)

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    async def _send_user_error(self, message: str):
        """Send an error message back to the iOS client."""
        try:
            await self.user_ws.send_json({
                "type": "error",
                "message": message,
            })
        except Exception:
            pass
