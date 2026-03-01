"""
CAT Inspect Database API — entrypoint.
All route logic lives in api/routers/*.py
"""
import os
import json
import asyncio
import logging
from datetime import datetime
from typing import Set

from dotenv import load_dotenv
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

load_dotenv()
logger = logging.getLogger("api")

app = FastAPI(title="CAT Inspect Database API")

# --- CORS: allow everything for mobile development ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Register routers ---
from api.routers.machines import router as machines_router
from api.routers.inspections import router as inspections_router
from api.routers.inventory import router as inventory_router
from api.routers.orders import router as orders_router
from api.routers.log_inspection import router as log_inspection_router
from api.routers.reports import router as reports_router
from api.routers.gemini_live import router as gemini_live_router

app.include_router(machines_router)
app.include_router(inspections_router)
app.include_router(inventory_router)
app.include_router(orders_router)
app.include_router(log_inspection_router)
app.include_router(reports_router)
app.include_router(gemini_live_router)


@app.get("/health")
async def health():
    return {"status": "ok"}


# ---------------------------------------------------------------------------
# WebSocket — real-time connection for the iOS app
# ---------------------------------------------------------------------------

class ConnectionManager:
    """Track active WebSocket connections from mobile clients."""

    def __init__(self):
        self.active: Set[WebSocket] = set()

    async def connect(self, ws: WebSocket):
        await ws.accept()
        self.active.add(ws)
        logger.info("WS client connected  (%d total)", len(self.active))

    def disconnect(self, ws: WebSocket):
        self.active.discard(ws)
        logger.info("WS client disconnected (%d total)", len(self.active))

    async def broadcast(self, message: dict):
        """Send a JSON message to every connected client."""
        dead: list[WebSocket] = []
        for ws in self.active:
            try:
                await ws.send_json(message)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.active.discard(ws)


manager = ConnectionManager()


@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    """
    Persistent WebSocket channel between iOS app and FastAPI.

    Protocol (JSON messages):
    ← server sends on connect:  {"type": "connected", "server_time": "...", "version": "1.0"}
    → client can send:          {"type": "ping"}
    ← server responds:          {"type": "pong", "server_time": "..."}
    → client can send:          {"type": "subscribe", "topics": ["inspections", "orders"]}
    ← server pushes events:     {"type": "event", "topic": "...", "payload": {...}}
    """
    await manager.connect(ws)
    try:
        # Send welcome handshake immediately
        await ws.send_json({
            "type": "connected",
            "server_time": datetime.utcnow().isoformat() + "Z",
            "version": "1.0",
            "message": "CAT Inspect API connected"
        })

        while True:
            raw = await ws.receive_text()
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await ws.send_json({"type": "error", "message": "Invalid JSON"})
                continue

            msg_type = msg.get("type", "")

            if msg_type == "ping":
                await ws.send_json({
                    "type": "pong",
                    "server_time": datetime.utcnow().isoformat() + "Z"
                })

            elif msg_type == "health":
                await ws.send_json({
                    "type": "health",
                    "status": "ok",
                    "server_time": datetime.utcnow().isoformat() + "Z",
                    "active_connections": len(manager.active)
                })

            elif msg_type == "subscribe":
                topics = msg.get("topics", [])
                await ws.send_json({
                    "type": "subscribed",
                    "topics": topics
                })

            else:
                await ws.send_json({
                    "type": "echo",
                    "original": msg,
                    "server_time": datetime.utcnow().isoformat() + "Z"
                })

    except WebSocketDisconnect:
        manager.disconnect(ws)
    except Exception as e:
        logger.exception("WS error: %s", e)
        manager.disconnect(ws)


@app.get("/ws/status")
async def ws_status():
    """Check how many WebSocket clients are connected."""
    return {
        "active_connections": len(manager.active),
        "server_time": datetime.utcnow().isoformat() + "Z"
    }


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
