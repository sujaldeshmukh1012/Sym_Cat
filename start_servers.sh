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

# Deploy Modal Audio API
echo "Deploying Modal Audio API..."
./start_audio_server.sh

# Start Modal Server (symbiote_core/) for interactive development
echo "Starting Modal Symbiote Server (serve mode)..."
cd symbiote_core
# Note: modal deploy was done in the previous step, modal serve is for hot-reloading
modal serve main.py

# When Modal serve is stopped (Ctrl+C), kill the background API
kill $API_PID
echo "Servers stopped."
