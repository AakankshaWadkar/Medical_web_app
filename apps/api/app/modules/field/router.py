import uuid
from datetime import date

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import Principal, require_roles
from app.core.db import tenant_session
from app.core.pagination import PaginatedResponse, PaginationParams
from app.modules.field.schemas import (
    ChemistFeedbackRequest,
    ChemistFeedbackResponse,
    DailyCallReportResponse,
    DoctorFeedbackRequest,
    DoctorFeedbackResponse,
    POBCreate,
    POBResponse,
    VisitCheckInRequest,
    VisitCheckOutRequest,
    VisitResponse,
)
from app.modules.field.service import FieldService

router = APIRouter(prefix="/v1", tags=["Field Operations"])


@router.post(
    "/visits/check-in",
    response_model=VisitResponse,
    status_code=status.HTTP_201_CREATED,
    summary="MR check-in to doctor or chemist visit",
)
async def check_in_visit(
    payload: VisitCheckInRequest,
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> VisitResponse:
    return await FieldService.check_in_visit(db=db, principal=principal, data=payload)


@router.post(
    "/visits/{id}/check-out",
    response_model=VisitResponse,
    summary="MR check-out from field visit",
)
async def check_out_visit(
    id: uuid.UUID,
    payload: VisitCheckOutRequest,
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> VisitResponse:
    return await FieldService.check_out_visit(db=db, principal=principal, visit_id=id, data=payload)


@router.post(
    "/visits/{id}/doctor-feedback",
    response_model=DoctorFeedbackResponse,
    summary="Record doctor call feedback",
)
async def record_doctor_feedback(
    id: uuid.UUID,
    payload: DoctorFeedbackRequest,
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> DoctorFeedbackResponse:
    return await FieldService.record_doctor_feedback(
        db=db, principal=principal, visit_id=id, data=payload
    )


@router.post(
    "/visits/{id}/chemist-feedback",
    response_model=ChemistFeedbackResponse,
    summary="Record chemist call feedback",
)
async def record_chemist_feedback(
    id: uuid.UUID,
    payload: ChemistFeedbackRequest,
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> ChemistFeedbackResponse:
    return await FieldService.record_chemist_feedback(
        db=db, principal=principal, visit_id=id, data=payload
    )


@router.post(
    "/pobs",
    response_model=POBResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Book Pre-Order Booking (POB) in the field",
)
async def create_pob(
    payload: POBCreate,
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> POBResponse:
    return await FieldService.create_pob(db=db, principal=principal, data=payload)


@router.get(
    "/visits",
    response_model=PaginatedResponse[VisitResponse],
    summary="List field visits with role scoping and filters",
)
async def list_visits(
    mr_id: uuid.UUID | None = Query(None, description="Filter by MR ID"),
    visit_type: str | None = Query(None, description="Filter by visit type"),
    visit_status: str | None = Query(None, description="Filter by visit status"),
    from_date: date | None = Query(None, description="Filter starting from date"),
    to_date: date | None = Query(None, description="Filter up to date"),
    pagination: PaginationParams = Depends(),
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> PaginatedResponse[VisitResponse]:
    return await FieldService.list_visits(
        db=db,
        principal=principal,
        pagination=pagination,
        mr_id=mr_id,
        visit_type=visit_type,
        visit_status=visit_status,
        from_date=from_date,
        to_date=to_date,
    )


@router.get(
    "/visits/{id}",
    response_model=VisitResponse,
    summary="Get field visit by ID",
)
async def get_visit(
    id: uuid.UUID,
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> VisitResponse:
    return await FieldService.get_visit(db=db, principal=principal, visit_id=id)


@router.get(
    "/dcr",
    response_model=PaginatedResponse[DailyCallReportResponse],
    summary="Read Daily Call Reports (DCR) with role scoping",
)
async def list_daily_call_reports(
    mr_id: uuid.UUID | None = Query(None, description="Filter by MR ID"),
    from_date: date | None = Query(None, description="Filter starting from date"),
    to_date: date | None = Query(None, description="Filter up to date"),
    pagination: PaginationParams = Depends(),
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> PaginatedResponse[DailyCallReportResponse]:
    return await FieldService.list_daily_call_reports(
        db=db,
        principal=principal,
        pagination=pagination,
        mr_id=mr_id,
        from_date=from_date,
        to_date=to_date,
    )
