import uuid

from httpx import AsyncClient

from tests.conftest import fetch_demo_token


async def test_mr_territory_scoping(client: AsyncClient, mr_token: str, mr2_token: str):
    """MR Amit (TERR-MUM-C) only sees Mumbai Central doctor/chemist, not Delhi South."""
    # Amit's view
    resp = await client.get("/v1/doctors", headers={"Authorization": f"Bearer {mr_token}"})
    assert resp.status_code == 200, resp.text
    data = resp.json()
    doctor_codes = [d["doctor_code"] for d in data["items"]]
    assert "DOC-001" in doctor_codes
    assert "DOC-004" not in doctor_codes

    resp = await client.get("/v1/chemists", headers={"Authorization": f"Bearer {mr_token}"})
    assert resp.status_code == 200
    chemist_codes = [c["chemist_code"] for c in resp.json()["items"]]
    assert "CHM-001" in chemist_codes
    assert "CHM-004" not in chemist_codes

    resp = await client.get("/v1/territories", headers={"Authorization": f"Bearer {mr_token}"})
    assert resp.status_code == 200
    territory_codes = [t["code"] for t in resp.json()["items"]]
    assert "TERR-MUM-C" in territory_codes
    assert "TERR-DEL-S" not in territory_codes

    # Neha's view (TERR-DEL-S)
    resp = await client.get("/v1/doctors", headers={"Authorization": f"Bearer {mr2_token}"})
    assert resp.status_code == 200
    neha_doctors = [d["doctor_code"] for d in resp.json()["items"]]
    assert "DOC-004" in neha_doctors
    assert "DOC-001" not in neha_doctors


async def test_manager_hierarchy_scoping(client: AsyncClient, manager_token: str):
    """Manager Vikram sees doctors for reportees Amit (MUM-C), Pooja (MUM-W), Rohan (PUN-C), but not Neha (DEL-S)."""
    resp = await client.get("/v1/doctors", headers={"Authorization": f"Bearer {manager_token}"})
    assert resp.status_code == 200
    doctor_codes = [d["doctor_code"] for d in resp.json()["items"]]
    assert "DOC-001" in doctor_codes
    assert "DOC-002" in doctor_codes
    assert "DOC-003" in doctor_codes
    assert "DOC-004" not in doctor_codes


async def test_admin_sees_all_masters(client: AsyncClient, admin_token: str):
    """Admin sees all doctors, chemists, territories, and products in tenant."""
    resp = await client.get("/v1/doctors", headers={"Authorization": f"Bearer {admin_token}"})
    assert resp.status_code == 200
    doctor_codes = [d["doctor_code"] for d in resp.json()["items"]]
    assert {"DOC-001", "DOC-002", "DOC-003", "DOC-004"}.issubset(set(doctor_codes))

    resp = await client.get("/v1/territories", headers={"Authorization": f"Bearer {admin_token}"})
    assert resp.status_code == 200
    terr_codes = [t["code"] for t in resp.json()["items"]]
    assert {"TERR-MUM-C", "TERR-MUM-W", "TERR-PUN-C", "TERR-DEL-S"}.issubset(set(terr_codes))

    resp = await client.get("/v1/products", headers={"Authorization": f"Bearer {admin_token}"})
    assert resp.status_code == 200
    prod_codes = [p["product_code"] for p in resp.json()["items"]]
    assert "PROD-CD-01" in prod_codes


async def test_mr_cannot_access_unassigned_territory(
    client: AsyncClient, mr_token: str, admin_token: str
):
    """MR Amit gets 403 when requesting Delhi South territory directly."""
    # Find Delhi South ID as Admin
    resp = await client.get(
        "/v1/territories?search=TERR-DEL-S", headers={"Authorization": f"Bearer {admin_token}"}
    )
    delhi_id = resp.json()["items"][0]["id"]

    # MR tries to access Delhi South
    resp = await client.get(
        f"/v1/territories/{delhi_id}", headers={"Authorization": f"Bearer {mr_token}"}
    )
    assert resp.status_code == 403
    assert resp.json()["code"] == "FORBIDDEN"


async def test_mr_cannot_access_unassigned_doctor(
    client: AsyncClient, mr_token: str, admin_token: str
):
    """MR Amit gets 403 when requesting Dr. Alok Aggarwal (Delhi) directly."""
    resp = await client.get(
        "/v1/doctors?search=DOC-004", headers={"Authorization": f"Bearer {admin_token}"}
    )
    delhi_doc_id = resp.json()["items"][0]["id"]

    resp = await client.get(
        f"/v1/doctors/{delhi_doc_id}", headers={"Authorization": f"Bearer {mr_token}"}
    )
    assert resp.status_code == 403


