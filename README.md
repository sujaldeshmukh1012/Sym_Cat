
**Sym_Cat**

Overview
- **Purpose:** Integrated inspection and inventory application for heavy machinery. Provides a Python backend API, React web UI, SwiftUI iOS inspection app, and analysis/core utilities.
- **Key features:** inspection data collection, report generation, inventory management, analytics, and integrations with Supabase.

Repository layout
- **`api/`** — Python backend, routers, services, report templates and schema.
- **`Web/`** — React + Vite frontend (pages, components, Supabase integration).
- **`CAT Inspect/`** — SwiftUI iOS app (Models, Services, Views, Xcode project and tests).
- **`cat_core/`** — Analysis, database helpers, inventory utilities, logging and test harnesses.
- **`prompts/`**, **`cat_core/data/`** — Inspection prompts, reference and test data.

Getting started

Prerequisites
- macOS (for iOS development)
- Python 3.10+ (see `api/requirements.txt`)
- Node 18+ and npm (or pnpm)
- Xcode 14+ (to open the iOS app)

Backend (api)
- Create and activate a virtual environment and install requirements:

```
python3 -m venv .venv
source .venv/bin/activate
pip install -r api/requirements.txt
```

- Run the API (examples):

```
uvicorn api.main:app --reload --port 8000
```

- Quick checks:

```
pytest
python api/test_live.py
```

- See `api/README.md` and `api/new_requirements.txt` for more environment specifics.

Web frontend (Web)
- Install and run development server:

```
cd Web
npm install
npm run dev
```

- Build for production:

```
npm run build
```

- API endpoints:

```
pip install -r api/requirements.txt
python -m uvicorn api.main:app --host 127.0.0.1 --port 8000 --reload
```

- The frontend uses a `.env` file and `Web/src/supabase.js` for Supabase configuration.

iOS App (CAT Inspect)
- Open `CAT Inspect.xcodeproj` or the workspace in Xcode.
- Select a simulator or device and run from Xcode.
- Update API base URLs in the app services when pointing to a local or remote backend.

Core & analysis (`cat_core`)
- Use `cat_core/` for analyzer utilities, inventory helpers, and DB interactions. Tests and example data live under `cat_core/data/`.

Configuration & integrations
- Supabase / DB schema: `api/supabase_schema.sql` and `Web/src/supabase.js` contain integration pointers.
- Report templates: `api/templates/report_template.html`.
- Sample error and reference data: `api/error_data.json` and `cat_core/data/reference/`.

Development notes
- Current branch: Gemini_API_imple. Default branch: main.
- Keep API routes stable to avoid breaking the frontend and iOS app.
- Linting: frontend has ESLint config in `Web/`.

Contributing
- Fork the repo and create a feature branch for changes.
- Run unit tests and linters before opening a pull request.
- Describe behavior and test steps in PR descriptions.
- We used Chatgpt 5.3 Codex that assisted with the majority of UI work.

Troubleshooting
- If backend dependencies fail: recreate the venv and reinstall from `api/requirements.txt`.
- If frontend can't reach the API: ensure the backend is running and CORS is enabled.
- For device testing of the iOS app: use a LAN-accessible backend or a tunneling tool (ngrok) so the simulator/device can reach the host.

Contact & license
- Check repository metadata or open an issue for bugs and feature requests.
- Confirm license in the repo root or with maintainers if none is present.

