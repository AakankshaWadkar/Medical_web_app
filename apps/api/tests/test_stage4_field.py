import uuid
from datetime import date
from decimal import Decimal

from httpx import AsyncClient

from tests.conftest import fetch_demo_token


async def test_visit_check_in_and_check_out_happy_path(
    client: AsyncClient, mr_token: str, admin_token: str
):
    """MR Amit checks in to Dr. Arvind Mehta (DOC-001 in Mumbai Central), records activity, and checks out."""
    # Find DOC-001 id
    doc_res = await client.get(
        "/v1/doctors?search=DOC-001", headers={"Authorization": f"Bearer {mr_token}"}
    )
    doc_id = doc_res.json()["items"][0]["id"]

    idempotency_key = str(uuid.uuid4())
    check_in_payload = {
        "idempotency_key": idempotency_key,
        "visit_type": "doctor",
        "entity_type": "doctors",
        "entity_id": doc_id,
        "latitude": 19.0178,
        "longitude": 72.8478,
        "remarks": "Morning clinical presentation",
    }

    # 1. Check-in
    resp = await client.post(
        "/v1/visits/check-in",
        headers={"Authorization": f"Bearer {mr_token}"},
        json=check_in_payload,
    )
    assert resp.status_code == 201, resp.text
    visit = resp.json()
    assert visit["visit_status"] == "in_progress"
    assert visit["check_in_latitude"] == 19.0178
    visit_id = visit["id"]

    # 2. Check-out
    check_out_payload = {
        "latitude": 19.0179,
        "longitude": 72.8479,
        "remarks": "Doctor agreed to prescribe Cardiostep AM",
    }
    resp_out = await client.post(
        f"/v1/visits/{visit_id}/check-out",
        headers={"Authorization": f"Bearer {mr_token}"},
        json=check_out_payload,
    )
    assert resp_out.status_code == 200
    updated_visit = resp_out.json()
    assert updated_visit["visit_status"] == "completed"
    assert updated_visit["check_out_latitude"] == 19.0179
    assert "Doctor agreed" in updated_visit["remarks"]

    # 3. Doctor feedback
    resp_fb = await client.post(
        f"/v1/visits/{visit_id}/doctor-feedback",
        headers={"Authorization": f"Bearer {mr_token}"},
        json={
            "feedback_type": "positive",
            "comments": "High interest in dual antihypertensive therapy",
            "next_followup_date": str(date.today()),
        },
    )
    assert resp_fb.status_code == 200
    fb = resp_fb.json()
    assert fb["feedback_type"] == "positive"
    assert fb["doctor_id"] == doc_id


async def test_idempotent_visit_check_in(client: AsyncClient, mr_token: str):
    """Submitting check-in with duplicate idempotency_key returns original visit without duplicating."""
    doc_res = await client.get(
        "/v1/doctors?search=DOC-001", headers={"Authorization": f"Bearer {mr_token}"}
    )
    doc_id = doc_res.json()["items"][0]["id"]

    idempotency_key = str(uuid.uuid4())
    payload = {
        "idempotency_key": idempotency_key,
        "visit_type": "doctor",
        "entity_type": "doctors",
        "entity_id": doc_id,
        "latitude": 19.0178,
        "longitude": 72.8478,
    }

    # First call
    resp1 = await client.post(
        "/v1/visits/check-in",
        headers={"Authorization": f"Bearer {mr_token}"},
        json=payload,
    )
    assert resp1.status_code == 201
    visit1 = resp1.json()

    # Second call (retry with same idempotency key)
    resp2 = await client.post(
        "/v1/visits/check-in",
        headers={"Authorization": f"Bearer {mr_token}"},
        json=payload,
    )
    assert resp2.status_code == 201
    visit2 = resp2.json()

    assert visit1["id"] == visit2["id"]


async def test_pob_booking_and_server_side_calculation(client: AsyncClient, mr_token: str):
    """MR books POB; system calculates totals server-side using product PTR and discount."""
    # Find chemist Dadar LifeCare Chemist
    chem_res = await client.get(
        "/v1/chemists?search=CHM-001", headers={"Authorization": f"Bearer {mr_token}"}
    )
    chem_id = chem_res.json()["items"][0]["id"]

    # Find product PROD-CD-01 (Cardiostep 50mg, ptr = 85.71)
    prod_res = await client.get(
        "/v1/products?search=PROD-CD-01", headers={"Authorization": f"Bearer {mr_token}"}
    )
    prod = prod_res.json()["items"][0]
    prod_id = prod["id"]
    ptr = Decimal(str(prod["ptr"]))  # 85.71

    idempotency_key = str(uuid.uuid4())
    quantity = 10
    discount_percent = Decimal("5.00")
    # expected line total = 10 * 85.71 * (1 - 0.05) = 857.10 * 0.95 = 814.245 -> 814.25
    expected_total = (ptr * Decimal(quantity) * Decimal("0.95")).quantize(Decimal("0.01"))

    payload = {
        "idempotency_key": idempotency_key,
        "customer_type": "chemist",
        "entity_id": chem_id,
        "items": [
            {
                "product_id": prod_id,
                "quantity": quantity,
                "discount_percent": str(discount_percent),
            }
        ],
    }

    resp = await client.post(
        "/v1/pobs",
        headers={"Authorization": f"Bearer {mr_token}"},
        json=payload,
    )
    assert resp.status_code == 201, resp.text
    pob = resp.json()
    assert Decimal(str(pob["total_amount"])) == expected_total
    assert len(pob["products"]) == 1
    assert pob["products"][0]["quantity"] == quantity

    # Retry with same idempotency key -> idempotent return
    resp_retry = await client.post(
        "/v1/pobs",
        headers={"Authorization": f"Bearer {mr_token}"},
        json=payload,
    )
    assert resp_retry.status_code == 201
    assert resp_retry.json()["id"] == pob["id"]


