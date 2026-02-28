"""
Shared Supabase client + helpers used by all routers.
"""
import os
from supabase import create_client, Client
from fastapi import HTTPException, status
from dotenv import load_dotenv
from botocore.config import Config

load_dotenv()

supabase_url = os.getenv("SUPABASE_URL")
supabase_key = os.getenv("SUPABASE_KEY")

if not supabase_url:
    supabase_url = "https://axxxkhxsuigimqragicw.supabase.co"
if not supabase_key:
    supabase_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF4eHhraHhzdWlnaW1xcmFnaWN3Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjI1NzYyMywiZXhwIjoyMDg3ODMzNjIzfQ.8xTJC_hCRGdpv3J58UgzDe7BQiWaL5YR-jM7twPvsIQ"

supabase: Client = create_client(supabase_url, supabase_key)


def validate_payload(payload: dict):
    """Raise 400 if the update payload is empty."""
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No fields provided for update",
        )
