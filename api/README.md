# CAT Inspect Database API

FastAPI server for managing inspections, inventory, machines, and orders.

## Prerequisites

Ensure the virtual environment and dependencies are set up in the root project directory:

```bash
# From project root
python -m venv cat_core/.venv
source cat_core/.venv/bin/activate
pip install uvicorn fastapi python-dotenv httpx httpcore "supabase<2"
```

## Starting the Server

From the project root directory:

```bash
/Users/manav/Desktop/dev/projects/Sym_Cat/cat_core/.venv/bin/python -m uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
```

Or with a shorter command (from project root):

```bash
source cat_core/.venv/bin/activate
uvicorn api.main:app --reload --host 0.0.0.0 --port 8000
```

## Accessing the API

- **Server URL**: `http://localhost:8000`
- **Health Check**: `http://localhost:8000/health`
- **API Docs**: `http://localhost:8000/docs` (Swagger UI)
- **Alternative Docs**: `http://localhost:8000/redoc` (ReDoc)

## Available Routes

The API includes the following routers:
- `/machines` - Machine management
- `/inspections` - Inspection data
- `/inventory` - Inventory management
- `/orders` - Order management

## Environment Variables

Create a `.env` file in the project root with your Supabase credentials:

```
SUPABASE_URL=your_supabase_url
SUPABASE_KEY=your_supabase_key
```

## Python 3.14 Compatibility Note

If using Python 3.14, ensure the following package versions are installed due to compatibility constraints:

```bash
source cat_core/.venv/bin/activate
pip install httpcore==0.15.0 httpx==0.23.3 'supabase<2'
```

## Troubleshooting

### Port 8000 Already in Use

Kill the process and restart:

```bash
kill -9 $(lsof -t -i :8000) 2>/dev/null
# Then restart the server
```

### AttributeError with typing.Union (httpcore)

If you see: `AttributeError: 'typing.Union' object has no attribute '__module__'`

This is a Python 3.14 compatibility issue. Fix by downgrading httpcore and httpx:

```bash
source cat_core/.venv/bin/activate
pip install httpcore==0.15.0 httpx==0.23.3 --force-reinstall
```

### Missing Dependencies

If you get import errors, reinstall dependencies:

```bash
source cat_core/.venv/bin/activate
pip install -r ../cat_core/requirements.txt
```
