import uuid
from datetime import UTC, date, datetime
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.auth import Principal
from app.core.errors import ConflictError, ForbiddenError, NotFoundError
from app.core.pagination import PaginatedResponse, PaginationParams, paginate
from app.modules.field.models import (
    POB,
    Activity,
    ChemistFeedback,
    DailyCallReport,
    DoctorFeedback,
    FieldVisit,
    POBProduct,
)
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
from app.modules.masters.models import Chemist, Doctor, Product
from app.modules.masters.service import MastersService
from app.modules.users.models import AppUser


class FieldService:
    @staticmethod
    async def get_app_user(db: AsyncSession, principal: Principal) -> AppUser:
        return await MastersService.get_app_user(db, principal)

    @staticmethod
    async def get_subordinate_user_ids(db: AsyncSession, app_user: AppUser) -> list[uuid.UUID]:
        return await MastersService.get_subordinate_user_ids(db, app_user)

    # -------------------------------------------------------------------------
    # Field Visits
    # -------------------------------------------------------------------------
    @staticmethod
    async def check_in_visit(
        db: AsyncSession, principal: Principal, data: VisitCheckInRequest
    ) -> VisitResponse:
        app_user = await FieldService.get_app_user(db, principal)

        # 1. Idempotency Check on (tenant_id, idempotency_key)
        existing_activity = await db.execute(
            select(Activity).where(
                Activity.tenant_id == principal.tenant_id,
                Activity.idempotency_key == data.idempotency_key,
                Activity.deleted_at.is_(None),
            )
        )
        act = existing_activity.scalar_one_or_none()
        if act and act.payload and "visit_id" in act.payload:
            visit_id = uuid.UUID(act.payload["visit_id"])
            existing_visit = await db.execute(
                select(FieldVisit).where(
                    FieldVisit.id == visit_id,
                    FieldVisit.tenant_id == principal.tenant_id,
                    FieldVisit.deleted_at.is_(None),
                )
            )
            visit = existing_visit.scalar_one_or_none()
            if visit:
                return VisitResponse.model_validate(visit)

        # 2. Scoping check: MR must only visit doctors/chemists in assigned territories
        accessible_territories = await MastersService.get_accessible_territory_ids(db, app_user)
        if accessible_territories is not None:
            if data.visit_type == "doctor":
                doc = (
                    await db.execute(
                        select(Doctor).where(
                            Doctor.id == data.entity_id,
                            Doctor.tenant_id == principal.tenant_id,
                            Doctor.deleted_at.is_(None),
                        )
                    )
                ).scalar_one_or_none()
                if not doc:
                    raise NotFoundError("Doctor not found in this tenant")
                if not doc.territory_id or doc.territory_id not in accessible_territories:
                    raise ForbiddenError(
                        "Cannot check in for a doctor outside assigned territories"
                    )
            elif data.visit_type == "chemist":
                chem = (
                    await db.execute(
                        select(Chemist).where(
                            Chemist.id == data.entity_id,
                            Chemist.tenant_id == principal.tenant_id,
                            Chemist.deleted_at.is_(None),
                        )
                    )
                ).scalar_one_or_none()
                if not chem:
                    raise NotFoundError("Chemist not found in this tenant")
                if not chem.territory_id or chem.territory_id not in accessible_territories:
                    raise ForbiddenError(
                        "Cannot check in for a chemist outside assigned territories"
                    )

        # 3. Create Field Visit
        now_utc = datetime.now(UTC)
        check_in_time = data.check_in_time or now_utc
        visit_date = data.visit_date or check_in_time.date()

        visit = FieldVisit(
            tenant_id=principal.tenant_id,
            mr_id=app_user.id,
            visit_type=data.visit_type,
            entity_type=data.entity_type,
            entity_id=data.entity_id,
            beat_id=data.beat_id,
            route_id=data.route_id,
            tour_plan_day_id=data.tour_plan_day_id,
            visit_date=visit_date,
            check_in_time=check_in_time,
            check_in_latitude=data.latitude,
            check_in_longitude=data.longitude,
            visit_status="in_progress",
            remarks=data.remarks,
        )
        db.add(visit)
        await db.flush()

        # 4. Create Activity Row
        activity = Activity(
            tenant_id=principal.tenant_id,
            mr_id=app_user.id,
            activity_type=f"{data.visit_type}_visit",
            entity_type=data.entity_type,
            entity_id=data.entity_id,
            started_at=check_in_time,
            latitude=data.latitude,
            longitude=data.longitude,
            payload={"visit_id": str(visit.id), "visit_type": data.visit_type},
            idempotency_key=data.idempotency_key,
        )
        db.add(activity)

        # 5. Upsert Daily Call Report (DCR)
        dcr_result = await db.execute(
            select(DailyCallReport).where(
                DailyCallReport.tenant_id == principal.tenant_id,
                DailyCallReport.mr_id == app_user.id,
                DailyCallReport.report_date == visit_date,
                DailyCallReport.deleted_at.is_(None),
            )
        )
        dcr = dcr_result.scalar_one_or_none()
        if not dcr:
            dcr = DailyCallReport(
                tenant_id=principal.tenant_id,
                mr_id=app_user.id,
                report_date=visit_date,
                beat_id=data.beat_id,
                total_calls=1,
                doctor_calls=1 if data.visit_type == "doctor" else 0,
                chemist_calls=1 if data.visit_type == "chemist" else 0,
                stockist_calls=1 if data.visit_type == "stockist" else 0,
                total_pob_value=Decimal("0.00"),
            )
            db.add(dcr)
        else:
            dcr.total_calls += 1
            if data.visit_type == "doctor":
                dcr.doctor_calls += 1
            elif data.visit_type == "chemist":
                dcr.chemist_calls += 1
            elif data.visit_type == "stockist":
                dcr.stockist_calls += 1

        await db.flush()
        await db.refresh(visit)
        return VisitResponse.model_validate(visit)

    @staticmethod
    async def check_out_visit(
        db: AsyncSession, principal: Principal, visit_id: uuid.UUID, data: VisitCheckOutRequest
    ) -> VisitResponse:
        app_user = await FieldService.get_app_user(db, principal)

        result = await db.execute(
            select(FieldVisit).where(
                FieldVisit.id == visit_id,
                FieldVisit.tenant_id == principal.tenant_id,
                FieldVisit.deleted_at.is_(None),
            )
        )
        visit = result.scalar_one_or_none()
        if not visit:
            raise NotFoundError("Field visit not found")

        # Authorization: MR must own visit, Manager must manage MR, Admin unrestricted
        if app_user.app_role == "mr" and visit.mr_id != app_user.id:
            raise ForbiddenError("Cannot check out another representative's visit")
        elif app_user.app_role == "manager":
            subordinates = await FieldService.get_subordinate_user_ids(db, app_user)
            if visit.mr_id not in subordinates:
                raise ForbiddenError("Visit does not belong to your team")

        now_utc = datetime.now(UTC)
        check_out_time = data.check_out_time or now_utc
        visit.check_out_time = check_out_time
        if data.latitude is not None:
            visit.check_out_latitude = data.latitude
        if data.longitude is not None:
            visit.check_out_longitude = data.longitude
        if data.remarks:
            visit.remarks = f"{visit.remarks}\n{data.remarks}" if visit.remarks else data.remarks
        visit.visit_status = "completed"

        if data.idempotency_key:
            # Check if checkout activity already logged
            existing_act = await db.execute(
                select(Activity.id).where(
                    Activity.tenant_id == principal.tenant_id,
                    Activity.idempotency_key == data.idempotency_key,
                )
            )
            if not existing_act.scalar_one_or_none():
                activity = Activity(
                    tenant_id=principal.tenant_id,
                    mr_id=visit.mr_id,
                    activity_type=f"{visit.visit_type}_checkout",
                    entity_type=visit.entity_type,
                    entity_id=visit.entity_id,
                    started_at=visit.check_in_time or check_out_time,
                    ended_at=check_out_time,
                    latitude=data.latitude,
                    longitude=data.longitude,
                    payload={"visit_id": str(visit.id)},
                    idempotency_key=data.idempotency_key,
                )
                db.add(activity)

        await db.flush()
        await db.refresh(visit)
        return VisitResponse.model_validate(visit)

    @staticmethod
    async def record_doctor_feedback(
        db: AsyncSession, principal: Principal, visit_id: uuid.UUID, data: DoctorFeedbackRequest
    ) -> DoctorFeedbackResponse:
        app_user = await FieldService.get_app_user(db, principal)

        result = await db.execute(
            select(FieldVisit).where(
                FieldVisit.id == visit_id,
                FieldVisit.tenant_id == principal.tenant_id,
                FieldVisit.deleted_at.is_(None),
            )
        )
        visit = result.scalar_one_or_none()
        if not visit:
            raise NotFoundError("Field visit not found")
        if visit.visit_type != "doctor":
            raise ConflictError("Cannot record doctor feedback on a non-doctor visit")

        if app_user.app_role == "mr" and visit.mr_id != app_user.id:
            raise ForbiddenError("Cannot add feedback to another representative's visit")

        # Check if feedback exists
        fb_res = await db.execute(
            select(DoctorFeedback).where(
                DoctorFeedback.tenant_id == principal.tenant_id,
                DoctorFeedback.visit_id == visit_id,
                DoctorFeedback.deleted_at.is_(None),
            )
        )
        feedback = fb_res.scalar_one_or_none()
        if not feedback:
            feedback = DoctorFeedback(
                tenant_id=principal.tenant_id,
                visit_id=visit.id,
                doctor_id=visit.entity_id,
                feedback_type=data.feedback_type,
                comments=data.comments,
                next_followup_date=data.next_followup_date,
            )
            db.add(feedback)
        else:
            feedback.feedback_type = data.feedback_type
            feedback.comments = data.comments
            feedback.next_followup_date = data.next_followup_date

        await db.flush()
        await db.refresh(feedback)
        return DoctorFeedbackResponse.model_validate(feedback)

    @staticmethod
    async def record_chemist_feedback(
        db: AsyncSession, principal: Principal, visit_id: uuid.UUID, data: ChemistFeedbackRequest
    ) -> ChemistFeedbackResponse:
        app_user = await FieldService.get_app_user(db, principal)

        result = await db.execute(
            select(FieldVisit).where(
                FieldVisit.id == visit_id,
                FieldVisit.tenant_id == principal.tenant_id,
                FieldVisit.deleted_at.is_(None),
            )
        )
        visit = result.scalar_one_or_none()
        if not visit:
            raise NotFoundError("Field visit not found")
        if visit.visit_type != "chemist":
            raise ConflictError("Cannot record chemist feedback on a non-chemist visit")

        if app_user.app_role == "mr" and visit.mr_id != app_user.id:
            raise ForbiddenError("Cannot add feedback to another representative's visit")

        fb_res = await db.execute(
            select(ChemistFeedback).where(
                ChemistFeedback.tenant_id == principal.tenant_id,
                ChemistFeedback.visit_id == visit_id,
                ChemistFeedback.deleted_at.is_(None),
            )
        )
        feedback = fb_res.scalar_one_or_none()
        if not feedback:
            feedback = ChemistFeedback(
                tenant_id=principal.tenant_id,
                visit_id=visit.id,
                chemist_id=visit.entity_id,
                stock_issue=data.stock_issue,
                competitor_activity=data.competitor_activity,
                comments=data.comments,
            )
            db.add(feedback)
        else:
            feedback.stock_issue = data.stock_issue
            feedback.competitor_activity = data.competitor_activity
            feedback.comments = data.comments

        await db.flush()
        await db.refresh(feedback)
        return ChemistFeedbackResponse.model_validate(feedback)

    # -------------------------------------------------------------------------
    # Pre-Order Bookings (POBs)
    # -------------------------------------------------------------------------
    @staticmethod
    async def create_pob(db: AsyncSession, principal: Principal, data: POBCreate) -> POBResponse:
        app_user = await FieldService.get_app_user(db, principal)

        # 1. Idempotency Check on (tenant_id, idempotency_key)
        existing_act = await db.execute(
            select(Activity).where(
                Activity.tenant_id == principal.tenant_id,
                Activity.idempotency_key == data.idempotency_key,
                Activity.deleted_at.is_(None),
            )
        )
        act = existing_act.scalar_one_or_none()
        if act and act.payload and "pob_id" in act.payload:
            pob_id = uuid.UUID(act.payload["pob_id"])
            existing_pob = await db.execute(
                select(POB)
                .options(selectinload(POB.products))
                .where(
                    POB.id == pob_id,
                    POB.tenant_id == principal.tenant_id,
                    POB.deleted_at.is_(None),
                )
            )
            pob = existing_pob.scalar_one_or_none()
            if pob:
                return POBResponse.model_validate(pob)

        # 2. Validate line items and calculate server-side totals
        total_pob_amount = Decimal("0.00")
        line_items: list[POBProduct] = []

        for item_data in data.items:
            prod_res = await db.execute(
                select(Product).where(
                    Product.id == item_data.product_id,
                    Product.tenant_id == principal.tenant_id,
                    Product.deleted_at.is_(None),
                )
            )
            product = prod_res.scalar_one_or_none()
            if not product:
                raise NotFoundError(f"Product {item_data.product_id} not found")
            if not product.is_active:
                raise ConflictError(f"Product '{product.name}' is inactive")

            rate = item_data.rate if item_data.rate is not None else product.ptr
            discount_multiplier = Decimal("1.00") - (item_data.discount_percent / Decimal("100.00"))
            line_total = (rate * Decimal(item_data.quantity) * discount_multiplier).quantize(
                Decimal("0.01")
            )

            pob_item = POBProduct(
                tenant_id=principal.tenant_id,
                product_id=product.id,
                quantity=item_data.quantity,
                rate=rate,
                total_amount=line_total,
                discount_percent=item_data.discount_percent,
            )
            line_items.append(pob_item)
            total_pob_amount += line_total

        # 3. Create POB Header
        pob_date = data.pob_date or date.today()
        pob = POB(
            tenant_id=principal.tenant_id,
            visit_id=data.visit_id,
            mr_id=app_user.id,
            customer_type=data.customer_type,
            entity_id=data.entity_id,
            stockist_id=data.stockist_id,
            pob_date=pob_date,
            total_amount=total_pob_amount,
            status="booked",
            expected_delivery_date=data.expected_delivery_date,
        )
        pob.products = line_items
        db.add(pob)
        await db.flush()

        # 4. Activity Row
        activity = Activity(
            tenant_id=principal.tenant_id,
            mr_id=app_user.id,
            activity_type="pob",
            entity_type=f"{data.customer_type}s",
            entity_id=data.entity_id,
            started_at=datetime.now(UTC),
            payload={
                "pob_id": str(pob.id),
                "total_amount": str(pob.total_amount),
                "items_count": len(line_items),
            },
            idempotency_key=data.idempotency_key,
        )
        db.add(activity)

        # 5. Update DCR total_pob_value
        dcr_result = await db.execute(
            select(DailyCallReport).where(
                DailyCallReport.tenant_id == principal.tenant_id,
                DailyCallReport.mr_id == app_user.id,
                DailyCallReport.report_date == pob_date,
                DailyCallReport.deleted_at.is_(None),
            )
        )
        dcr = dcr_result.scalar_one_or_none()
        if dcr:
            dcr.total_pob_value += total_pob_amount

        await db.flush()
        pob_res = await db.execute(
            select(POB).options(selectinload(POB.products)).where(POB.id == pob.id)
        )
        saved_pob = pob_res.scalar_one()
        return POBResponse.model_validate(saved_pob)

    # -------------------------------------------------------------------------
    # List and Read Queries
    # -------------------------------------------------------------------------
    @staticmethod
    async def list_visits(
        db: AsyncSession,
        principal: Principal,
        pagination: PaginationParams,
        mr_id: uuid.UUID | None = None,
        visit_type: str | None = None,
        visit_status: str | None = None,
        from_date: date | None = None,
        to_date: date | None = None,
    ) -> PaginatedResponse[VisitResponse]:
        app_user = await FieldService.get_app_user(db, principal)

        query = select(FieldVisit).where(
            FieldVisit.tenant_id == principal.tenant_id,
            FieldVisit.deleted_at.is_(None),
        )

        if app_user.app_role == "mr":
            query = query.where(FieldVisit.mr_id == app_user.id)
        elif app_user.app_role == "manager":
            subordinates = await FieldService.get_subordinate_user_ids(db, app_user)
            query = query.where(FieldVisit.mr_id.in_(subordinates))

        if mr_id:
            if app_user.app_role == "mr" and mr_id != app_user.id:
                raise ForbiddenError("Cannot view visits of another representative")
            elif app_user.app_role == "manager":
                subordinates = await FieldService.get_subordinate_user_ids(db, app_user)
                if mr_id not in subordinates:
                    raise ForbiddenError("Representative does not belong to your team")
            query = query.where(FieldVisit.mr_id == mr_id)

        if visit_type:
            query = query.where(FieldVisit.visit_type == visit_type)
        if visit_status:
            query = query.where(FieldVisit.visit_status == visit_status)
        if from_date:
            query = query.where(FieldVisit.visit_date >= from_date)
        if to_date:
            query = query.where(FieldVisit.visit_date <= to_date)

        items, total, total_pages = await paginate(
            db,
            query.order_by(FieldVisit.visit_date.desc(), FieldVisit.created_at.desc()),
            pagination,
        )
        return PaginatedResponse(
            items=[VisitResponse.model_validate(v) for v in items],
            total=total,
            page=pagination.page,
            page_size=pagination.page_size,
            total_pages=total_pages,
        )

    @staticmethod
    async def get_visit(
        db: AsyncSession, principal: Principal, visit_id: uuid.UUID
    ) -> VisitResponse:
        app_user = await FieldService.get_app_user(db, principal)

        result = await db.execute(
            select(FieldVisit).where(
                FieldVisit.id == visit_id,
                FieldVisit.tenant_id == principal.tenant_id,
                FieldVisit.deleted_at.is_(None),
            )
        )
        visit = result.scalar_one_or_none()
        if not visit:
            raise NotFoundError("Field visit not found")

        if app_user.app_role == "mr" and visit.mr_id != app_user.id:
            raise ForbiddenError("You do not have access to this visit")
        elif app_user.app_role == "manager":
            subordinates = await FieldService.get_subordinate_user_ids(db, app_user)
            if visit.mr_id not in subordinates:
                raise ForbiddenError("Visit does not belong to your team")

        return VisitResponse.model_validate(visit)

    @staticmethod
    async def list_daily_call_reports(
        db: AsyncSession,
        principal: Principal,
        pagination: PaginationParams,
        mr_id: uuid.UUID | None = None,
        from_date: date | None = None,
        to_date: date | None = None,
    ) -> PaginatedResponse[DailyCallReportResponse]:
        app_user = await FieldService.get_app_user(db, principal)

        query = select(DailyCallReport).where(
            DailyCallReport.tenant_id == principal.tenant_id,
            DailyCallReport.deleted_at.is_(None),
        )

        if app_user.app_role == "mr":
            query = query.where(DailyCallReport.mr_id == app_user.id)
        elif app_user.app_role == "manager":
            subordinates = await FieldService.get_subordinate_user_ids(db, app_user)
            query = query.where(DailyCallReport.mr_id.in_(subordinates))

        if mr_id:
            if app_user.app_role == "mr" and mr_id != app_user.id:
                raise ForbiddenError("Cannot view reports of another representative")
            elif app_user.app_role == "manager":
                subordinates = await FieldService.get_subordinate_user_ids(db, app_user)
                if mr_id not in subordinates:
                    raise ForbiddenError("Representative does not belong to your team")
            query = query.where(DailyCallReport.mr_id == mr_id)

        if from_date:
            query = query.where(DailyCallReport.report_date >= from_date)
        if to_date:
            query = query.where(DailyCallReport.report_date <= to_date)

        items, total, total_pages = await paginate(
            db, query.order_by(DailyCallReport.report_date.desc()), pagination
        )
        return PaginatedResponse(
            items=[DailyCallReportResponse.model_validate(r) for r in items],
            total=total,
            page=pagination.page,
            page_size=pagination.page_size,
            total_pages=total_pages,
        )
