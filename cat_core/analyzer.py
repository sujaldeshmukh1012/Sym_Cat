import base64
import json
import os
import re
import tempfile
from pathlib import Path

import modal

MODEL_VOL_PATH = Path("/models")
volume = modal.Volume.from_name("inspex-models", create_if_missing=True)

image = (
    modal.Image.debian_slim(python_version="3.11")
    .pip_install(
        "torch",
        "torchvision",
        "transformers",
        "accelerate",
        "qwen-vl-utils",
        "pillow",
    )
)

app = modal.App("inspex-core")

# ---------------------------------------------------------------------------
# Per-component example outputs
# When the model sees an example that matches the current component, it
# produces far more accurate output than a generic Tires/Rims example.
# ---------------------------------------------------------------------------
COMPONENT_EXAMPLES = {
    "Cooling System": """{
  "component_identified": "Cooling System",
  "anomalies": [
    {
      "component": "Cooling System Hose",
      "issue": "Hose Crack and Leak",
      "description": "Visible crack on upper radiator hose near clamp, active coolant seepage observed.",
      "severity": "Critical",
      "recommended_action": "Shut down immediately. Replace upper radiator hose and inspect clamp."
    },
    {
      "component": "Hose Clamp",
      "issue": "Loose Clamp",
      "description": "Hose clamp at upper connection is loose with visible gap between clamp and hose.",
      "severity": "Critical",
      "recommended_action": "Tighten or replace clamp to restore seal integrity."
    }
  ],
  "overall_status": "Critical",
  "operational_impact": "Risk of engine overheating and coolant loss due to hose and clamp failure."
}""",
    "Steps/Handrails": """{
  "component_identified": "Steps/Handrails",
  "anomalies": [
    {
      "component": "Access Ladder",
      "issue": "Bent Rung",
      "description": "Middle rung of access ladder is bent inward approximately 30 degrees, compromising safe footing.",
      "severity": "Critical",
      "recommended_action": "Do not use ladder. Replace bent rung before equipment operation."
    },
    {
      "component": "Handrail",
      "issue": "Corrosion on Handrail Surface",
      "description": "Surface rust visible on upper handrail section, reducing grip reliability.",
      "severity": "Moderate",
      "recommended_action": "Sand and repaint handrail; schedule replacement if structural integrity is compromised."
    }
  ],
  "overall_status": "Critical",
  "operational_impact": "Personnel fall risk during equipment access due to structural and surface defects."
}""",
    "Tires/Rims": """{
  "component_identified": "Tires/Rims",
  "anomalies": [
    {
      "component": "Rim",
      "issue": "Severe Rim Corrosion",
      "description": "Extensive rust and pitting observed on the rim structure, affecting integrity and mounting surfaces.",
      "severity": "Critical",
      "recommended_action": "Immediate replacement of the rim to prevent structural failure."
    },
    {
      "component": "Wheel Hardware",
      "issue": "Loose or Missing Wheel Hardware",
      "description": "One lug nut is visibly missing, compromising wheel stability and increasing the risk of wheel separation.",
      "severity": "Critical",
      "recommended_action": "Immediate inspection and replacement of missing lug nut; verify all hardware is secure."
    },
    {
      "component": "Tire",
      "issue": "Moderate Tire Wear",
      "description": "Tread appears worn but still functional; no critical damage to the sidewalls or surface.",
      "severity": "Moderate",
      "recommended_action": "Monitor tread wear and schedule replacement as needed."
    }
  ],
  "wheel_position": "Front left",
  "overall_status": "Critical",
  "operational_impact": "Compromised safety and mobility due to critical rim and hardware issues."
}""",
    "Engine": """{
  "component_identified": "Engine",
  "anomalies": [
    {
      "component": "Engine Belt",
      "issue": "Belt Wear",
      "description": "Serpentine belt shows visible fraying on outer edge, approaching end of service life.",
      "severity": "Moderate",
      "recommended_action": "Schedule belt replacement within 24 hours."
    },
    {
      "component": "Oil Pan",
      "issue": "Oil Seepage",
      "description": "Dark staining visible around oil pan gasket indicating slow oil seepage.",
      "severity": "Moderate",
      "recommended_action": "Monitor oil levels and schedule gasket replacement."
    }
  ],
  "overall_status": "Moderate",
  "operational_impact": "Risk of belt failure and progressive oil loss if not addressed."
}""",
    "Hydraulics": """{
  "component_identified": "Hydraulics",
  "anomalies": [
    {
      "component": "Hydraulic Hose",
      "issue": "Active Hydraulic Leak",
      "description": "Hydraulic fluid seeping from boom cylinder hose connection, visible pooling below.",
      "severity": "Critical",
      "recommended_action": "Stop operation immediately. Replace hose and inspect cylinder seal."
    },
    {
      "component": "Hydraulic Fitting",
      "issue": "Corroded Fitting",
      "description": "Visible corrosion on quick-disconnect fitting at cylinder base, risk of seal failure.",
      "severity": "Moderate",
      "recommended_action": "Replace corroded fitting at next maintenance window."
    }
  ],
  "overall_status": "Critical",
  "operational_impact": "Loss of hydraulic pressure and equipment control risk due to active leak."
}""",
    "Undercarriage": """{
  "component_identified": "Undercarriage",
  "anomalies": [
    {
      "component": "Track Roller",
      "issue": "Roller Seal Leak",
      "description": "Oil leaking from track roller seal, visible contamination on undercarriage frame.",
      "severity": "Moderate",
      "recommended_action": "Schedule roller replacement at next maintenance window."
    },
    {
      "component": "Track Shoe",
      "issue": "Worn Track Shoe Grouser",
      "description": "Grouser height visibly reduced on multiple track shoes, indicating advanced wear.",
      "severity": "Moderate",
      "recommended_action": "Measure grouser height and schedule track shoe replacement."
    }
  ],
  "overall_status": "Moderate",
  "operational_impact": "Accelerated roller and track wear reducing traction and equipment lifespan."
}""",
    "Cab/Glass": """{
  "component_identified": "Cab/Glass",
  "anomalies": [
    {
      "component": "Windshield",
      "issue": "Cracked Glass",
      "description": "Diagonal crack spanning left third of windshield, obstructing operator sight line.",
      "severity": "Critical",
      "recommended_action": "Replace windshield before operation. Operator visibility compromised."
    },
    {
      "component": "Door Seal",
      "issue": "Deteriorated Door Seal",
      "description": "Rubber seal along cab door shows cracking and gaps, allowing dust and moisture ingress.",
      "severity": "Moderate",
      "recommended_action": "Replace door seal to restore cab environment protection."
    }
  ],
  "overall_status": "Critical",
  "operational_impact": "Operator visibility hazard and compromised cab environment."
}""",
}

