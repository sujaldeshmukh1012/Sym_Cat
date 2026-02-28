# Cat Core (Modal)

Modal serverless Python in Sym_Cat.

## Setup

1. **Create a virtualenv and install deps:**

   ```bash
   cd cat_core
   python -m venv .venv
   source .venv/bin/activate   # Windows: .venv\Scripts\activate
   pip install -r requirements.txt
   ```

2. **Auth with Modal** (one-time):

   ```bash
   modal token new
   ```

   Or copy `.env.example` to `.env` and set `MODAL_TOKEN_ID` and `MODAL_TOKEN_SECRET` from [Modal settings](https://modal.com/settings).

## Run

**Minimal Modal test:**
```bash
modal run get_started.py
```
Expected: `the square is 1764` (42²).

**Test the Qwen Inspector (GPU):**  
This spins up the A10G Inspector and runs one inference. First run may take a few minutes (model download).

```bash
modal run test_inspector.py
```

With your own image:
```bash
modal run test_inspector.py --image path/to/photo.jpg
```

If it works, you’ll see a short description of the image printed from the model.
