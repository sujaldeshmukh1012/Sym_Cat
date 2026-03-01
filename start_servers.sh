#!/bin/bash

# Get the directory where the script is located
PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$PROJECT_ROOT"

# Kill existing servers if running on port 8000 (FastAPI)
echo "Stopping any existing local API on port 8000..."
lsof -ti:8000 | xargs kill -9 2>/dev/null

# Start Local Backend (api/)
echo "Starting Local FastAPI Backend..."
source api/.venv/bin/activate
# Run as module from root so 'from api.routers...' works
python -m api.main &
API_PID=$!
deactivate

# Start Modal Server (symbiote_core/)
echo "Starting Modal Symbiote Server..."
cd symbiote_core
source .venv/bin/activate
modal serve main.py

# When Modal serve is stopped (Ctrl+C), kill the background API
kill $API_PID
echo "Servers stopped."