DEFAULT_EXAMPLE = COMPONENT_EXAMPLES["Tires/Rims"]

SYSTEM_PROMPT_TEMPLATE = """You are a certified CAT heavy equipment inspector analyzing a {component} image.

YOUR #1 JOB: Find EVERY distinct anomaly visible in the image. Do NOT stop at the first or most obvious issue.
Inspect the image systematically — check every sub-component (e.g. rim, tire, lug nuts, valve stems for Tires/Rims).
When damage IS present, a thorough inspection typically finds 2-5 anomalies per image.

CRITICAL: Do NOT hallucinate or invent damage. If the component looks structurally sound, clean, and functional — the correct answer is ZERO anomalies and overall_status "Good". Normal wear, dirt, or minor cosmetic marks from regular use are NOT anomalies.

EXAMPLE OF DAMAGED COMPONENT (for a {component} inspection):
{example}

EXAMPLE OF GOOD CONDITION (no issues found):
{{
  "component_identified": "{component}",
  "anomalies": [],
  "overall_status": "Good",
  "operational_impact": "No issues detected. Component is in acceptable operating condition."
}}

When real damage exists, report MULTIPLE anomalies of DIFFERENT sub-components like the damaged example above.
When no real damage exists, return the good-condition example above with an EMPTY anomalies array.

STRICT RULES — violations will be flagged:
1. ONLY report what is VISUALLY CONFIRMED as actual damage, defect, or failure. No assumptions.
2. If a component is not clearly visible or is obstructed, do NOT mention it.
3. Do NOT flag camera angle, lighting, dirt, or normal operational wear as anomalies.
4. Do NOT invent damage that is not clearly visible. When in doubt, do NOT flag it.
5. Severity: Critical = immediate shutdown / replacement, Moderate = schedule maintenance, Minor = monitor.
6. If everything looks normal and functional, return an EMPTY anomalies array with overall_status "Good".
7. Return ONLY valid JSON. No markdown fences, no explanation, no extra text.

OUTPUT SCHEMA:
{{
  "component_identified": "string",
  "anomalies": [
    {{
      "component": "string",
      "issue": "string",
      "description": "string (be specific and detailed, reference what you see)",
      "severity": "Critical | Moderate | Minor",
      "recommended_action": "string"
    }}
  ],
  "overall_status": "Critical | Moderate | Minor | Good",
  "operational_impact": "string"
}}"""


