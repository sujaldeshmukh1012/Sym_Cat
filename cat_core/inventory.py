"""
Inventory layer: match anomaly components against the Supabase `inventory` table.
Falls back to a static map when the DB is unreachable.
"""
import logging
from typing import Any

_log = logging.getLogger("inspex.inventory")

# ---------------------------------------------------------------------------
# Static fallback — used when Supabase is unavailable (e.g. unit tests)
# Keys = anomaly "component" values, values = list of matching parts
# ---------------------------------------------------------------------------
FALLBACK_CATALOG: dict[str, list[dict]] = {
    "Rim":                 [{"part_number": "CAT-RIM-001",   "part_name": "Steel Rim Assembly 24\"",   "unit_price": 1450.00}],
    "Wheel Hardware":      [{"part_number": "CAT-LUG-001",   "part_name": "Lug Nut M22",              "unit_price": 8.50},
                            {"part_number": "CAT-LUG-002",   "part_name": "Wheel Bolt M22x80",        "unit_price": 12.00}],
    "Tire":                [{"part_number": "CAT-TIRE-001",  "part_name": "Radial Tire 26.5R25",      "unit_price": 3200.00}],
    "Cooling System Hose": [{"part_number": "CAT-HOSE-001",  "part_name": "Upper Radiator Hose",      "unit_price": 85.00}],
    "Hose Clamp":          [{"part_number": "CAT-CLAMP-001", "part_name": "Hose Clamp 3\"",           "unit_price": 4.50}],
    "Engine Belt":         [{"part_number": "CAT-BELT-001",  "part_name": "Serpentine Belt",           "unit_price": 65.00}],
    "Oil Pan":             [{"part_number": "CAT-GSKT-001",  "part_name": "Oil Pan Gasket",            "unit_price": 38.00}],
    "Hydraulic Hose":      [{"part_number": "CAT-HHOSE-001", "part_name": "Hydraulic Hose 1/2\" x 48\"", "unit_price": 125.00}],
    "Hydraulic Fitting":   [{"part_number": "CAT-HFIT-001",  "part_name": "Hydraulic Quick-Disconnect Fitting", "unit_price": 35.00}],
    "Access Ladder":       [{"part_number": "CAT-RUNG-001",  "part_name": "Access Ladder Rung",       "unit_price": 55.00}],
    "Handrail":            [{"part_number": "CAT-RAIL-001",  "part_name": "Handrail Section 36\"",     "unit_price": 120.00}],
    "Track Roller":        [{"part_number": "CAT-ROLL-001",  "part_name": "Track Roller Assembly",     "unit_price": 320.00}],
    "Track Shoe":          [{"part_number": "CAT-SHOE-001",  "part_name": "Track Shoe Grouser",        "unit_price": 85.00}],
    "Windshield":          [{"part_number": "CAT-WIND-001",  "part_name": "Front Windshield",          "unit_price": 950.00}],
    "Door Seal":           [{"part_number": "CAT-SEAL-001",  "part_name": "Cab Door Seal",             "unit_price": 45.00}],
}


def _lookup_from_supabase(component_tag: str) -> list[dict] | None:
    """Query inventory table for parts matching the anomaly component."""
    try:
        from db import get_supabase
        sb = get_supabase()
        resp = (
            sb.table("inventory")
            .select("part_number, part_name, stock_qty, unit_price, lead_days")
            .eq("component_tag", component_tag)
            .execute()
        )
        if resp.data:
            return resp.data
    except Exception as exc:
        _log.warning("Supabase inventory lookup failed for '%s': %s", component_tag, exc)
    return None


def check_parts(anomalies: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """
    For each anomaly, look up matching parts from Supabase (or fallback catalog).
    Returns a flat list of parts needed, each with availability info.
    """
    parts: list[dict[str, Any]] = []
    seen: set[str] = set()  # avoid duplicate part_numbers

    for anomaly in anomalies or []:
        component = anomaly.get("component", "")
        severity = anomaly.get("severity", "Moderate")

        # Try Supabase first, fall back to static catalog
        matches = _lookup_from_supabase(component)
        if matches is None:
            matches = FALLBACK_CATALOG.get(component, [])

        for part in matches:
            pn = part.get("part_number", "")
            if pn in seen:
                continue
            seen.add(pn)

            stock = part.get("stock_qty", 0)
            parts.append({
                "part_number": pn,
                "part_name": part.get("part_name", component),
                "component_tag": component,
                "quantity": 1,
                "unit_price": float(part.get("unit_price", 0)),
                "stock_qty": stock,
                "lead_days": part.get("lead_days", 1),
                "urgency": "Critical" if severity == "Critical" else "Moderate",
                "in_stock": stock > 0,
            })

    return parts

