"""Cross-tenant leak tests for MVP tables: territories, doctors, chemists, products, visits, orders (POB).
Needs `supabase start` + seed (app_backend password).
ADMIN_DB_URL uses the postgres role to seed; APP_DB_URL uses app_backend.
"""

import os
import uuid

import pytest
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from sqlalchemy.ext.asyncio import create_async_engine

ADMIN = os.getenv("ADMIN_DB_URL", "postgresql+asyncpg://postgres:postgres@127.0.0.1:54122/postgres")
APP = os.getenv(
    "APP_DB_URL", "postgresql+asyncpg://app_backend:app_backend_dev@127.0.0.1:54122/postgres"
)


@pytest.fixture
async def two_tenants():
    admin = create_async_engine(ADMIN)
    a, b = uuid.uuid4(), uuid.uuid4()
    async with admin.begin() as c:
        for t in (a, b):
            await c.execute(
                text("insert into tenants(id, name, slug) values (:i, :n, :s)"),
                {"i": t, "n": f"T-{t}", "s": f"s-{t}"},
            )
    yield a, b
    async with admin.begin() as c:
        await c.execute(text("delete from app_users where tenant_id in (:a, :b)"), {"a": a, "b": b})
        await c.execute(text("delete from tenants where id in (:a, :b)"), {"a": a, "b": b})
    await admin.dispose()


async def _as_tenant(engine, tenant, sql, params=None):
    async with engine.begin() as c:
        await c.execute(text("select set_config('app.tenant_id', :t, true)"), {"t": str(tenant)})
        return await c.execute(text(sql), params or {})


async def test_tenant_sees_only_itself(two_tenants):
    a, b = two_tenants
    app = create_async_engine(APP, connect_args={"statement_cache_size": 0})
    rows = (await _as_tenant(app, a, "select id from tenants")).scalars().all()
    assert rows == [a]
    await app.dispose()


async def test_no_context_returns_nothing(two_tenants):
    app = create_async_engine(APP, connect_args={"statement_cache_size": 0})
    async with app.begin() as c:
        rows = (await c.execute(text("select id from tenants"))).all()
    assert rows == []
    await app.dispose()


async def test_cannot_write_other_tenant_rows(two_tenants):
    a, b = two_tenants
    app = create_async_engine(APP, connect_args={"statement_cache_size": 0})
    with pytest.raises(DBAPIError):
        await _as_tenant(
            app,
            a,
            """
            insert into app_users(tenant_id, auth_user_id, app_role, full_name)
            values (:b, gen_random_uuid(), 'mr', 'x')""",
            {"b": b},
        )
    await app.dispose()


async def test_territories_leak_isolation(two_tenants):
    a, b = two_tenants
    admin = create_async_engine(ADMIN)
    app = create_async_engine(APP, connect_args={"statement_cache_size": 0})

    # Setup regions & areas for both tenants via admin
    r_a, r_b = uuid.uuid4(), uuid.uuid4()
    area_a, area_b = uuid.uuid4(), uuid.uuid4()
    t_a, t_b = uuid.uuid4(), uuid.uuid4()

    async with admin.begin() as c:
        await c.execute(
            text("insert into regions(id, tenant_id, code, name) values (:id, :t, :c, :n)"),
            {"id": r_a, "t": a, "c": f"REG-A-{a}", "n": "Region A"},
        )
        await c.execute(
            text("insert into regions(id, tenant_id, code, name) values (:id, :t, :c, :n)"),
            {"id": r_b, "t": b, "c": f"REG-B-{b}", "n": "Region B"},
        )
        await c.execute(
            text(
                "insert into areas(id, tenant_id, region_id, code, name) values (:id, :t, :r, :c, :n)"
            ),
            {"id": area_a, "t": a, "r": r_a, "c": f"AREA-A-{a}", "n": "Area A"},
        )
        await c.execute(
            text(
                "insert into areas(id, tenant_id, region_id, code, name) values (:id, :t, :r, :c, :n)"
            ),
            {"id": area_b, "t": b, "r": r_b, "c": f"AREA-B-{b}", "n": "Area B"},
        )

    # Insert territories as tenant A and tenant B
    await _as_tenant(
        app,
        a,
        "insert into territories(id, tenant_id, area_id, code, name) values (:id, :t, :area, :c, :n)",
        {"id": t_a, "t": a, "area": area_a, "c": f"TERR-A-{a}", "n": "Territory A"},
    )
    await _as_tenant(
        app,
        b,
        "insert into territories(id, tenant_id, area_id, code, name) values (:id, :t, :area, :c, :n)",
        {"id": t_b, "t": b, "area": area_b, "c": f"TERR-B-{b}", "n": "Territory B"},
    )

    # Tenant A must only see t_a
    rows_a = (await _as_tenant(app, a, "select id from territories")).scalars().all()
    assert t_a in rows_a
    assert t_b not in rows_a

    # Tenant B must only see t_b
    rows_b = (await _as_tenant(app, b, "select id from territories")).scalars().all()
    assert t_b in rows_b
    assert t_a not in rows_b

    # Tenant A cannot write territory for tenant B
    with pytest.raises(DBAPIError):
        await _as_tenant(
            app,
            a,
            "insert into territories(id, tenant_id, area_id, code, name) values (:id, :t, :area, :c, :n)",
            {"id": uuid.uuid4(), "t": b, "area": area_b, "c": f"TERR-CROSS-{b}", "n": "Cross"},
        )

    await app.dispose()
    await admin.dispose()


