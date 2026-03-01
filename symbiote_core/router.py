"""
Routing layer: identify component from image (and optional voice hint), then select
the correct SubSection Prompt. Prevents FAIL 1 (wrong prompt for the image).

Speed optimizations:
- Text-hint fast path: when voice hint clearly names a component, skip GPU classify entirely
- Expanded hint vocabulary covers ~50 phrases across 7 component categories
- GPU classify is only called when hint is ambiguous or missing
"""
import base64

from prompts import cab_glass, cooling_system, engine, hydraulics, steps_handrails, tires_rims

from analyzer import Inspector

ROUTING_PROMPT = """Look at this image of a CAT excavator component.
Identify the PRIMARY component visible. Be specific:
- Radiator, radiator HOSES, coolant hoses, coolant lines, upper/lower hose → Cooling System (not Engine)
- Engine block, belts, oil, air filter → Engine
- Steps, ladder, handrails, guardrails → Steps/Handrails
- Tires, rims, wheel nuts → Tires/Rims
- Cylinders, hydraulic hoses, reservoir → Hydraulics
- Tracks, rollers, undercarriage → Undercarriage
- Cab, glass, mirrors → Cab/Glass
Respond with ONLY one exact string: Cooling System | Steps/Handrails | Tires/Rims | Engine | Hydraulics | Cab/Glass | Unknown"""

# Map router output → subsection prompt content (loaded from prompts/)
PROMPT_MAP = {
    "Cooling System": cooling_system.PROMPT,
    "Steps/Handrails": steps_handrails.PROMPT,
    "Tires/Rims": tires_rims.PROMPT,
    "Engine": engine.PROMPT,
    "Hydraulics": hydraulics.PROMPT,
    "Cab/Glass": cab_glass.PROMPT,
    "Unknown": None,
}

VALID_COMPONENTS = [c for c in PROMPT_MAP if c != "Unknown"]

# Expanded hint vocabulary — when voice hint matches, GPU classify is skipped entirely
HINT_TO_COMPONENT = [
    (["radiator hose", "radiator hoses", "coolant hose", "cooling hose",
      "upper radiator", "lower radiator", "coolant leak", "cooling system hose",
      "radiator", "coolant", "cooling system", "cooling fan", "water pump",
      "coolant line", "coolant reservoir", "thermostat"], "Cooling System"),
    (["ladder", "access ladder", "steps", "handrail", "guardrail",
      "grab rail", "grab bar", "rung", "access steps", "step",
      "hand rail", "guard rail", "entry steps", "entry ladder"], "Steps/Handrails"),
    (["tire", "tyre", "rim", "wheel bolt", "wheel nut", "lug nut",
      "lug bolt", "wheel", "tires", "rims", "wheel hardware",
      "flat tire", "tire tread", "valve stem", "tire pressure"], "Tires/Rims"),
    (["hydraulic", "cylinder", "hydraulics", "hydraulic hose",
      "hydraulic line", "hydraulic pump", "boom cylinder",
      "hydraulic fitting", "hydraulic reservoir", "hydraulic leak",
      "hydraulic fluid", "hydraulic seal"], "Hydraulics"),
    (["engine", "engine block", "belt", "oil leak", "engine oil",
      "serpentine belt", "air filter", "fuel filter", "oil pan",
      "engine bay", "motor", "diesel engine", "turbo", "turbocharger",
      "exhaust", "fuel injector"], "Engine"),
    (["track", "undercarriage", "roller", "sprocket", "idler",
      "track shoe", "track chain", "track roller", "carrier roller",
      "track tension", "track pad", "track link"], "Undercarriage"),
    (["cab", "glass", "mirror", "windshield", "window", "door seal",
      "wiper", "cab door", "rear window", "side window", "side mirror",
      "rops", "fops", "cab glass"], "Cab/Glass"),
]


class Router:
    """
    Two-stage: (1) component identification via same LLM, (2) prompt selection.
    Image + voice hint → component string + subsection prompt or (Unknown, None).
    """

    def identify(self, image_bytes: bytes, voice_hint: str = "") -> tuple[str, str | None]:
        """
        Returns (component, subsection_prompt).
        FAST PATH: If voice hint clearly names a component, skip GPU classify entirely.
        SLOW PATH: If hint is ambiguous/missing, call GPU classify_component, then apply overrides.
        """
        hint_lower = (voice_hint or "").strip().lower()

        # --- FAST PATH: strong text hint → skip GPU entirely (saves 5-10s) ---
        if hint_lower:
            for phrases, component in HINT_TO_COMPONENT:
                if any(p in hint_lower for p in phrases):
                    return (component, PROMPT_MAP[component])

        # --- SLOW PATH: need GPU classification ---
        inspector = Inspector()
        image_b64 = base64.b64encode(image_bytes).decode("ascii")
        raw = inspector.classify_component.remote(
            image_b64,
            text_hint=voice_hint or "",
        )
        text = (raw or "").strip()
        component_from_image = None
        for valid in VALID_COMPONENTS:
            if valid.lower() == text.lower() or valid in text:
                component_from_image = valid
                break
        if component_from_image is None:
            return ("Unknown", None)

        # Safety overrides: image + hint disagreement
        if component_from_image == "Engine" and any(
            p in hint_lower for p in ["radiator", "hose", "coolant", "cooling system", "cooling hose"]
        ):
            return ("Cooling System", PROMPT_MAP["Cooling System"])
        if component_from_image != "Steps/Handrails" and any(
            p in hint_lower for p in ["ladder", "access ladder", "steps", "handrail", "guardrail", "rung"]
        ):
            return ("Steps/Handrails", PROMPT_MAP["Steps/Handrails"])
        if component_from_image != "Tires/Rims" and any(
            p in hint_lower for p in ["tire", "tyre", "rim", "wheel bolt", "wheel nut"]
        ):
            return ("Tires/Rims", PROMPT_MAP["Tires/Rims"])
        return (component_from_image, PROMPT_MAP[component_from_image])

    def classify(self, image_bytes: bytes, text: str = "") -> dict[str, object]:
        """
        Pure classification helper for debugging routing.

        IMPORTANT: This does **not** apply any hint overrides. It shows the raw
        image-based label the router LLM produced so you can see if classification
        is improving independent of text hints.

        Returns:
        {
          "component_from_image": <raw LLM label or "Unknown">,
          "component_final": same as component_from_image,
          "used_hint_override": false,
          "raw_router_output": <full text from Inspector>,
        }
        """
        inspector = Inspector()
        image_b64 = base64.b64encode(image_bytes).decode("ascii")
        raw = inspector.classify_component.remote(
            image_b64,
            text_hint=text or "",
        )
        router_text = (raw or "").strip()

        component_from_image = None
        for valid in VALID_COMPONENTS:
            if valid.lower() == router_text.lower() or valid in router_text:
                component_from_image = valid
                break

        if component_from_image is None:
            if "Unknown" in router_text or not router_text:
                component_from_image = "Unknown"
            else:
                component_from_image = "Unknown"

        return {
            "component_from_image": component_from_image,
            "component_final": component_from_image,
            "used_hint_override": False,
            "raw_router_output": router_text,
        }
