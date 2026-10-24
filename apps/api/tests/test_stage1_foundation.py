import uuid

import pytest
from httpx import AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

from app.cli import create_tenant
from app.core.config import settings


async def test_healthz(client: AsyncClient):
    response = await client.get("/healthz")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
    assert "X-Request-ID" in response.headers


async def test_request_id_middleware(client: AsyncClient):
    custom_id = "test-req-id-12345"
    response = await client.get("/healthz", headers={"X-Request-ID": custom_id})
    assert response.status_code == 200
    assert response.headers["X-Request-ID"] == custom_id


async def test_me_unauthorized(client: AsyncClient):
    response = await client.get("/v1/me")
    assert response.status_code == 401
    data = response.json()
    assert data["code"] == "UNAUTHORIZED"
    assert "message" in data


async def test_me_invalid_token(client: AsyncClient):
    response = await client.get("/v1/me", headers={"Authorization": "Bearer not-a-valid-token"})
    assert response.status_code == 401
    data = response.json()
    assert data["code"] == "UNAUTHORIZED"


async def test_me_authenticated_admin(client: AsyncClient, admin_token: str):
    response = await client.get("/v1/me", headers={"Authorization": f"Bearer {admin_token}"})
    assert response.status_code == 200
    data = response.json()
    assert data["role"] == "admin"
    assert data["tenant_id"] == "00000000-0000-0000-0000-000000000001"
    assert data["tenant_name"] == "Apex Pharma Solutions Ltd"
    assert data["full_name"] == "Rajesh Sharma"
    assert data["app_user_id"] == "20000000-0000-0000-0000-000000000001"
    assert data["user_id"] == "10000000-0000-0000-0000-000000000001"


async def test_me_authenticated_mr(client: AsyncClient, mr_token: str):
    response = await client.get("/v1/me", headers={"Authorization": f"Bearer {mr_token}"})
    assert response.status_code == 200
    data = response.json()
    assert data["role"] == "mr"
    assert data["tenant_id"] == "00000000-0000-0000-0000-000000000001"
    assert data["full_name"] == "Amit Kumar"
    assert data["app_user_id"] == "20000000-0000-0000-0000-000000000004"


async def test_error_format_404(client: AsyncClient):
    response = await client.get("/v1/non-existent-route")
    assert response.status_code == 404
    data = response.json()
    assert data["code"] == "NOT_FOUND"
    assert "message" in data


async def test_cli_create_tenant():
    unique_suffix = str(uuid.uuid4())[:8]
    slug = f"test-tenant-{unique_suffix}"
    name = f"Test Tenant {unique_suffix}"
    admin_email = f"admin-{unique_suffix}@example.com"
    admin_name = "Test Admin"

    result = await create_tenant(
        name=name,
        slug=slug,
        admin_email=admin_email,
        admin_name=admin_name,
        admin_password="Password123!",
    )

    assert result["status"] == "success"
    assert result["slug"] == slug
    tenant_id = uuid.UUID(result["tenant_id"])

    # Verify directly via admin engine
    admin_engine = create_async_engine(settings.platform_admin_url)
    async with admin_engine.begin() as conn:
        tenant_row = (
            await conn.execute(
                text("select id, name, slug from public.tenants where id = :id"), {"id": tenant_id}
            )
        ).first()
        assert tenant_row is not None
        assert tenant_row.name == name

        branch_row = (
            await conn.execute(
                text("select id, is_head_office from public.branches where tenant_id = :id"),
                {"id": tenant_id},
            )
        ).first()
        assert branch_row is not None
        assert branch_row.is_head_office is True

        user_row = (
            await conn.execute(
                text("select id, app_role from public.app_users where tenant_id = :id"),
                {"id": tenant_id},
            )
        ).first()
        assert user_row is not None
        assert user_row.app_role == "admin"

        audit_row = (
            await conn.execute(
                text(
                    "select action, entity_name from public.audit_logs where tenant_id = :id and entity_name = 'tenants'"
                ),
                {"id": tenant_id},
            )
        ).first()
        assert audit_row is not None
        assert audit_row.action == "insert"

    # Verify duplicate slug throws ValueError
    with pytest.raises(ValueError, match="already exists"):
        await create_tenant(
            name=name,
            slug=slug,
            admin_email=f"other-{unique_suffix}@example.com",
            admin_name=admin_name,
            admin_password="Password123!",
        )

    await admin_engine.dispose()
