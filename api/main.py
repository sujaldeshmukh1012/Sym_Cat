"""
CAT Inspect Database API — entrypoint.
All route logic lives in api/routers/*.py
"""
import os
from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

load_dotenv()

app = FastAPI(title="CAT Inspect Database API")

allowed_origins = [
    origin.strip()
    for origin in os.getenv("CORS_ORIGINS", "http://localhost:5173,http://127.0.0.1:5174").split(",")
    if origin.strip()
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
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

app.include_router(machines_router)
app.include_router(inspections_router)
app.include_router(inventory_router)
app.include_router(orders_router)
app.include_router(log_inspection_router)
app.include_router(reports_router)


@app.get("/health")
async def health():
    return {"status": "ok"}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)