async def test_primary_orders_leak_isolation(two_tenants):
    a, b = two_tenants
    admin = create_async_engine(ADMIN)
    app = create_async_engine(APP, connect_args={"statement_cache_size": 0})

    stk_a, stk_b = uuid.uuid4(), uuid.uuid4()
    ord_a, ord_b = uuid.uuid4(), uuid.uuid4()

    async with admin.begin() as c:
        await c.execute(
            text(
                "insert into stockists(id, tenant_id, stockist_code, name) values (:id, :t, :c, :n)"
            ),
            {"id": stk_a, "t": a, "c": f"STK-A-{a}", "n": "Stockist A"},
        )
        await c.execute(
            text(
                "insert into stockists(id, tenant_id, stockist_code, name) values (:id, :t, :c, :n)"
            ),
            {"id": stk_b, "t": b, "c": f"STK-B-{b}", "n": "Stockist B"},
        )

    # 1. Primary order isolation
    await _as_tenant(
        app,
        a,
        """insert into primary_orders(id, tenant_id, order_number, stockist_id, total_amount)
           values (:id, :t, :num, :stk, 50000.00)""",
        {"id": ord_a, "t": a, "num": f"ORD-A-{a}", "stk": stk_a},
    )
    await _as_tenant(
        app,
        b,
        """insert into primary_orders(id, tenant_id, order_number, stockist_id, total_amount)
           values (:id, :t, :num, :stk, 75000.00)""",
        {"id": ord_b, "t": b, "num": f"ORD-B-{b}", "stk": stk_b},
    )

    orders_a = (await _as_tenant(app, a, "select id from primary_orders")).scalars().all()
    assert ord_a in orders_a
    assert ord_b not in orders_a

    orders_b = (await _as_tenant(app, b, "select id from primary_orders")).scalars().all()
    assert ord_b in orders_b
    assert ord_a not in orders_b

    # 2. Cannot cross-write primary orders
    with pytest.raises(DBAPIError):
        await _as_tenant(
            app,
            a,
            """insert into primary_orders(id, tenant_id, order_number, stockist_id, total_amount)
               values (:id, :t, :num, :stk, 1000.00)""",
            {"id": uuid.uuid4(), "t": b, "num": f"ORD-ILLEGAL-{b}", "stk": stk_b},
        )

    await app.dispose()
    await admin.dispose()


async def test_doctors_and_chemists_leak_isolation(two_tenants):
    a, b = two_tenants
    app = create_async_engine(APP, connect_args={"statement_cache_size": 0})

    doc_a, doc_b = uuid.uuid4(), uuid.uuid4()
    chem_a, chem_b = uuid.uuid4(), uuid.uuid4()

    # Tenant A inserts doctor and chemist
    await _as_tenant(
        app,
        a,
        "insert into doctors(id, tenant_id, doctor_code, name) values (:id, :t, :c, :n)",
        {"id": doc_a, "t": a, "c": f"DOC-A-{a}", "n": "Dr. Alice"},
    )
    await _as_tenant(
        app,
        a,
        "insert into chemists(id, tenant_id, chemist_code, name) values (:id, :t, :c, :n)",
        {"id": chem_a, "t": a, "c": f"CHEM-A-{a}", "n": "Chemist A"},
    )

    # Tenant B inserts doctor and chemist
    await _as_tenant(
        app,
        b,
        "insert into doctors(id, tenant_id, doctor_code, name) values (:id, :t, :c, :n)",
        {"id": doc_b, "t": b, "c": f"DOC-B-{b}", "n": "Dr. Bob"},
    )
    await _as_tenant(
        app,
        b,
        "insert into chemists(id, tenant_id, chemist_code, name) values (:id, :t, :c, :n)",
        {"id": chem_b, "t": b, "c": f"CHEM-B-{b}", "n": "Chemist B"},
    )

    # Isolation check: doctors
    docs_for_a = (await _as_tenant(app, a, "select id from doctors")).scalars().all()
    assert doc_a in docs_for_a
    assert doc_b not in docs_for_a

    # Isolation check: chemists
    chems_for_b = (await _as_tenant(app, b, "select id from chemists")).scalars().all()
    assert chem_b in chems_for_b
    assert chem_a not in chems_for_b

    # Cross write check
    with pytest.raises(DBAPIError):
        await _as_tenant(
            app,
            a,
            "insert into doctors(id, tenant_id, doctor_code, name) values (:id, :t, :c, :n)",
            {"id": uuid.uuid4(), "t": b, "c": f"DOC-X-{b}", "n": "Dr. Illegal"},
        )

    await app.dispose()


