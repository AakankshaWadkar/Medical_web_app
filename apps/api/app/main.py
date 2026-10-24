from fastapi import Depends, FastAPI
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import Principal, get_principal
from app.core.db import tenant_session
from app.core.errors import register_error_handlers
from app.core.middleware import RequestIDMiddleware
from app.modules.field.router import router as field_router
from app.modules.masters.router import router as masters_router
from app.modules.orders.router import router as orders_router
from app.modules.reports.router import router as reports_router
from app.modules.users.router import router as users_router

app = FastAPI(
    title="PharmaSphere API",
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)

# Middleware
app.add_middleware(RequestIDMiddleware)

# Error handlers
register_error_handlers(app)

# Routers
app.include_router(users_router)
app.include_router(masters_router)
app.include_router(field_router)
app.include_router(orders_router)
app.include_router(reports_router)


class HealthResponse(BaseModel):
    status: str


class MeResponse(BaseModel):
    user_id: str
    app_user_id: str | None
    tenant_id: str
    tenant_name: str | None
    role: str
    full_name: str | None


@app.get("/healthz", response_model=HealthResponse, tags=["System"], summary="Health check")
async def healthz() -> HealthResponse:
    return HealthResponse(status="ok")


@app.get(
    "/v1/me",
    response_model=MeResponse,
    tags=["Auth"],
    summary="Get current user principal and tenant info",
)
async def me(
    p: Principal = Depends(get_principal),
    db: AsyncSession = Depends(tenant_session),
) -> MeResponse:
    # Query tenant details
    tenant_name = (await db.execute(text("select name from public.tenants"))).scalar_one_or_none()

    # Query app_users record for this authenticated user
    user_row = (
        await db.execute(
            text(
                "select id, full_name from public.app_users where auth_user_id = :auth_id and deleted_at is null"
            ),
            {"auth_id": p.user_id},
        )
    ).first()

    app_user_id = str(user_row.id) if user_row else None
    full_name = user_row.full_name if user_row else None

    return MeResponse(
        user_id=str(p.user_id),
        app_user_id=app_user_id,
        tenant_id=str(p.tenant_id),
        tenant_name=tenant_name,
        role=p.role,
        full_name=full_name,
    )
