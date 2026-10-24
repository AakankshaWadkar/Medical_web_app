import uuid
from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


# -----------------------------------------------------------------------------
# Territories
# -----------------------------------------------------------------------------
class TerritoryCreate(BaseModel):
    area_id: uuid.UUID
    code: str = Field(..., min_length=2, max_length=50)
    name: str = Field(..., min_length=2, max_length=255)
    manager_id: uuid.UUID | None = None


class TerritoryUpdate(BaseModel):
    name: str | None = Field(None, min_length=2, max_length=255)
    area_id: uuid.UUID | None = None
    manager_id: uuid.UUID | None = None


class TerritoryAssignMR(BaseModel):
    mr_id: uuid.UUID


class TerritoryResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    area_id: uuid.UUID
    code: str
    name: str
    manager_id: uuid.UUID | None = None
    created_at: datetime
    updated_at: datetime


# -----------------------------------------------------------------------------
# Doctors
# -----------------------------------------------------------------------------
class DoctorCreate(BaseModel):
    doctor_code: str = Field(..., min_length=2, max_length=50)
    name: str = Field(..., min_length=2, max_length=255)
    gender: str | None = Field(None, pattern=r"^(male|female|other)$")
    mobile: str | None = None
    email: str | None = None
    qualification_id: uuid.UUID | None = None
    speciality_id: uuid.UUID | None = None
    category_id: uuid.UUID | None = None
    doctor_type: str | None = Field(
        "private_practitioner", pattern=r"^(consultant|resident|private_practitioner)$"
    )
    hospital_id: uuid.UUID | None = None
    visit_frequency: int = Field(1, ge=1, le=30)
    dob: date | None = None
    anniversary: date | None = None
    division_id: uuid.UUID | None = None
    territory_id: uuid.UUID | None = None
    area_id: uuid.UUID | None = None
    status: str = Field("active", pattern=r"^(active|transferred|inactive)$")


class DoctorUpdate(BaseModel):
    name: str | None = Field(None, min_length=2, max_length=255)
    gender: str | None = Field(None, pattern=r"^(male|female|other)$")
    mobile: str | None = None
    email: str | None = None
    qualification_id: uuid.UUID | None = None
    speciality_id: uuid.UUID | None = None
    category_id: uuid.UUID | None = None
    doctor_type: str | None = Field(None, pattern=r"^(consultant|resident|private_practitioner)$")
    hospital_id: uuid.UUID | None = None
    visit_frequency: int | None = Field(None, ge=1, le=30)
    dob: date | None = None
    anniversary: date | None = None
    division_id: uuid.UUID | None = None
    territory_id: uuid.UUID | None = None
    area_id: uuid.UUID | None = None
    status: str | None = Field(None, pattern=r"^(active|transferred|inactive)$")


class DoctorResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    doctor_code: str
    name: str
    gender: str | None = None
    mobile: str | None = None
    email: str | None = None
    qualification_id: uuid.UUID | None = None
    speciality_id: uuid.UUID | None = None
    category_id: uuid.UUID | None = None
    doctor_type: str | None = None
    hospital_id: uuid.UUID | None = None
    visit_frequency: int
    dob: date | None = None
    anniversary: date | None = None
    division_id: uuid.UUID | None = None
    territory_id: uuid.UUID | None = None
    area_id: uuid.UUID | None = None
    status: str
    created_at: datetime
    updated_at: datetime


# -----------------------------------------------------------------------------
# Chemists
# -----------------------------------------------------------------------------
class ChemistCreate(BaseModel):
    chemist_code: str = Field(..., min_length=2, max_length=50)
    name: str = Field(..., min_length=2, max_length=255)
    contact_person: str | None = None
    mobile: str | None = None
    email: str | None = None
    chemist_type: str | None = Field(
        "independent", pattern=r"^(independent|chain_store|hospital_attached)$"
    )
    category_id: uuid.UUID | None = None
    territory_id: uuid.UUID | None = None
    division_id: uuid.UUID | None = None
    visit_frequency: int = Field(2, ge=1, le=30)
    dob: date | None = None
    anniversary: date | None = None
    gst_no: str | None = None
    dl_no: str | None = None
    status: str = Field("active", pattern=r"^(active|pending_verification|inactive)$")


class ChemistUpdate(BaseModel):
    name: str | None = Field(None, min_length=2, max_length=255)
    contact_person: str | None = None
    mobile: str | None = None
    email: str | None = None
    chemist_type: str | None = Field(None, pattern=r"^(independent|chain_store|hospital_attached)$")
    category_id: uuid.UUID | None = None
    territory_id: uuid.UUID | None = None
    division_id: uuid.UUID | None = None
    visit_frequency: int | None = Field(None, ge=1, le=30)
    dob: date | None = None
    anniversary: date | None = None
    gst_no: str | None = None
    dl_no: str | None = None
    status: str | None = Field(None, pattern=r"^(active|pending_verification|inactive)$")


class ChemistResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    chemist_code: str
    name: str
    contact_person: str | None = None
    mobile: str | None = None
    email: str | None = None
    chemist_type: str | None = None
    category_id: uuid.UUID | None = None
    territory_id: uuid.UUID | None = None
    division_id: uuid.UUID | None = None
    visit_frequency: int
    dob: date | None = None
    anniversary: date | None = None
    gst_no: str | None = None
    dl_no: str | None = None
    status: str
    created_at: datetime
    updated_at: datetime


# -----------------------------------------------------------------------------
# Products
# -----------------------------------------------------------------------------
class ProductCreate(BaseModel):
    product_code: str = Field(..., min_length=2, max_length=50)
    name: str = Field(..., min_length=2, max_length=255)
    generic_name: str | None = None
    description: str | None = None
    division_id: uuid.UUID | None = None
    category_id: uuid.UUID | None = None
    brand_id: uuid.UUID | None = None
    uom_id: uuid.UUID | None = None
    mrp: Decimal = Field(Decimal("0.00"), ge=0)
    ptr: Decimal = Field(Decimal("0.00"), ge=0)
    pts: Decimal = Field(Decimal("0.00"), ge=0)
    is_active: bool = True
    is_prescription_required: bool = True


class ProductUpdate(BaseModel):
    name: str | None = Field(None, min_length=2, max_length=255)
    generic_name: str | None = None
    description: str | None = None
    division_id: uuid.UUID | None = None
    category_id: uuid.UUID | None = None
    brand_id: uuid.UUID | None = None
    uom_id: uuid.UUID | None = None
    mrp: Decimal | None = Field(None, ge=0)
    ptr: Decimal | None = Field(None, ge=0)
    pts: Decimal | None = Field(None, ge=0)
    is_active: bool | None = None
    is_prescription_required: bool | None = None


class ProductResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    division_id: uuid.UUID | None = None
    category_id: uuid.UUID | None = None
    brand_id: uuid.UUID | None = None
    uom_id: uuid.UUID | None = None
    product_code: str
    name: str
    generic_name: str | None = None
    description: str | None = None
    mrp: Decimal
    ptr: Decimal
    pts: Decimal
    is_active: bool
    is_prescription_required: bool
    created_at: datetime
    updated_at: datetime