async def test_products_and_visits_and_pob_leak_isolation(two_tenants):
    a, b = two_tenants
    app = create_async_engine(APP, connect_args={"statement_cache_size": 0})
    admin = create_async_engine(ADMIN)

    # Seed an MR user for each tenant via admin
    mr_a, mr_b = uuid.uuid4(), uuid.uuid4()
    prod_a, prod_b = uuid.uuid4(), uuid.uuid4()
    doc_a, doc_b = uuid.uuid4(), uuid.uuid4()
    visit_a, visit_b = uuid.uuid4(), uuid.uuid4()
    pob_a, pob_b = uuid.uuid4(), uuid.uuid4()

    auth_a, auth_b = uuid.uuid4(), uuid.uuid4()
    async with admin.begin() as c:
        await c.execute(
            text(
                "insert into auth.users (id, aud, role, email) values (:id, 'authenticated', 'authenticated', :em)"
            ),
            {"id": auth_a, "em": f"mr-a-{a}@test.com"},
        )
        await c.execute(
            text(
                "insert into auth.users (id, aud, role, email) values (:id, 'authenticated', 'authenticated', :em)"
            ),
            {"id": auth_b, "em": f"mr-b-{b}@test.com"},
        )
        await c.execute(
            text(
                "insert into app_users(id, tenant_id, auth_user_id, app_role, full_name) "
                "values (:id, :t, :auth, 'mr', :n)"
            ),
            {"id": mr_a, "t": a, "auth": auth_a, "n": "MR Alpha"},
        )
        await c.execute(
            text(
                "insert into app_users(id, tenant_id, auth_user_id, app_role, full_name) "
                "values (:id, :t, :auth, 'mr', :n)"
            ),
            {"id": mr_b, "t": b, "auth": auth_b, "n": "MR Beta"},
        )
        await c.execute(
            text("insert into doctors(id, tenant_id, doctor_code, name) values (:id, :t, :c, :n)"),
            {"id": doc_a, "t": a, "c": f"D-A-{a}", "n": "Doctor A"},
        )
        await c.execute(
            text("insert into doctors(id, tenant_id, doctor_code, name) values (:id, :t, :c, :n)"),
            {"id": doc_b, "t": b, "c": f"D-B-{b}", "n": "Doctor B"},
        )

    # 1. Product isolation
    await _as_tenant(
        app,
        a,
        "insert into products(id, tenant_id, product_code, name, mrp, ptr) values (:id, :t, :c, :n, 100, 80)",
        {"id": prod_a, "t": a, "c": f"PROD-A-{a}", "n": "Medicine A"},
    )
    await _as_tenant(
        app,
        b,
        "insert into products(id, tenant_id, product_code, name, mrp, ptr) values (:id, :t, :c, :n, 200, 160)",
        {"id": prod_b, "t": b, "c": f"PROD-B-{b}", "n": "Medicine B"},
    )

    prods_a = (await _as_tenant(app, a, "select id from products")).scalars().all()
    assert prod_a in prods_a
    assert prod_b not in prods_a

    # 2. Visit isolation
    await _as_tenant(
        app,
        a,
        """insert into field_visits(id, tenant_id, mr_id, visit_type, entity_type, entity_id, visit_status)
           values (:id, :t, :mr, 'doctor', 'doctors', :ent, 'completed')""",
        {"id": visit_a, "t": a, "mr": mr_a, "ent": doc_a},
    )
    await _as_tenant(
        app,
        b,
        """insert into field_visits(id, tenant_id, mr_id, visit_type, entity_type, entity_id, visit_status)
           values (:id, :t, :mr, 'doctor', 'doctors', :ent, 'completed')""",
        {"id": visit_b, "t": b, "mr": mr_b, "ent": doc_b},
    )

    visits_b = (await _as_tenant(app, b, "select id from field_visits")).scalars().all()
    assert visit_b in visits_b
    assert visit_a not in visits_b

    # 3. POB (Order) isolation
    await _as_tenant(
        app,
        a,
        """insert into pobs(id, tenant_id, visit_id, mr_id, customer_type, entity_id, total_amount, status)
           values (:id, :t, :vis, :mr, 'doctor', :ent, 1500.00, 'booked')""",
        {"id": pob_a, "t": a, "vis": visit_a, "mr": mr_a, "ent": doc_a},
    )
    await _as_tenant(
        app,
        b,
        """insert into pobs(id, tenant_id, visit_id, mr_id, customer_type, entity_id, total_amount, status)
           values (:id, :t, :vis, :mr, 'doctor', :ent, 3000.00, 'booked')""",
        {"id": pob_b, "t": b, "vis": visit_b, "mr": mr_b, "ent": doc_b},
    )

    pobs_a = (await _as_tenant(app, a, "select id from pobs")).scalars().all()
    assert pob_a in pobs_a
    assert pob_b not in pobs_a

    # Cross write rejection
    with pytest.raises(DBAPIError):
        await _as_tenant(
            app,
            a,
            """insert into pobs(id, tenant_id, mr_id, customer_type, entity_id, total_amount)
               values (:id, :t, :mr, 'doctor', :ent, 100.00)""",
            {"id": uuid.uuid4(), "t": b, "mr": mr_b, "ent": doc_b},
        )

    await app.dispose()
    await admin.dispose()
