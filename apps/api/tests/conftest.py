from collections.abc import AsyncIterator

import httpx
import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import settings
from app.main import app


@pytest.fixture
async def client() -> AsyncIterator[AsyncClient]:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


async def fetch_demo_token(email: str, password: str = "Password123!") -> str:
    """Fetch real JWT access token directly from local Supabase GoTrue auth."""
    async with httpx.AsyncClient() as http_client:
        resp = await http_client.post(
            f"{settings.supabase_url}/auth/v1/token?grant_type=password",
            headers={"apikey": "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"},
            json={"email": email, "password": password},
        )
        if resp.status_code != 200:
            raise RuntimeError(f"Failed to fetch token for {email}: {resp.status_code} {resp.text}")
        data = resp.json()
        return data["access_token"]


@pytest.fixture(scope="session")
def anyio_backend():
    return "asyncio"


@pytest.fixture
async def admin_token() -> str:
    return await fetch_demo_token("admin@apexpharma.com")


@pytest.fixture
async def manager_token() -> str:
    return await fetch_demo_token("vikram.manager@apexpharma.com")


@pytest.fixture
async def mr_token() -> str:
    return await fetch_demo_token("amit.mr@apexpharma.com")


@pytest.fixture
async def mr2_token() -> str:
    return await fetch_demo_token("neha.mr@apexpharma.com")
