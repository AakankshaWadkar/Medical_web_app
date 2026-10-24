import uuid
from datetime import date

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import Principal, require_roles
from app.core.db import tenant_session
from app.core.pagination import PaginatedResponse, PaginationParams
from app.modules.orders.schemas import (
    PrimaryOrderCreate,
    PrimaryOrderResponse,
    PrimaryOrderStatusUpdate,
    SecondarySaleCreate,
    SecondarySaleResponse,
)
from app.modules.orders.service import OrdersService

router = APIRouter(prefix="/v1/orders", tags=["Orders & Secondary Sales"])


# -----------------------------------------------------------------------------
# Primary Orders
# -----------------------------------------------------------------------------
@router.post(
    "/primary",
    response_model=PrimaryOrderResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create primary wholesale order from stockist to company",
)
async def create_primary_order(
    payload: PrimaryOrderCreate,
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> PrimaryOrderResponse:
    return await OrdersService.create_primary_order(db=db, principal=principal, data=payload)


@router.get(
    "/primary",
    response_model=PaginatedResponse[PrimaryOrderResponse],
    summary="List primary orders with filtering and pagination",
)
async def list_primary_orders(
    stockist_id: uuid.UUID | None = Query(None, description="Filter by stockist ID"),
    order_status: str | None = Query(None, alias="status", description="Filter by order status"),
    from_date: date | None = Query(None, description="Filter starting from date"),
    to_date: date | None = Query(None, description="Filter up to date"),
    pagination: PaginationParams = Depends(),
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> PaginatedResponse[PrimaryOrderResponse]:
    return await OrdersService.list_primary_orders(
        db=db,
        principal=principal,
        pagination=pagination,
        stockist_id=stockist_id,
        status=order_status,
        from_date=from_date,
        to_date=to_date,
    )


@router.get(
    "/primary/{id}",
    response_model=PrimaryOrderResponse,
    summary="Get primary order by ID with line items",
)
async def get_primary_order(
    id: uuid.UUID,
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> PrimaryOrderResponse:
    return await OrdersService.get_primary_order(db=db, principal=principal, order_id=id)


@router.patch(
    "/primary/{id}/status",
    response_model=PrimaryOrderResponse,
    summary="Update primary order status (state machine transition)",
)
async def update_primary_order_status(
    id: uuid.UUID,
    payload: PrimaryOrderStatusUpdate,
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> PrimaryOrderResponse:
    return await OrdersService.update_primary_order_status(
        db=db, principal=principal, order_id=id, data=payload
    )


# -----------------------------------------------------------------------------
# Secondary Sales
# -----------------------------------------------------------------------------
@router.post(
    "/secondary",
    response_model=SecondarySaleResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Record secondary sales statement / chemist order from stockist",
)
async def create_secondary_sale(
    payload: SecondarySaleCreate,
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> SecondarySaleResponse:
    return await OrdersService.create_secondary_sale(db=db, principal=principal, data=payload)


@router.get(
    "/secondary",
    response_model=PaginatedResponse[SecondarySaleResponse],
    summary="List secondary sales statements",
)
async def list_secondary_sales(
    stockist_id: uuid.UUID | None = Query(None, description="Filter by stockist ID"),
    chemist_id: uuid.UUID | None = Query(None, description="Filter by chemist ID"),
    reporting_month: int | None = Query(None, description="Filter by month (1-12)"),
    reporting_year: int | None = Query(None, description="Filter by year"),
    pagination: PaginationParams = Depends(),
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> PaginatedResponse[SecondarySaleResponse]:
    return await OrdersService.list_secondary_sales(
        db=db,
        principal=principal,
        pagination=pagination,
        stockist_id=stockist_id,
        chemist_id=chemist_id,
        reporting_month=reporting_month,
        reporting_year=reporting_year,
    )


@router.get(
    "/secondary/{id}",
    response_model=SecondarySaleResponse,
    summary="Get secondary sales record by ID with item lines",
)
async def get_secondary_sale(
    id: uuid.UUID,
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> SecondarySaleResponse:
    return await OrdersService.get_secondary_sale(db=db, principal=principal, sale_id=id)
