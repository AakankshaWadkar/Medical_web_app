import uuid
from datetime import date

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import Principal
from app.core.errors import ForbiddenError
from app.core.pagination import PaginatedResponse, PaginationParams, paginate
from app.modules.masters.models import Doctor
from app.modules.masters.service import MastersService
from app.modules.reports.models import (
    DoctorCoverageMetric,
    MRPerformanceSummary,
    SecondarySalesAggregate,
)
from app.modules.reports.schemas import (
    DoctorCoverageResponse,
    MRPerformanceResponse,
    SecondarySalesAggregateResponse,
)
from app.modules.users.models import AppUser


class ReportsService:
    @staticmethod
    async def get_app_user(db: AsyncSession, principal: Principal) -> AppUser:
        return await MastersService.get_app_user(db, principal)

    @staticmethod
    async def get_subordinate_user_ids(db: AsyncSession, app_user: AppUser) -> list[uuid.UUID]:
        return await MastersService.get_subordinate_user_ids(db, app_user)

    @staticmethod
    async def get_mr_performance(
        db: AsyncSession,
        principal: Principal,
        pagination: PaginationParams,
        mr_id: uuid.UUID | None = None,
        from_month: date | None = None,
        to_month: date | None = None,
    ) -> PaginatedResponse[MRPerformanceResponse]:
        app_user = await ReportsService.get_app_user(db, principal)

        query = select(MRPerformanceSummary).where(
            MRPerformanceSummary.tenant_id == principal.tenant_id
        )

        if app_user.app_role == "mr":
            query = query.where(MRPerformanceSummary.mr_id == app_user.id)
        elif app_user.app_role == "manager":
            subordinates = await ReportsService.get_subordinate_user_ids(db, app_user)
            query = query.where(MRPerformanceSummary.mr_id.in_(subordinates))

        if mr_id:
            if app_user.app_role == "mr" and mr_id != app_user.id:
                raise ForbiddenError("Cannot view performance report of another representative")
            elif app_user.app_role == "manager":
                subordinates = await ReportsService.get_subordinate_user_ids(db, app_user)
                if mr_id not in subordinates:
                    raise ForbiddenError("Representative does not belong to your team")
            query = query.where(MRPerformanceSummary.mr_id == mr_id)

        if from_month:
            query = query.where(MRPerformanceSummary.report_month >= from_month)
        if to_month:
            query = query.where(MRPerformanceSummary.report_month <= to_month)

        items, total, total_pages = await paginate(
            db,
            query.order_by(
                MRPerformanceSummary.report_month.desc(), MRPerformanceSummary.mr_name.asc()
            ),
            pagination,
        )
        return PaginatedResponse(
            items=[MRPerformanceResponse.model_validate(row) for row in items],
            total=total,
            page=pagination.page,
            page_size=pagination.page_size,
            total_pages=total_pages,
        )

    @staticmethod
    async def get_doctor_coverage(
        db: AsyncSession,
        principal: Principal,
        pagination: PaginationParams,
        doctor_id: uuid.UUID | None = None,
        coverage_status: str | None = None,
        from_month: date | None = None,
        to_month: date | None = None,
    ) -> PaginatedResponse[DoctorCoverageResponse]:
        app_user = await ReportsService.get_app_user(db, principal)
        accessible_territories = await MastersService.get_accessible_territory_ids(db, app_user)

        query = select(DoctorCoverageMetric).where(
            DoctorCoverageMetric.tenant_id == principal.tenant_id
        )

        if accessible_territories is not None:
            if not accessible_territories:
                return PaginatedResponse(
                    items=[],
                    total=0,
                    page=pagination.page,
                    page_size=pagination.page_size,
                    total_pages=0,
                )
            doc_ids_subq = (
                select(Doctor.id)
                .where(
                    Doctor.tenant_id == principal.tenant_id,
                    Doctor.territory_id.in_(accessible_territories),
                    Doctor.deleted_at.is_(None),
                )
                .scalar_subquery()
            )
            query = query.where(DoctorCoverageMetric.doctor_id.in_(doc_ids_subq))

        if doctor_id:
            query = query.where(DoctorCoverageMetric.doctor_id == doctor_id)
        if coverage_status:
            query = query.where(DoctorCoverageMetric.coverage_status == coverage_status)
        if from_month:
            query = query.where(DoctorCoverageMetric.coverage_month >= from_month)
        if to_month:
            query = query.where(DoctorCoverageMetric.coverage_month <= to_month)

        items, total, total_pages = await paginate(
            db,
            query.order_by(
                DoctorCoverageMetric.coverage_month.desc().nulls_last(),
                DoctorCoverageMetric.doctor_name.asc(),
            ),
            pagination,
        )
        return PaginatedResponse(
            items=[DoctorCoverageResponse.model_validate(row) for row in items],
            total=total,
            page=pagination.page,
            page_size=pagination.page_size,
            total_pages=total_pages,
        )

    @staticmethod
    async def get_secondary_sales_aggregates(
        db: AsyncSession,
        principal: Principal,
        pagination: PaginationParams,
        stockist_id: uuid.UUID | None = None,
        product_id: uuid.UUID | None = None,
        reporting_month: int | None = None,
        reporting_year: int | None = None,
    ) -> PaginatedResponse[SecondarySalesAggregateResponse]:
        query = select(SecondarySalesAggregate).where(
            SecondarySalesAggregate.tenant_id == principal.tenant_id
        )

        if stockist_id:
            query = query.where(SecondarySalesAggregate.stockist_id == stockist_id)
        if product_id:
            query = query.where(SecondarySalesAggregate.product_id == product_id)
        if reporting_month:
            query = query.where(SecondarySalesAggregate.reporting_month == reporting_month)
        if reporting_year:
            query = query.where(SecondarySalesAggregate.reporting_year == reporting_year)

        items, total, total_pages = await paginate(
            db,
            query.order_by(
                SecondarySalesAggregate.reporting_year.desc(),
                SecondarySalesAggregate.reporting_month.desc(),
                SecondarySalesAggregate.stockist_name.asc(),
            ),
            pagination,
        )
        return PaginatedResponse(
            items=[SecondarySalesAggregateResponse.model_validate(row) for row in items],
            total=total,
            page=pagination.page,
            page_size=pagination.page_size,
            total_pages=total_pages,
        )
