from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from api.services.fault_rag import (
    DEFAULT_SOURCE_PDF_URL,
    generate_fault_summary,
    ingest_fault_pdf,
    load_fault_catalog,
    normalize_code,
    retrieve_fault_chunks,
)

router = APIRouter(prefix="/fault-codes", tags=["Fault Codes"])


class FaultSearchResponseItem(BaseModel):
    code: str
    title: str
    description: str
    recommended_action: str
    source: str | None = None


class FaultSearchResponse(BaseModel):
    query: str
    normalized_query: str
    total_matches: int
    results: list[FaultSearchResponseItem]
    rag_summary: str
    technician_summary: str
    suggested_actions: list[str]


class ReindexRequest(BaseModel):
    source_pdf_url: str = Field(default=DEFAULT_SOURCE_PDF_URL)


@router.get("/search", response_model=FaultSearchResponse)
async def search_fault_codes(
    q: str = Query(..., min_length=1, description="Error code or free-text query"),
    top_k: int = Query(default=5, ge=1, le=25),
):
    catalog = load_fault_catalog()
    if not catalog:
        raise HTTPException(
            status_code=503,
            detail="Fault code catalog not built yet. Run /fault-codes/reindex first.",
        )

    matches = retrieve_fault_chunks(q, catalog, top_k=top_k)
    rag = generate_fault_summary(q, matches)

    return FaultSearchResponse(
        query=q,
        normalized_query=normalize_code(q),
        total_matches=len(matches),
        results=[FaultSearchResponseItem(**item) for item in matches],
        rag_summary=rag["summary"],
        technician_summary=rag["technician_summary"],
        suggested_actions=rag["suggested_actions"],
    )


@router.post("/reindex")
async def reindex_fault_codes(payload: ReindexRequest):
    try:
        rows = ingest_fault_pdf(payload.source_pdf_url)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to index PDF: {exc}") from exc

    return {
        "message": "Fault code catalog indexed",
        "source_pdf_url": payload.source_pdf_url,
        "codes_indexed": len(rows),
    }


@router.get("/health")
async def fault_catalog_health() -> dict[str, Any]:
    catalog = load_fault_catalog()
    return {
        "indexed": bool(catalog),
        "codes": len(catalog),
    }
