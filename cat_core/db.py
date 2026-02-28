"""
Supabase client singleton for cat_core.
Reads SUPABASE_URL and SUPABASE_KEY from environment / .env file.
"""
import os
from supabase import create_client, Client

# Try loading .env if present (for local dev)
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

_client: Client | None = None


def get_supabase() -> Client:
    """Return a singleton Supabase client."""
    global _client
    if _client is None:
        url = os.getenv("SUPABASE_URL")
        key = os.getenv("SUPABASE_KEY")
        if not url or not key:
            raise RuntimeError(
                "SUPABASE_URL and SUPABASE_KEY must be set. "
                "Add them to cat_core/.env or export as environment variables."
            )
        _client = create_client(url, key)
    return _client
