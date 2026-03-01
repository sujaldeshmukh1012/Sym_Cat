#!/bin/bash

# Get the directory where the script is located
PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$PROJECT_ROOT"

# Deploy Modal Backend for Audio API
echo "Deploying Modal Audio API..."
source api/.venv/bin/activate
modal deploy symbiote_core/main.py
deactivate

echo "Audio API deployed successfully."
