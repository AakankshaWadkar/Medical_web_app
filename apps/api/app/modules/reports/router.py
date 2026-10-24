import uuid
from datetime import date

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import Principal, require_roles
from app.core.db import tenant_session
from app.core.pagination import PaginatedResponse, PaginationParams
from app.modules.reports.schemas import (
    DoctorCoverageResponse,
    MRPerformanceResponse,
    SecondarySalesAggregateResponse,
)
from app.modules.reports.service import ReportsService

router = APIRouter(prefix="/v1/reports", tags=["Analytics & Reports"])


@router.get(
    "/mr-performance",
    response_model=PaginatedResponse[MRPerformanceResponse],
    summary="MR performance summary reading view_mr_performance_summary",
)
async def get_mr_performance(
    mr_id: uuid.UUID | None = Query(None, description="Filter by MR ID"),
    from_month: date | None = Query(
        None, description="Filter starting from report month (YYYY-MM-01)"
    ),
    to_month: date | None = Query(None, description="Filter up to report month (YYYY-MM-01)"),
    pagination: PaginationParams = Depends(),
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> PaginatedResponse[MRPerformanceResponse]:
    return await ReportsService.get_mr_performance(
        db=db,
        principal=principal,
        pagination=pagination,
        mr_id=mr_id,
        from_month=from_month,
        to_month=to_month,
    )


@router.get(
    "/doctor-coverage",
    response_model=PaginatedResponse[DoctorCoverageResponse],
    summary="Doctor coverage metrics reading view_doctor_coverage_metrics",
)
async def get_doctor_coverage(
    doctor_id: uuid.UUID | None = Query(None, description="Filter by doctor ID"),
    coverage_status: str | None = Query(
        None, description="Filter by coverage status (target_met / below_target)"
    ),
    from_month: date | None = Query(
        None, description="Filter starting from coverage month (YYYY-MM-01)"
    ),
    to_month: date | None = Query(None, description="Filter up to coverage month (YYYY-MM-01)"),
    pagination: PaginationParams = Depends(),
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> PaginatedResponse[DoctorCoverageResponse]:
    return await ReportsService.get_doctor_coverage(
        db=db,
        principal=principal,
        pagination=pagination,
        doctor_id=doctor_id,
        coverage_status=coverage_status,
        from_month=from_month,
        to_month=to_month,
    )


@router.get(
    "/secondary-sales",
    response_model=PaginatedResponse[SecondarySalesAggregateResponse],
    summary="Secondary sales aggregates reading view_secondary_sales_aggregates",
)
async def get_secondary_sales_aggregates(
    stockist_id: uuid.UUID | None = Query(None, description="Filter by stockist ID"),
    product_id: uuid.UUID | None = Query(None, description="Filter by product ID"),
    reporting_month: int | None = Query(None, description="Filter by reporting month (1-12)"),
    reporting_year: int | None = Query(None, description="Filter by reporting year"),
    pagination: PaginationParams = Depends(),
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> PaginatedResponse[SecondarySalesAggregateResponse]:
    return await ReportsService.get_secondary_sales_aggregates(
        db=db,
        principal=principal,
        pagination=pagination,
        stockist_id=stockist_id,
        product_id=product_id,
        reporting_month=reporting_month,
        reporting_year=reporting_year,
    )
