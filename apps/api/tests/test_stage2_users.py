import uuid

from httpx import AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

from app.cli import create_tenant
from app.core.config import settings
from tests.conftest import fetch_demo_token


async def test_users_list_admin_only(
    client: AsyncClient, admin_token: str, manager_token: str, mr_token: str
):
    # MR forbidden
    mr_res = await client.get("/v1/users", headers={"Authorization": f"Bearer {mr_token}"})
    assert mr_res.status_code == 403
    assert mr_res.json()["code"] == "FORBIDDEN"

    # Manager forbidden
    mgr_res = await client.get("/v1/users", headers={"Authorization": f"Bearer {manager_token}"})
    assert mgr_res.status_code == 403

    # Admin allowed
    admin_res = await client.get("/v1/users", headers={"Authorization": f"Bearer {admin_token}"})
    assert admin_res.status_code == 200
    data = admin_res.json()
    assert "items" in data
    assert data["total"] >= 7
    assert data["page"] == 1


async def test_users_list_filters(client: AsyncClient, admin_token: str):
    # Filter by role=mr
    res = await client.get("/v1/users?role=mr", headers={"Authorization": f"Bearer {admin_token}"})
    assert res.status_code == 200
    data = res.json()
    for item in data["items"]:
        assert item["app_role"] == "mr"

    # Filter by search=Rajesh
    res_search = await client.get(
        "/v1/users?search=Rajesh", headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert res_search.status_code == 200
    assert len(res_search.json()["items"]) >= 1
    assert "Rajesh" in res_search.json()["items"][0]["full_name"]


async def test_create_user_happy_path_and_audit(client: AsyncClient, admin_token: str):
    unique = str(uuid.uuid4())[:8]
    email = f"field.rep.{unique}@apexpharma.com"
    manager_id = "20000000-0000-0000-0000-000000000002"  # Vikram Malhotra

    payload = {
        "email": email,
        "password": "Password123!",
        "full_name": f"Field Rep {unique}",
        "app_role": "mr",
        "phone": "+91 99999 88888",
        "employee_code": f"EMP-{unique}",
        "manager_id": manager_id,
    }

    create_res = await client.post(
        "/v1/users", json=payload, headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert create_res.status_code == 201
    created = create_res.json()
    user_id = created["id"]
    assert created["full_name"] == payload["full_name"]
    assert created["app_role"] == "mr"
    assert created["manager_id"] == manager_id

    # Verify audit log row created
    admin_engine = create_async_engine(settings.platform_admin_url)
    async with admin_engine.begin() as conn:
        audit_row = (
            await conn.execute(
                text(
                    "select action, entity_name from public.audit_logs where entity_id = :uid and action = 'insert'"
                ),
                {"uid": uuid.UUID(user_id)},
            )
        ).first()
        assert audit_row is not None
        assert audit_row.entity_name == "app_users"
    await admin_engine.dispose()

    # Get user
    get_res = await client.get(
        f"/v1/users/{user_id}", headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert get_res.status_code == 200
    assert get_res.json()["id"] == user_id

    # Update user
    update_res = await client.patch(
        f"/v1/users/{user_id}",
        json={"full_name": f"Updated Name {unique}", "phone": "+91 98765 43210"},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert update_res.status_code == 200
    assert update_res.json()["full_name"] == f"Updated Name {unique}"

    # Deactivate user
    delete_res = await client.delete(
        f"/v1/users/{user_id}", headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert delete_res.status_code == 200
    assert delete_res.json()["status"] == "suspended"

    # Verify banned in auth.users
    admin_engine = create_async_engine(settings.platform_admin_url)
    async with admin_engine.begin() as conn:
        auth_row = (
            await conn.execute(
                text("select banned_until from auth.users where id = :aid"),
                {"aid": uuid.UUID(created["auth_user_id"])},
            )
        ).first()
        assert auth_row is not None
        assert auth_row.banned_until is not None
    await admin_engine.dispose()


async def test_user_validation_errors(client: AsyncClient, admin_token: str):
    # Invalid email
    res1 = await client.post(
        "/v1/users",
        json={
            "email": "bad-email",
            "password": "Password123!",
            "full_name": "Test",
            "app_role": "mr",
        },
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert res1.status_code == 422
    assert res1.json()["code"] == "VALIDATION_ERROR"

    # Password too short (< 8 chars)
    res2 = await client.post(
        "/v1/users",
        json={"email": "good@test.com", "password": "short", "full_name": "Test", "app_role": "mr"},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert res2.status_code == 422

    # Non-existent manager_id
    res3 = await client.post(
        "/v1/users",
        json={
            "email": f"test-{uuid.uuid4()}@apexpharma.com",
            "password": "Password123!",
            "full_name": "Test",
            "app_role": "mr",
            "manager_id": str(uuid.uuid4()),
        },
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert res3.status_code == 400
    assert res3.json()["code"] == "BAD_REQUEST"


async def test_cross_tenant_user_leak_isolation(client: AsyncClient, admin_token: str):
    # Create Tenant B using platform CLI helper
    suffix = str(uuid.uuid4())[:8]
    b_slug = f"tenant-b-{suffix}"
    b_email = f"admin-{suffix}@tenantb.com"

    res_b = await create_tenant(
        name=f"Tenant B {suffix}",
        slug=b_slug,
        admin_email=b_email,
        admin_name="Tenant B Admin",
        admin_password="Password123!",
    )
    b_admin_id = res_b["admin_app_user_id"]
    b_token = await fetch_demo_token(b_email)

    # Tenant A admin tries to GET Tenant B user
    leak_get = await client.get(
        f"/v1/users/{b_admin_id}", headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert leak_get.status_code == 404

    # Tenant A admin tries to UPDATE Tenant B user
    leak_patch = await client.patch(
        f"/v1/users/{b_admin_id}",
        json={"full_name": "Hacked Name"},
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert leak_patch.status_code == 404

    # Tenant A admin tries to DELETE Tenant B user
    leak_del = await client.delete(
        f"/v1/users/{b_admin_id}", headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert leak_del.status_code == 404

    # But Tenant B admin CAN view their own user
    b_own_get = await client.get(
        f"/v1/users/{b_admin_id}", headers={"Authorization": f"Bearer {b_token}"}
    )
    assert b_own_get.status_code == 200
    assert b_own_get.json()["id"] == b_admin_id
