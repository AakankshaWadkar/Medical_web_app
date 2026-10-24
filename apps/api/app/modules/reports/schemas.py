import uuid
from datetime import date
from decimal import Decimal

from pydantic import BaseModel, ConfigDict


class MRPerformanceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    tenant_id: uuid.UUID
    mr_id: uuid.UUID
    mr_name: str
    report_month: date
    total_visits: int
    doctor_visits: int
    chemist_visits: int
    stockist_visits: int
    total_pob_booked: Decimal


class DoctorCoverageResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    tenant_id: uuid.UUID
    doctor_id: uuid.UUID
    doctor_code: str
    doctor_name: str
    category_name: str
    target_frequency: int
    coverage_month: date | None = None
    visits_completed: int
    coverage_status: str


class SecondarySalesAggregateResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    tenant_id: uuid.UUID
    stockist_id: uuid.UUID
    product_id: uuid.UUID
    reporting_month: int
    reporting_year: int
    stockist_name: str
    product_name: str
    total_quantity_sold: int
    total_free_quantity: int
    total_secondary_sales_value: Decimal
