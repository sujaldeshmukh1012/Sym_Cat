import re
from typing import Any

DTC_PATTERN = re.compile(r"^[BCPU]\d{4}$", re.IGNORECASE)

DTC_SYSTEM_MAP = {
    "B": "Body",
    "C": "Chassis",
    "P": "Powertrain",
    "U": "Network/Communication",
}

P_SUBSYSTEM_MAP = {
    "0": "Fuel/Air metering and auxiliary emissions",
    "1": "Fuel/Air metering",
    "2": "Injector circuit",
    "3": "Ignition/misfire",
    "4": "Auxiliary emissions",
    "5": "Idle/speed/aux inputs",
    "6": "Computer/output circuit",
    "7": "Transmission",
    "A": "Hybrid propulsion",
    "B": "Hybrid propulsion",
    "C": "Hybrid propulsion",
}

FAULT_TOPICS = {
    "misfire": {
        "title": "Engine Misfire",
        "severity": "Critical",
        "keywords": ["misfire", "ignition", "spark", "combustion", "rough idle"],
        "technician_summary": "Combustion events are irregular; inspect ignition and fuel delivery components.",
        "customer_summary": "The engine is not firing smoothly, which can reduce power and increase wear.",
        "recommended_actions": [
            "Inspect spark/ignition components",
            "Inspect injectors and fuel pressure",
            "Run compression and balance test",
        ],
    },
    "low_oil_pressure": {
        "title": "Low Oil Pressure",
        "severity": "Critical",
        "keywords": ["low oil", "oil pressure", "lubrication", "oil pump"],
        "technician_summary": "Lubrication pressure is below safe threshold; risk of accelerated internal wear.",
        "customer_summary": "The machine may not be getting enough oil flow, which can quickly damage the engine.",
        "recommended_actions": [
            "Shut down and verify oil level",
            "Inspect oil filter and pump",
            "Check for leaks and pressure sensor issues",
        ],
    },
    "high_engine_temp": {
        "title": "High Engine Temperature",
        "severity": "Critical",
        "keywords": ["overheat", "high temp", "engine temperature", "coolant", "hot engine"],
        "technician_summary": "Thermal load is above normal operating envelope; cooling efficiency may be compromised.",
        "customer_summary": "The engine is overheating and should be checked immediately to avoid major damage.",
        "recommended_actions": [
            "Stop operation and allow cool-down",
            "Inspect coolant level and circulation",
            "Inspect radiator and airflow path",
        ],
    },
    "hydraulic_issue": {
        "title": "Hydraulic System Issue",
        "severity": "Moderate",
        "keywords": ["hydraulic", "pressure drop", "cavitation", "aeration", "fluid contamination"],
        "technician_summary": "Hydraulic performance anomaly detected; verify fluid quality, pressure stability, and sealing.",
        "customer_summary": "The hydraulic system is not performing as expected and may lose efficiency or responsiveness.",
        "recommended_actions": [
            "Inspect hydraulic fluid level and condition",
            "Inspect filters, seals, and lines",
            "Validate pump and valve performance",
        ],
    },
    "electrical_fault": {
        "title": "Electrical System Fault",
        "severity": "Moderate",
        "keywords": ["electrical", "voltage", "battery", "alternator", "starter", "wiring"],
        "technician_summary": "Electrical supply or control integrity issue suspected across charging/start circuits.",
        "customer_summary": "There is an electrical problem that can affect starting, lights, or system reliability.",
        "recommended_actions": [
            "Load-test battery and charging system",
            "Inspect alternator output",
            "Inspect harness/connectors for faults",
        ],
    },
}

KNOWN_CODE_HINTS = {
    "P0300": "misfire",
    "P0524": "low_oil_pressure",
    "P0217": "high_engine_temp",
}


def _normalize_text(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip().lower()


def parse_dtc(code: str) -> dict[str, Any] | None:
    normalized = _normalize_text(code).upper()
    if not DTC_PATTERN.match(normalized):
        return None

    system_letter = normalized[0]
    first_number = normalized[1]
    subsystem = normalized[2]

    parsed = {
        "code": normalized,
        "format": "DTC",
        "system": DTC_SYSTEM_MAP.get(system_letter, "Unknown"),
        "scope": "Manufacturer-specific" if first_number == "1" else "Generic",
        "subsystem": None,
    }

    if system_letter == "P":
        parsed["subsystem"] = P_SUBSYSTEM_MAP.get(subsystem, "Unknown")

    return parsed


def _topic_from_text(text: str) -> str | None:
    normalized = _normalize_text(text)
    if not normalized:
        return None

    for topic_key, topic_meta in FAULT_TOPICS.items():
        keywords = topic_meta.get("keywords", [])
        if any(keyword in normalized for keyword in keywords):
            return topic_key
    return None


def _topic_from_code(code: str) -> str | None:
    normalized = _normalize_text(code).upper()
    if not normalized:
        return None
    return KNOWN_CODE_HINTS.get(normalized)


def explain_faults(
    fault_codes: list[str] | None = None,
    anomalies: list[dict[str, Any]] | None = None,
    overall_status: str | None = None,
) -> list[dict[str, Any]]:
    fault_codes = fault_codes or []
    anomalies = anomalies or []

    explanations: list[dict[str, Any]] = []
    seen_signatures: set[str] = set()

    for code in fault_codes:
        parsed = parse_dtc(code)
        topic_key = _topic_from_code(code)
        topic = FAULT_TOPICS.get(topic_key or "")

        item = {
            "code": (parsed or {}).get("code") or str(code).upper(),
            "format": (parsed or {}).get("format") or "Unknown",
            "system": (parsed or {}).get("system") or "Unknown",
            "scope": (parsed or {}).get("scope") or "Unknown",
            "subsystem": (parsed or {}).get("subsystem"),
            "topic": topic.get("title") if topic else "Unclassified Fault",
            "severity": topic.get("severity") if topic else ("Critical" if _normalize_text(overall_status) == "red" else "Moderate"),
            "technician_summary": topic.get("technician_summary") if topic else "Review OEM diagnostic tooling for exact machine-specific interpretation.",
            "customer_summary": topic.get("customer_summary") if topic else "A fault was detected and requires technician review.",
            "recommended_actions": topic.get("recommended_actions") if topic else [
                "Confirm active vs historical code status",
                "Inspect related subsystem and harnesses",
                "Use CAT diagnostics for exact interpretation",
            ],
        }

        signature = f"code::{item['code']}"
        if signature not in seen_signatures:
            seen_signatures.add(signature)
            explanations.append(item)

    for anomaly in anomalies:
        issue = _normalize_text((anomaly or {}).get("issue"))
        description = _normalize_text((anomaly or {}).get("description"))
        text_blob = f"{issue} {description}".strip()
        topic_key = _topic_from_text(text_blob)
        if not topic_key:
            continue

        topic = FAULT_TOPICS[topic_key]
        signature = f"topic::{topic_key}"
        if signature in seen_signatures:
            continue

        seen_signatures.add(signature)
        explanations.append(
            {
                "code": None,
                "format": "Heuristic",
                "system": "Machine",
                "scope": "Inspection-derived",
                "subsystem": None,
                "topic": topic["title"],
                "severity": topic["severity"],
                "technician_summary": topic["technician_summary"],
                "customer_summary": topic["customer_summary"],
                "recommended_actions": topic["recommended_actions"],
            }
        )

    return explanations
