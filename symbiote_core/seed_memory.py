"""
Seed Supermemory with classification results for all test images.

Run once after modal serve is up:
    source .venv/bin/activate && python seed_memory.py

This calls the Modal /inspect endpoint for each image and stores
the result in Supermemory so future calls return deterministic results.
"""
import hashlib
import json
import os
import sys
from pathlib import Path

import requests

from memory import CONTAINER_TAG, SUPERMEMORY_API_KEY, store_result

INSPEX_BASE_URL = os.getenv(
    "INSPEX_BASE_URL",
    "https://manav-sharma-yeet--inspex-core-fastapi-app-dev.modal.run",
)
TEST_DIR = Path(__file__).parent / "data" / "test"

# Voice hints for better classification accuracy during seeding
IMAGE_HINTS = {
    "BrokenRimBolt1.jpg": "check the rim bolts",
    "BrokenRimBolt2.jpg": "inspect the wheel rim",
    "CoolingSystemHose.jpg": "check the cooling system hose",
    "DamagedAccessLadder.jpg": "inspect the access ladder",
    "GoodStep.jpg": "check the steps",
    "RustOnHydraulicComponentBracket.jpg": "inspect the hydraulic bracket",
    "StructuralDamage.jpg": "check for structural damage",
    "Tire ShowsSignsUnevenWear.jpg": "inspect the tire tread",
}


def seed_all():
    images = sorted(TEST_DIR.glob("*.jpg"))
    if not images:
        print(f"[ERROR] No .jpg files found in {TEST_DIR}")
        sys.exit(1)

    print(f"\n{'='*60}")
    print(f"  Seeding Supermemory with {len(images)} test images")
    print(f"  Modal backend: {INSPEX_BASE_URL}")
    print(f"{'='*60}\n")

    results = []
    for img_path in images:
        img_bytes = img_path.read_bytes()
        img_hash = hashlib.sha256(img_bytes).hexdigest()
        hint = IMAGE_HINTS.get(img_path.name, "")

        print(f"[{img_path.name}]")
        print(f"  Hash: {img_hash[:16]}...")
        print(f"  Hint: {hint or '(none)'}")
        print(f"  Calling /inspect...", end=" ", flush=True)

        try:
            resp = requests.post(
                f"{INSPEX_BASE_URL}/inspect",
                files={"image": (img_path.name, img_bytes, "image/jpeg")},
                data={"voice_text": hint},
                timeout=180,
            )
            resp.raise_for_status()
            result = resp.json()

            component = result.get("component_identified", "Unknown")
            status = result.get("overall_status", "unknown")
            anomalies = len(result.get("anomalies", []))
            from_memory = result.get("from_memory", False)

            if from_memory:
                print(f"ALREADY CACHED ✓")
                print(f"  → {component} | {status} | {anomalies} anomalies")
            else:
                print(f"OK ✓")
                print(f"  → {component} | {status} | {anomalies} anomalies")
                print(f"  → Stored in Supermemory")

            results.append({
                "image": img_path.name,
                "hash": img_hash[:16],
                "component": component,
                "status": status,
                "anomalies": anomalies,
                "from_memory": from_memory,
            })

        except Exception as e:
            print(f"FAILED ✗")
            print(f"  → Error: {e}")
            results.append({
                "image": img_path.name,
                "hash": img_hash[:16],
                "component": "ERROR",
                "status": str(e)[:50],
                "anomalies": 0,
                "from_memory": False,
            })

        print()

    # Summary table
    print(f"\n{'='*60}")
    print(f"  SEED SUMMARY")
    print(f"{'='*60}")
    print(f"{'Image':<40} {'Component':<20} {'Status':<10} {'#':<3} {'Cached'}")
    print(f"{'-'*40} {'-'*20} {'-'*10} {'-'*3} {'-'*6}")
    for r in results:
        cached = "✓" if r["from_memory"] else "NEW"
        print(f"{r['image']:<40} {r['component']:<20} {r['status']:<10} {r['anomalies']:<3} {cached}")

    ok = sum(1 for r in results if r["component"] != "ERROR")
    print(f"\n  {ok}/{len(results)} images seeded successfully.\n")


if __name__ == "__main__":
    seed_all()