# ---------------------------------------------------------------------------
# JSON extraction helper
# ---------------------------------------------------------------------------
def strip_to_json(text: str) -> str:
    """
    Extract the first {...} block from model output.
    Handles markdown fences (```json ... ```) and leading/trailing prose.
    """
    # Strip markdown fences
    text = re.sub(r"```(?:json)?", "", text).strip()
    # Find first { and last }
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        return text[start : end + 1]
    return text


@app.cls(
    gpu="A10G",
    image=image,
    volumes={str(MODEL_VOL_PATH): volume},
    timeout=180,  # raised: large subsection prompts take longer to process
)
class Inspector:
    """Runs inspection only when router has already selected the subsection prompt."""

    @modal.enter()
    def load_model(self):
        os.environ["HF_HOME"] = str(MODEL_VOL_PATH)
        volume.commit()

        import torch
        from transformers import AutoProcessor, Qwen2VLForConditionalGeneration

        self.model = Qwen2VLForConditionalGeneration.from_pretrained(
            "Qwen/Qwen2-VL-7B-Instruct",
            device_map="auto",
            torch_dtype=torch.float16,
        )
        self.processor = AutoProcessor.from_pretrained(
            "Qwen/Qwen2-VL-7B-Instruct",
            min_pixels=256 * 256,
            max_pixels=1024 * 1024,
        )

    @modal.method()
    def run_inspection(
        self,
        image_b64: str,
        subsection_prompt: str,
        component_hint: str = "",
    ) -> str:
        """
        Full inspection. Returns JSON string.
        system_prompt is now in the SYSTEM role, not injected into user turn.
        max_new_tokens raised to 1024 so full JSON is never truncated.
        Example is component-specific to avoid biasing toward wrong findings.
        """
        import io
        import torch
        from PIL import Image

        image_bytes = base64.b64decode(image_b64)
        pil_image = Image.open(io.BytesIO(image_bytes)).convert("RGB")

        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as f:
            pil_image.save(f, format="JPEG")
            image_path = f.name

        # Pick component-specific example to avoid Tires/Rims bias
        component_key = component_hint.strip() if component_hint else ""
        example = COMPONENT_EXAMPLES.get(component_key, DEFAULT_EXAMPLE)
        system_prompt = SYSTEM_PROMPT_TEMPLATE.format(
            component=component_key or "heavy equipment",
            example=example,
        )

        try:
            conversation = [
                {
                    "role": "system",
                    "content": system_prompt,
                },
                {
                    "role": "user",
                    "content": [
                        {"type": "image", "path": image_path},
                        {
                            "type": "text",
                            "text": (
                                f"SUBSECTION KNOWLEDGE:\n{subsection_prompt}\n\n"
                                "Perform a THOROUGH inspection of this image. "
                                "Examine EVERY visible sub-component one by one. "
                                "For each sub-component, determine if there is damage, wear, corrosion, or anything missing. "
                                "Report EACH distinct issue as a separate anomaly entry. "
                                "Do NOT stop after the first finding — keep scanning the entire image. "
                                "Return JSON only."
                            ),
                        },
                    ],
                },
            ]

            # Qwen2-VL pattern: first build text with apply_chat_template, then tensorize
            prompt_text = self.processor.apply_chat_template(
                conversation,
                add_generation_prompt=True,
                tokenize=False,
            )

            inputs = self.processor(
                text=[prompt_text],
                images=[pil_image],
                return_tensors="pt",
            ).to(self.model.device)

            with torch.no_grad():
                output = self.model.generate(
                    **inputs,
                    max_new_tokens=2048,
                    do_sample=False,
                    temperature=None,
                    repetition_penalty=1.05,
                )

            input_len = inputs["input_ids"].shape[1]
            generated_ids = output[0][input_len:]
            decoded = self.processor.decode(
                generated_ids,
                skip_special_tokens=True,
                clean_up_tokenization_spaces=True,
            )

            # FIX 6: extract clean JSON even if model wraps in prose/fences
            return strip_to_json(decoded.strip())

        finally:
            try:
                os.unlink(image_path)
            except OSError:
                pass

    @modal.method()
    def classify_component(
        self,
        image_b64: str,
        text_hint: str = "",
    ) -> str:
        """
        Lightweight classifier for router use.
        Returns ONE component string.
        max_new_tokens raised to 32 — "Steps/Handrails" alone is 15 chars.
        """
        import io
        import torch
        from PIL import Image

        image_bytes = base64.b64decode(image_b64)
        pil_image = Image.open(io.BytesIO(image_bytes)).convert("RGB")

        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as f:
            pil_image.save(f, format="JPEG")
            image_path = f.name

        try:
            classification_prompt = f"""You are classifying ONE primary component visible in a CAT machine image.

Inspector note (use as a hint, image is primary): "{text_hint}"

VISUAL RULES:
- Metal ladder, rungs, entry steps, grab rails → Steps/Handrails
- Rubber hoses, radiator, coolant lines → Cooling System
- Engine block, belts, air filter, oil cap → Engine
- Tires, rims, lug nuts, wheel bolts → Tires/Rims
- Hydraulic cylinders, hydraulic hoses → Hydraulics
- Rubber tracks, rollers, sprockets → Undercarriage
- Cab windows, windshield, mirrors → Cab/Glass

Respond with EXACTLY one of:
Cooling System | Steps/Handrails | Tires/Rims | Engine | Hydraulics | Undercarriage | Cab/Glass | Unknown

One string only. Nothing else."""

            conversation = [
                {
                    "role": "user",
                    "content": [
                        {"type": "image", "path": image_path},
                        {"type": "text", "text": classification_prompt},
                    ],
                }
            ]

            prompt_text = self.processor.apply_chat_template(
                conversation,
                add_generation_prompt=True,
                tokenize=False,
            )

            inputs = self.processor(
                text=[prompt_text],
                images=[pil_image],
                return_tensors="pt",
            ).to(self.model.device)

            with torch.no_grad():
                output = self.model.generate(
                    **inputs,
                    max_new_tokens=32,     # FIX 4: was 8, "Steps/Handrails" = 15 chars
                    do_sample=False,
                    temperature=None,
                )

            input_len = inputs["input_ids"].shape[1]
            generated_ids = output[0][input_len:]
            decoded = self.processor.decode(
                generated_ids,
                skip_special_tokens=True,
                clean_up_tokenization_spaces=True,
            )
            return decoded.strip()

        finally:
            try:
                os.unlink(image_path)
            except OSError:
                pass