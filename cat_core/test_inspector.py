"""
One-off test: call the Qwen Inspector on Modal with an image to verify the GPU/model works.
Run from cat_core/:   modal run test_inspector.py
With your own image:  modal run test_inspector.py --image path/to/photo.jpg
"""
import base64
import sys
from pathlib import Path

# Optional: use a small test image URL if no file provided
TEST_IMAGE_URL = "https://modal-public-assets.s3.amazonaws.com/golden-gate-bridge.jpg"

from analyzer import Inspector, app


@app.local_entrypoint()
def main(image: str = "") -> None:
    """
    Test the Inspector (Qwen2-VL on A10G). Pass --image path/to/image.jpg or leave empty to use a sample image.
    """
    if image and Path(image).exists():
        image_bytes = Path(image).read_bytes()
        print(f"Using local image: {image}", file=sys.stderr)
    else:
        if image:
            print(f"File not found: {image}, using sample image.", file=sys.stderr)
        try:
            import urllib.request
            with urllib.request.urlopen(TEST_IMAGE_URL, timeout=10) as resp:
                image_bytes = resp.read()
            print("Using sample image (Golden Gate).", file=sys.stderr)
        except Exception as e:
            print(f"Could not load sample image: {e}", file=sys.stderr)
            print("Pass a local file: modal run test_inspector.py --image your_photo.jpg", file=sys.stderr)
            sys.exit(1)

    image_b64 = base64.b64encode(image_bytes).decode("ascii")
    prompt = "Look at this image. What do you see? Reply in one short sentence."
    print("Calling Inspector (Qwen2-VL on A10G)...", file=sys.stderr)
    out = Inspector().run_inspection.remote(image_b64, prompt, "")
    print("--- Inspector output ---")
    print(out)
    print("---")
    print("If you see a short description above, the Qwen Modal GPU is working.", file=sys.stderr)
