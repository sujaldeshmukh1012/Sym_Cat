from __future__ import annotations

import json
import importlib
import math
import re
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from typing import Any

import requests
DEFAULT_SOURCE_PDF_URL = "https://crushers.ie/site/wp-content/uploads/2021/01/CAT-Fault-codes.pdf"

CODE_PATTERNS = [
    re.compile(r"\b[BCPU]\d{4}\b", re.IGNORECASE),
    re.compile(r"\bE\d{3,5}\b", re.IGNORECASE),
    re.compile(r"\bCID\s*\d{1,4}\s*FMI\s*\d{1,2}\b", re.IGNORECASE),
]

DATA_DIR = Path(__file__).resolve().parents[1] / "data"
KB_JSON_PATH = DATA_DIR / "cat_fault_codes.json"


@dataclass
class FaultChunk:
    code: str
    title: str
    description: str
    recommended_action: str
    source: str

    @property
    def text(self) -> str:
        return " ".join([self.code, self.title, self.description, self.recommended_action]).strip()


def _normalize_ws(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def normalize_code(value: str) -> str:
    compact = re.sub(r"[^A-Z0-9]", "", value.upper())
    cid_match = re.match(r"CID(\d{1,4})FMI(\d{1,2})", compact)
    if cid_match:
        return f"CID {cid_match.group(1).zfill(4)} FMI {cid_match.group(2).zfill(2)}"
    return compact


def find_codes(text: str) -> list[str]:
    found: list[str] = []
    for pattern in CODE_PATTERNS:
        for match in pattern.findall(text or ""):
            token = _normalize_ws(str(match).upper())
            if token not in found:
                found.append(token)
    return found


def _line_to_title(line: str) -> str:
    cleaned = re.sub(r"\s*[:\-–]\s*", " - ", _normalize_ws(line))
    if " - " in cleaned:
        parts = cleaned.split(" - ", 1)
        return parts[1].strip() or "CAT Fault"
    tokens = cleaned.split()
    return " ".join(tokens[:8]).strip() or "CAT Fault"


def _build_chunks_from_text(pdf_text: str, source: str) -> list[FaultChunk]:
    lines = [_normalize_ws(line) for line in (pdf_text or "").splitlines()]
    lines = [line for line in lines if line]

    chunks: list[FaultChunk] = []
    current_code: str | None = None
    current_title: str = ""
    buffer: list[str] = []

    def flush_current():
        nonlocal current_code, current_title, buffer
        if not current_code:
            return
        description = _normalize_ws(" ".join(buffer))
        if not description:
            description = "No description extracted from source yet."
        chunks.append(
            FaultChunk(
                code=current_code,
                title=current_title or "CAT Fault",
                description=description,
                recommended_action="Inspect machine using CAT diagnostics and follow OEM repair guidance.",
                source=source,
            )
        )
        current_code = None
        current_title = ""
        buffer = []

    for line in lines:
        line_codes = find_codes(line)
        if line_codes:
            flush_current()
            first_code = line_codes[0]
            current_code = normalize_code(first_code)
            current_title = _line_to_title(line)
            continue

        if current_code:
            buffer.append(line)

    flush_current()

    unique: dict[str, FaultChunk] = {}
    for chunk in chunks:
        key = normalize_code(chunk.code)
        if key not in unique:
            unique[key] = chunk
        else:
            merged = unique[key]
            if len(chunk.description) > len(merged.description):
                unique[key] = chunk

    return list(unique.values())


def ingest_fault_pdf(pdf_url: str = DEFAULT_SOURCE_PDF_URL) -> list[dict[str, Any]]:
    try:
        PdfReader = importlib.import_module("pypdf").PdfReader
    except Exception as exc:
        raise RuntimeError("pypdf is required for PDF ingestion. Install with: pip install pypdf") from exc

    response = requests.get(pdf_url, timeout=60)
    response.raise_for_status()

    reader = PdfReader(BytesIO(response.content))
    pages_text = []
    for page in reader.pages:
        pages_text.append(page.extract_text() or "")

    combined_text = "\n".join(pages_text)
    chunks = _build_chunks_from_text(combined_text, source=pdf_url)

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    serialized = [
        {
            "code": chunk.code,
            "title": chunk.title,
            "description": chunk.description,
            "recommended_action": chunk.recommended_action,
            "source": chunk.source,
        }
        for chunk in chunks
    ]
    KB_JSON_PATH.write_text(json.dumps(serialized, indent=2), encoding="utf-8")
    return serialized


def load_fault_catalog() -> list[dict[str, Any]]:
    if not KB_JSON_PATH.exists():
        return []
    try:
        return json.loads(KB_JSON_PATH.read_text(encoding="utf-8"))
    except Exception:
        return []


def _hash_token(token: str, dim: int) -> int:
    return abs(hash(token)) % dim


def embed_text(text: str, dim: int = 256) -> list[float]:
    vec = [0.0] * dim
    tokens = re.findall(r"[A-Za-z0-9]+", (text or "").lower())
    if not tokens:
        return vec
    for token in tokens:
        idx = _hash_token(token, dim)
        vec[idx] += 1.0
    norm = math.sqrt(sum(v * v for v in vec)) or 1.0
    return [v / norm for v in vec]


def cosine_similarity(a: list[float], b: list[float]) -> float:
    if not a or not b or len(a) != len(b):
        return 0.0
    return sum(x * y for x, y in zip(a, b))


def retrieve_fault_chunks(query: str, catalog: list[dict[str, Any]], top_k: int = 5) -> list[dict[str, Any]]:
    if not query or not catalog:
        return []

    query_vec = embed_text(query)
    query_norm = normalize_code(query)
    query_lower = query.lower().strip()

    scored: list[tuple[float, dict[str, Any]]] = []
    for item in catalog:
        code = str(item.get("code") or "")
        title = str(item.get("title") or "")
        description = str(item.get("description") or "")
        action = str(item.get("recommended_action") or "")
        item_text = " ".join([code, title, description, action]).strip()

        vec_score = cosine_similarity(query_vec, embed_text(item_text))

        exact_bonus = 0.0
        partial_bonus = 0.0
        if normalize_code(code) == query_norm and query_norm:
            exact_bonus = 2.0
        elif query_lower and (
            query_lower in code.lower()
            or query_lower in title.lower()
            or query_lower in description.lower()
        ):
            partial_bonus = 1.0

        score = vec_score + exact_bonus + partial_bonus
        scored.append((score, item))

    scored.sort(key=lambda x: x[0], reverse=True)
    return [item for score, item in scored[: max(1, top_k)] if score > 0]


def generate_fault_summary(query: str, retrieved: list[dict[str, Any]]) -> dict[str, Any]:
    if not retrieved:
        return {
            "query": query,
            "summary": "No matching CAT fault code was found in the current catalog.",
            "technician_summary": "Verify code format and check active machine diagnostics.",
            "suggested_actions": [
                "Confirm exact code from machine display",
                "Retry search using CID/FMI or DTC format",
                "Run CAT diagnostic tool lookup",
            ],
            "matches": [],
        }

    best = retrieved[0]
    summary = str(best.get("description") or "No description available.")
    action = str(best.get("recommended_action") or "Use CAT diagnostics for guided troubleshooting.")

    return {
        "query": query,
        "summary": summary,
        "technician_summary": (
            "Matched CAT code context from knowledge base. Prioritize verification of active fault state "
            "before replacement decisions."
        ),
        "suggested_actions": [action],
        "matches": retrieved,
    }
