from uuid import UUID

import httpx

from app.core.config import settings
from app.core.errors import ConflictError


async def create_auth_user(email: str, password: str, full_name: str) -> UUID:
    """Create a user in Supabase Auth using the Admin REST API."""
    url = f"{settings.supabase_url}/auth/v1/admin/users"
    headers = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "Content-Type": "application/json",
    }
    payload = {
        "email": email,
        "password": password,
        "email_confirm": True,
        "user_metadata": {"full_name": full_name},
    }

    async with httpx.AsyncClient() as client:
        resp = await client.post(url, headers=headers, json=payload, timeout=10.0)
        if resp.status_code == 422 or (
            resp.status_code == 400 and "already exists" in resp.text.lower()
        ):
            raise ConflictError(f"User with email '{email}' already exists")
        if resp.status_code not in (200, 201):
            raise RuntimeError(f"Supabase Auth admin create error: {resp.status_code} {resp.text}")

        data = resp.json()
        return UUID(data["id"])


async def ban_auth_user(auth_user_id: UUID) -> None:
    """Ban a user in Supabase Auth to prevent logins."""
    url = f"{settings.supabase_url}/auth/v1/admin/users/{auth_user_id}"
    headers = {
        "apikey": settings.supabase_service_role_key,
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "Content-Type": "application/json",
    }
    payload = {"ban_duration": "876000h"}  # 100 years

    async with httpx.AsyncClient() as client:
        resp = await client.put(url, headers=headers, json=payload, timeout=10.0)
        if resp.status_code not in (200, 204):
            raise RuntimeError(f"Supabase Auth admin ban error: {resp.status_code} {resp.text}")