async def test_dcr_summary_endpoint(client: AsyncClient, mr_token: str):
    """DCR read endpoint returns daily call report reflecting logged visits and POBs."""
    resp = await client.get("/v1/dcr", headers={"Authorization": f"Bearer {mr_token}"})
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["total"] >= 1
    dcr = data["items"][0]
    assert dcr["total_calls"] >= 1
    assert Decimal(str(dcr["total_pob_value"])) >= Decimal("0.00")


async def test_mr_cannot_visit_unassigned_territory_doctor(
    client: AsyncClient, mr_token: str, admin_token: str
):
    """MR Amit (Mumbai Central) cannot check in for Dr. Alok Aggarwal (Delhi South)."""
    resp_adm = await client.get(
        "/v1/doctors?search=DOC-004", headers={"Authorization": f"Bearer {admin_token}"}
    )
    delhi_doc_id = resp_adm.json()["items"][0]["id"]

    resp = await client.post(
        "/v1/visits/check-in",
        headers={"Authorization": f"Bearer {mr_token}"},
        json={
            "idempotency_key": str(uuid.uuid4()),
            "visit_type": "doctor",
            "entity_type": "doctors",
            "entity_id": delhi_doc_id,
        },
    )
    assert resp.status_code == 403
    assert resp.json()["code"] == "FORBIDDEN"


async def test_role_scoped_visits_visibility(
    client: AsyncClient, mr_token: str, mr2_token: str, manager_token: str, admin_token: str
):
    """MR only sees self; Manager sees self + team; Admin sees all."""
    # 1. MR Amit lists visits
    resp_amit = await client.get("/v1/visits", headers={"Authorization": f"Bearer {mr_token}"})
    assert resp_amit.status_code == 200
    amit_app_user_id = "20000000-0000-0000-0000-000000000004"
    for v in resp_amit.json()["items"]:
        assert v["mr_id"] == amit_app_user_id

    # 2. Manager Vikram lists visits -> sees Amit's visits
    resp_mgr = await client.get("/v1/visits", headers={"Authorization": f"Bearer {manager_token}"})
    assert resp_mgr.status_code == 200
    mgr_visit_ids = [v["id"] for v in resp_mgr.json()["items"]]
    for v in resp_amit.json()["items"]:
        assert v["id"] in mgr_visit_ids

    # 3. Admin sees all visits
    resp_adm = await client.get("/v1/visits", headers={"Authorization": f"Bearer {admin_token}"})
    assert resp_adm.status_code == 200
    assert resp_adm.json()["total"] >= resp_mgr.json()["total"]


async def test_cross_tenant_field_isolation(client: AsyncClient, admin_token: str):
    """Visits created in Tenant B are completely invisible to Tenant A."""
    from app.cli import create_tenant

    suffix = uuid.uuid4().hex[:6]
    tenant_b_name = f"Gamma Pharma {suffix}"
    admin_b_email = f"admin_{suffix}@gammapharma.com"

    result = await create_tenant(
        slug=f"gamma-{suffix}",
        name=tenant_b_name,
        admin_email=admin_b_email,
        admin_password="Password123!",
        admin_name="Gamma Admin",
    )
    assert result["tenant_id"]

    token_b = await fetch_demo_token(admin_b_email)

    # In Tenant B, get doctor
    # Create doctor in Tenant B
    doc_res = await client.post(
        "/v1/doctors",
        headers={"Authorization": f"Bearer {token_b}"},
        json={"doctor_code": f"DOC-G-{suffix}", "name": "Dr. Gamma"},
    )
    doc_b_id = doc_res.json()["id"]

    # Check-in visit in Tenant B
    v_res = await client.post(
        "/v1/visits/check-in",
        headers={"Authorization": f"Bearer {token_b}"},
        json={
            "idempotency_key": str(uuid.uuid4()),
            "visit_type": "doctor",
            "entity_type": "doctors",
            "entity_id": doc_b_id,
        },
    )
    assert v_res.status_code == 201
    visit_b_id = v_res.json()["id"]

    # Tenant A admin cannot see Tenant B's visit
    resp_leak = await client.get(
        f"/v1/visits/{visit_b_id}", headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert resp_leak.status_code == 404
