import os
import sys
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import Depends
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from app.core.auth import Principal, get_principal
from app.core.config import settings

# If running under pytest, use NullPool so connections don't cross event loops
is_test = os.getenv("PYTEST_CURRENT_TEST") is not None or "pytest" in sys.modules

# Statement caches off: Supabase's transaction pooler does not support prepared statements.
engine_kwargs = {
    "pool_pre_ping": True,
    "connect_args": {"statement_cache_size": 0, "prepared_statement_cache_size": 0},
}
if is_test:
    engine_kwargs["poolclass"] = NullPool
else:
    engine_kwargs["pool_size"] = 10
    engine_kwargs["max_overflow"] = 5

engine = create_async_engine(settings.database_url, **engine_kwargs)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False)

# Platform engine: used strictly by the platform CLI to bootstrap tenants
platform_engine = create_async_engine(
    settings.platform_admin_url,
    pool_pre_ping=True,
    poolclass=NullPool if is_test else None,
    connect_args={"statement_cache_size": 0, "prepared_statement_cache_size": 0},
)
PlatformSessionLocal = async_sessionmaker(platform_engine, expire_on_commit=False)


@asynccontextmanager
async def platform_session() -> AsyncIterator[AsyncSession]:
    """Admin connection for CLI tenant creation."""
    async with PlatformSessionLocal() as session, session.begin():
        yield session


async def tenant_session(
    principal: Principal = Depends(get_principal),
) -> AsyncIterator[AsyncSession]:
    """One transaction per request with the tenant bound transaction-locally (RLS reads it)."""
    async with SessionLocal() as session, session.begin():
        await session.execute(
            text("select set_config('app.tenant_id', :t, true)"),
            {"t": str(principal.tenant_id)},
        )
        yield session
