from httpx import AsyncClient


async def test_mr_performance_report_role_scoping(
    client: AsyncClient, mr_token: str, manager_token: str, admin_token: str
):
    """MR sees self; Manager sees team; Admin sees tenant."""
    # 1. MR view
    resp_mr = await client.get(
        "/v1/reports/mr-performance", headers={"Authorization": f"Bearer {mr_token}"}
    )
    assert resp_mr.status_code == 200, resp_mr.text
    amit_app_user_id = "20000000-0000-0000-0000-000000000004"
    data_mr = resp_mr.json()
    for item in data_mr["items"]:
        assert item["mr_id"] == amit_app_user_id

    # 2. Manager view
    resp_mgr = await client.get(
        "/v1/reports/mr-performance", headers={"Authorization": f"Bearer {manager_token}"}
    )
    assert resp_mgr.status_code == 200
    mgr_items = resp_mgr.json()["items"]
    mgr_mr_ids = {it["mr_id"] for it in mgr_items}
    # Amit is in Vikram's team
    if data_mr["total"] > 0:
        assert amit_app_user_id in mgr_mr_ids

    # 3. Admin view
    resp_adm = await client.get(
        "/v1/reports/mr-performance", headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert resp_adm.status_code == 200
    assert resp_adm.json()["total"] >= resp_mgr.json()["total"]


async def test_mr_cannot_access_other_mr_performance(client: AsyncClient, mr_token: str):
    """MR Amit attempting to filter by Neha's MR ID gets 403 Forbidden."""
    neha_app_user_id = "20000000-0000-0000-0000-000000000007"
    resp = await client.get(
        f"/v1/reports/mr-performance?mr_id={neha_app_user_id}",
        headers={"Authorization": f"Bearer {mr_token}"},
    )
    assert resp.status_code == 403
    assert resp.json()["code"] == "FORBIDDEN"


async def test_doctor_coverage_report_scoping(client: AsyncClient, mr_token: str, admin_token: str):
    """MR only sees doctor coverage in assigned territory (Mumbai Central vs Delhi South)."""
    # MR view
    resp_mr = await client.get(
        "/v1/reports/doctor-coverage", headers={"Authorization": f"Bearer {mr_token}"}
    )
    assert resp_mr.status_code == 200
    doc_codes = [d["doctor_code"] for d in resp_mr.json()["items"]]
    assert "DOC-001" in doc_codes
    assert "DOC-004" not in doc_codes

    # Admin view
    resp_adm = await client.get(
        "/v1/reports/doctor-coverage", headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert resp_adm.status_code == 200
    adm_doc_codes = [d["doctor_code"] for d in resp_adm.json()["items"]]
    assert "DOC-001" in adm_doc_codes
    assert "DOC-004" in adm_doc_codes


async def test_secondary_sales_aggregates_report(client: AsyncClient, admin_token: str):
    """Reads view_secondary_sales_aggregates with filters."""
    # List secondary sales aggregates
    resp = await client.get(
        "/v1/reports/secondary-sales", headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data["items"], list)
