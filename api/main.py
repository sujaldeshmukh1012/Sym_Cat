"""
CAT Inspect Database API — entrypoint.
All route logic lives in api/routers/*.py
"""
import os
from dotenv import load_dotenv
from fastapi import FastAPI
import uvicorn

load_dotenv()

app = FastAPI(title="CAT Inspect Database API")

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