async def test_product_crud_permissions(client: AsyncClient, admin_token: str, mr_token: str):
    """Admin can create product; MR gets 403 when attempting creation."""
    unique_code = f"PROD-TEST-{uuid.uuid4().hex[:6]}"
    payload = {
        "product_code": unique_code,
        "name": "Test Amoxicillin 500mg",
        "generic_name": "Amoxicillin",
        "mrp": "150.00",
        "ptr": "107.14",
        "pts": "96.43",
    }

    # MR attempt
    resp = await client.post(
        "/v1/products",
        headers={"Authorization": f"Bearer {mr_token}"},
        json=payload,
    )
    assert resp.status_code == 403

    # Admin attempt
    resp = await client.post(
        "/v1/products",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=payload,
    )
    assert resp.status_code == 201
    prod = resp.json()
    assert prod["product_code"] == unique_code
    prod_id = prod["id"]

    # MR can read the newly created product
    resp = await client.get(
        f"/v1/products/{prod_id}",
        headers={"Authorization": f"Bearer {mr_token}"},
    )
    assert resp.status_code == 200
    assert resp.json()["name"] == "Test Amoxicillin 500mg"


async def test_validation_and_conflict_errors(client: AsyncClient, admin_token: str):
    """Duplicate code causes 409 Conflict; schema violations cause 422."""
    # Duplicate doctor code
    resp = await client.post(
        "/v1/doctors",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "doctor_code": "DOC-001",
            "name": "Duplicate Dr.",
        },
    )
    assert resp.status_code == 409
    assert resp.json()["code"] == "CONFLICT"

    # Invalid gender enum
    resp = await client.post(
        "/v1/doctors",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "doctor_code": f"DOC-{uuid.uuid4().hex[:6]}",
            "name": "Bad Gender Dr.",
            "gender": "unknown_value",
        },
    )
    assert resp.status_code == 422


async def test_territory_assignment(client: AsyncClient, admin_token: str, mr_token: str):
    """Admin can assign MR to territory, immediately updating MR visibility."""
    # 1. Create a fresh territory
    terr_code = f"TERR-TEST-{uuid.uuid4().hex[:6]}"
    area_id = "30000000-0000-0000-0000-000000000021"  # Mumbai Metro Area
    resp = await client.post(
        "/v1/territories",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"area_id": area_id, "code": terr_code, "name": "Test Suburban Territory"},
    )
    assert resp.status_code == 201
    terr = resp.json()
    terr_id = terr["id"]

    # MR Amit cannot see it initially
    resp = await client.get(
        f"/v1/territories/{terr_id}", headers={"Authorization": f"Bearer {mr_token}"}
    )
    assert resp.status_code == 403

    # 2. Assign territory to Amit
    amit_app_user_id = "20000000-0000-0000-0000-000000000004"
    resp = await client.post(
        f"/v1/territories/{terr_id}/assign-mr",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"mr_id": amit_app_user_id},
    )
    assert resp.status_code == 200
    assert resp.json()["manager_id"] == amit_app_user_id

    # 3. MR Amit can now see it!
    resp = await client.get(
        f"/v1/territories/{terr_id}", headers={"Authorization": f"Bearer {mr_token}"}
    )
    assert resp.status_code == 200
    assert resp.json()["code"] == terr_code


async def test_cross_tenant_master_isolation(client: AsyncClient, admin_token: str):
    """Tenant A admin cannot see or modify Tenant B masters."""
    # Use CLI to create second tenant
    from app.cli import create_tenant

    suffix = uuid.uuid4().hex[:6]
    tenant_b_name = f"Beta Pharma {suffix}"
    admin_b_email = f"admin_{suffix}@betapharma.com"

    result = await create_tenant(
        slug=f"beta-{suffix}",
        name=tenant_b_name,
        admin_email=admin_b_email,
        admin_password="Password123!",
        admin_name="Beta Admin",
    )
    tenant_b_id = str(result["tenant_id"])
    assert tenant_b_id

    token_b = await fetch_demo_token(admin_b_email)

    # Create doctor in Tenant B
    doc_b_code = f"DOC-B-{suffix}"
    resp_b = await client.post(
        "/v1/doctors",
        headers={"Authorization": f"Bearer {token_b}"},
        json={"doctor_code": doc_b_code, "name": "Dr. Beta Specialist"},
    )
    assert resp_b.status_code == 201
    doc_b_id = resp_b.json()["id"]

    # Tenant A admin queries doctors -> doc_b must NOT appear
    resp_a = await client.get("/v1/doctors", headers={"Authorization": f"Bearer {admin_token}"})
    assert resp_a.status_code == 200
    tenant_a_doc_codes = [d["doctor_code"] for d in resp_a.json()["items"]]
    assert doc_b_code not in tenant_a_doc_codes

    # Tenant A admin attempts direct GET of Tenant B doctor -> 404 (due to RLS / tenant filter)
    resp_leak = await client.get(
        f"/v1/doctors/{doc_b_id}", headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert resp_leak.status_code == 404
