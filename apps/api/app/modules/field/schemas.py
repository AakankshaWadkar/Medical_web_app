import uuid
from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


# -----------------------------------------------------------------------------
# Field Visits
# -----------------------------------------------------------------------------
class VisitCheckInRequest(BaseModel):
    idempotency_key: uuid.UUID
    visit_type: str = Field(..., pattern=r"^(doctor|chemist|stockist|hospital)$")
    entity_type: str = Field(..., pattern=r"^(doctors|chemists|stockists|hospitals)$")
    entity_id: uuid.UUID
    beat_id: uuid.UUID | None = None
    route_id: uuid.UUID | None = None
    tour_plan_day_id: uuid.UUID | None = None
    visit_date: date | None = None
    check_in_time: datetime | None = None
    latitude: float | None = None
    longitude: float | None = None
    remarks: str | None = None


class VisitCheckOutRequest(BaseModel):
    idempotency_key: uuid.UUID | None = None
    check_out_time: datetime | None = None
    latitude: float | None = None
    longitude: float | None = None
    remarks: str | None = None


class VisitResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    mr_id: uuid.UUID
    visit_type: str
    entity_type: str
    entity_id: uuid.UUID
    beat_id: uuid.UUID | None = None
    route_id: uuid.UUID | None = None
    tour_plan_day_id: uuid.UUID | None = None
    visit_date: date
    check_in_time: datetime | None = None
    check_out_time: datetime | None = None
    check_in_latitude: float | None = None
    check_in_longitude: float | None = None
    check_out_latitude: float | None = None
    check_out_longitude: float | None = None
    visit_status: str
    remarks: str | None = None
    created_at: datetime
    updated_at: datetime


# -----------------------------------------------------------------------------
# Feedbacks
# -----------------------------------------------------------------------------
class DoctorFeedbackRequest(BaseModel):
    feedback_type: str = Field(
        "positive",
        pattern=r"^(positive|neutral|negative|requested_literature|competitor_price_issue)$",
    )
    comments: str | None = None
    next_followup_date: date | None = None


class DoctorFeedbackResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    visit_id: uuid.UUID
    doctor_id: uuid.UUID
    feedback_type: str
    comments: str | None = None
    next_followup_date: date | None = None
    created_at: datetime


class ChemistFeedbackRequest(BaseModel):
    stock_issue: bool = False
    competitor_activity: str | None = None
    comments: str | None = None


class ChemistFeedbackResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    visit_id: uuid.UUID
    chemist_id: uuid.UUID
    stock_issue: bool
    competitor_activity: str | None = None
    comments: str | None = None
    created_at: datetime


# -----------------------------------------------------------------------------
# POBs
# -----------------------------------------------------------------------------
class POBProductCreate(BaseModel):
    product_id: uuid.UUID
    quantity: int = Field(..., gt=0)
    rate: Decimal | None = Field(None, ge=0)
    discount_percent: Decimal = Field(Decimal("0.00"), ge=0, le=100)


class POBCreate(BaseModel):
    idempotency_key: uuid.UUID
    visit_id: uuid.UUID | None = None
    customer_type: str = Field(..., pattern=r"^(chemist|doctor|hospital)$")
    entity_id: uuid.UUID
    stockist_id: uuid.UUID | None = None
    pob_date: date | None = None
    expected_delivery_date: date | None = None
    items: list[POBProductCreate] = Field(..., min_length=1)


class POBProductResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    pob_id: uuid.UUID
    product_id: uuid.UUID
    quantity: int
    rate: Decimal
    total_amount: Decimal
    discount_percent: Decimal
    created_at: datetime


class POBResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    visit_id: uuid.UUID | None = None
    mr_id: uuid.UUID
    customer_type: str
    entity_id: uuid.UUID
    stockist_id: uuid.UUID | None = None
    pob_date: date
    total_amount: Decimal
    status: str
    expected_delivery_date: date | None = None
    products: list[POBProductResponse] = []
    created_at: datetime
    updated_at: datetime


# -----------------------------------------------------------------------------
# Daily Call Report
# -----------------------------------------------------------------------------
class DailyCallReportResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    mr_id: uuid.UUID
    report_date: date
    beat_id: uuid.UUID | None = None
    total_calls: int
    doctor_calls: int
    chemist_calls: int
    stockist_calls: int
    total_pob_value: Decimal
    status: str
    submitted_at: datetime | None = None
    approved_by_user_id: uuid.UUID | None = None
    created_at: datetime
