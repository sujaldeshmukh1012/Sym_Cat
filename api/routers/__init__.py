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

if not supabase_url or not supabase_key:
    raise RuntimeError("SUPABASE_URL and SUPABASE_KEY must be set.")

supabase: Client = create_client(supabase_url, supabase_key)


def validate_payload(payload: dict):
    """Raise 400 if the update payload is empty."""
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No fields provided for update",
        )
