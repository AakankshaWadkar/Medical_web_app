import uuid
from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


# -----------------------------------------------------------------------------
# Primary Orders
# -----------------------------------------------------------------------------
class PrimaryOrderItemCreate(BaseModel):
    product_id: uuid.UUID
    ordered_quantity: int = Field(..., gt=0)
    unit_price: Decimal | None = Field(None, ge=0)
    discount_percent: Decimal = Field(Decimal("0.00"), ge=0, le=100)
    tax_percent: Decimal = Field(Decimal("0.00"), ge=0, le=100)


class PrimaryOrderCreate(BaseModel):
    order_number: str | None = Field(None, max_length=50)
    stockist_id: uuid.UUID
    division_id: uuid.UUID | None = None
    order_date: date | None = None
    items: list[PrimaryOrderItemCreate] = Field(..., min_length=1)


class PrimaryOrderStatusUpdate(BaseModel):
    status: str = Field(
        ...,
        pattern=r"^(draft|submitted|approved|processing|dispatched|cancelled)$",
        description="Target order status",
    )


class PrimaryOrderItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    primary_order_id: uuid.UUID
    product_id: uuid.UUID
    ordered_quantity: int
    unit_price: Decimal
    discount_percent: Decimal
    tax_amount: Decimal
    line_total: Decimal
    created_at: datetime


class PrimaryOrderResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    order_number: str
    stockist_id: uuid.UUID
    division_id: uuid.UUID | None = None
    order_date: date
    status: str
    subtotal: Decimal
    tax_amount: Decimal
    total_amount: Decimal
    items: list[PrimaryOrderItemResponse] = []
    created_at: datetime
    updated_at: datetime


# -----------------------------------------------------------------------------
# Secondary Sales
# -----------------------------------------------------------------------------
class SecondarySaleItemCreate(BaseModel):
    product_id: uuid.UUID
    batch_id: uuid.UUID | None = None
    quantity: int = Field(..., ge=0)
    free_quantity: int = Field(0, ge=0)
    rate: Decimal | None = Field(None, ge=0)


class SecondarySaleCreate(BaseModel):
    stockist_id: uuid.UUID
    chemist_id: uuid.UUID | None = None
    sale_date: date | None = None
    invoice_no: str | None = Field(None, max_length=100)
    reporting_month: int | None = Field(None, ge=1, le=12)
    reporting_year: int | None = Field(None, ge=2000, le=2100)
    items: list[SecondarySaleItemCreate] = Field(..., min_length=1)


class SecondarySaleItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    secondary_sales_id: uuid.UUID
    product_id: uuid.UUID
    batch_id: uuid.UUID | None = None
    quantity: int
    free_quantity: int
    rate: Decimal
    total_amount: Decimal
    created_at: datetime


class SecondarySaleResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    stockist_id: uuid.UUID
    chemist_id: uuid.UUID | None = None
    sale_date: date
    invoice_no: str | None = None
    total_value: Decimal
    reporting_month: int
    reporting_year: int
    items: list[SecondarySaleItemResponse] = []
    created_at: datetime
    updated_at: datetime
