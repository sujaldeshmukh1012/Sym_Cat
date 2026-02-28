"""
Routing layer: identify component from image (and optional voice hint), then select
the correct SubSection Prompt. Prevents FAIL 1 (wrong prompt for the image).
Analyzer is only called after this step with image + correct prompt.
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

# Strong hint phrases → component (user said "radiator hose" etc. → use Cooling System)
HINT_TO_COMPONENT = [
    (["radiator hose", "radiator hoses", "coolant hose", "cooling hose", "upper radiator", "lower radiator", "coolant leak", "cooling system hose"], "Cooling System"),
    (["ladder", "access ladder", "steps", "handrail", "guardrail"], "Steps/Handrails"),
    (["tire", "tyre", "rim", "wheel bolt", "wheel nut"], "Tires/Rims"),
    (["hydraulic", "cylinder", "hydraulics"], "Hydraulics"),
    (["engine", "engine block", "belt", "oil leak"], "Engine"),
    (["track", "undercarriage", "roller", "sprocket"], "Undercarriage"),
    (["cab", "glass", "mirror"], "Cab/Glass"),
]


class Router:
    """
    Two-stage: (1) component identification via same LLM, (2) prompt selection.
    Image + voice hint → component string + subsection prompt or (Unknown, None).
    """

    def identify(self, image_bytes: bytes, voice_hint: str = "") -> tuple[str, str | None]:
        """
        Returns (component, subsection_prompt).
        Image classification wins; if the LLM misclassifies (e.g. hose as Engine) and the
        user gave a specific hint (e.g. "radiator hose"), we override to the hinted component.
        """
        hint_lower = (voice_hint or "").strip().lower()
        inspector = Inspector()
        image_b64 = base64.b64encode(image_bytes).decode("ascii")
        # Use dedicated classifier so routing is independent of inspection prompt
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
        if component_from_image is None and ("Unknown" in text or not text):
            # Unknown from image: use hint if it clearly names a component
            for phrases, component in HINT_TO_COMPONENT:
                if any(p in hint_lower for p in phrases):
                    return (component, PROMPT_MAP[component])
            return ("Unknown", None)
        if component_from_image is None:
            return ("Unknown", None)

        # User hint overrides when they clearly name a component (avoids misclassification)
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
