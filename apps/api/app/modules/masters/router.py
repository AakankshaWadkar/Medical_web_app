import uuid

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import Principal, require_roles
from app.core.db import tenant_session
from app.core.pagination import PaginatedResponse, PaginationParams
from app.modules.masters.schemas import (
    ChemistCreate,
    ChemistResponse,
    ChemistUpdate,
    DoctorCreate,
    DoctorResponse,
    DoctorUpdate,
    ProductCreate,
    ProductResponse,
    ProductUpdate,
    TerritoryAssignMR,
    TerritoryCreate,
    TerritoryResponse,
    TerritoryUpdate,
)
from app.modules.masters.service import MastersService

router = APIRouter(prefix="/v1", tags=["Masters"])


# -----------------------------------------------------------------------------
# Territories
# -----------------------------------------------------------------------------
@router.get(
    "/territories",
    response_model=PaginatedResponse[TerritoryResponse],
    summary="List sales territories",
)
async def list_territories(
    area_id: uuid.UUID | None = Query(None, description="Filter by area ID"),
    search: str | None = Query(None, description="Search by name or code"),
    pagination: PaginationParams = Depends(),
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> PaginatedResponse[TerritoryResponse]:
    return await MastersService.list_territories(
        db=db,
        principal=principal,
        pagination=pagination,
        area_id=area_id,
        search=search,
    )


@router.get(
    "/territories/{id}",
    response_model=TerritoryResponse,
    summary="Get sales territory by ID",
)
async def get_territory(
    id: uuid.UUID,
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> TerritoryResponse:
    return await MastersService.get_territory(db=db, principal=principal, territory_id=id)


@router.post(
    "/territories",
    response_model=TerritoryResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create sales territory",
)
async def create_territory(
    payload: TerritoryCreate,
    principal: Principal = Depends(require_roles("admin")),
    db: AsyncSession = Depends(tenant_session),
) -> TerritoryResponse:
    return await MastersService.create_territory(db=db, principal=principal, data=payload)


@router.patch(
    "/territories/{id}",
    response_model=TerritoryResponse,
    summary="Update sales territory",
)
async def update_territory(
    id: uuid.UUID,
    payload: TerritoryUpdate,
    principal: Principal = Depends(require_roles("admin")),
    db: AsyncSession = Depends(tenant_session),
) -> TerritoryResponse:
    return await MastersService.update_territory(
        db=db, principal=principal, territory_id=id, data=payload
    )


@router.post(
    "/territories/{id}/assign-mr",
    response_model=TerritoryResponse,
    summary="Assign MR or manager to sales territory",
)
async def assign_mr(
    id: uuid.UUID,
    payload: TerritoryAssignMR,
    principal: Principal = Depends(require_roles("admin", "manager")),
    db: AsyncSession = Depends(tenant_session),
) -> TerritoryResponse:
    return await MastersService.assign_mr_to_territory(
        db=db, principal=principal, territory_id=id, mr_id=payload.mr_id
    )


# -----------------------------------------------------------------------------
# Doctors
# -----------------------------------------------------------------------------
@router.get(
    "/doctors",
    response_model=PaginatedResponse[DoctorResponse],
    summary="List doctors master",
)
async def list_doctors(
    territory_id: uuid.UUID | None = Query(None, description="Filter by territory ID"),
    speciality_id: uuid.UUID | None = Query(None, description="Filter by speciality ID"),
    category_id: uuid.UUID | None = Query(None, description="Filter by category ID"),
    status_filter: str | None = Query(None, alias="status", description="Filter by status"),
    search: str | None = Query(None, description="Search by name or doctor_code"),
    pagination: PaginationParams = Depends(),
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> PaginatedResponse[DoctorResponse]:
    return await MastersService.list_doctors(
        db=db,
        principal=principal,
        pagination=pagination,
        territory_id=territory_id,
        speciality_id=speciality_id,
        category_id=category_id,
        status=status_filter,
        search=search,
    )


@router.get(
    "/doctors/{id}",
    response_model=DoctorResponse,
    summary="Get doctor by ID",
)
async def get_doctor(
    id: uuid.UUID,
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> DoctorResponse:
    return await MastersService.get_doctor(db=db, principal=principal, doctor_id=id)


@router.post(
    "/doctors",
    response_model=DoctorResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create doctor master record",
)
async def create_doctor(
    payload: DoctorCreate,
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> DoctorResponse:
    return await MastersService.create_doctor(db=db, principal=principal, data=payload)


@router.patch(
    "/doctors/{id}",
    response_model=DoctorResponse,
    summary="Update doctor master record",
)
async def update_doctor(
    id: uuid.UUID,
    payload: DoctorUpdate,
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> DoctorResponse:
    return await MastersService.update_doctor(
        db=db, principal=principal, doctor_id=id, data=payload
    )


# -----------------------------------------------------------------------------
# Chemists
# -----------------------------------------------------------------------------
@router.get(
    "/chemists",
    response_model=PaginatedResponse[ChemistResponse],
    summary="List chemists master",
)
async def list_chemists(
    territory_id: uuid.UUID | None = Query(None, description="Filter by territory ID"),
    category_id: uuid.UUID | None = Query(None, description="Filter by category ID"),
    status_filter: str | None = Query(None, alias="status", description="Filter by status"),
    search: str | None = Query(None, description="Search by name or chemist_code"),
    pagination: PaginationParams = Depends(),
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> PaginatedResponse[ChemistResponse]:
    return await MastersService.list_chemists(
        db=db,
        principal=principal,
        pagination=pagination,
        territory_id=territory_id,
        category_id=category_id,
        status=status_filter,
        search=search,
    )


@router.get(
    "/chemists/{id}",
    response_model=ChemistResponse,
    summary="Get chemist by ID",
)
async def get_chemist(
    id: uuid.UUID,
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> ChemistResponse:
    return await MastersService.get_chemist(db=db, principal=principal, chemist_id=id)


@router.post(
    "/chemists",
    response_model=ChemistResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create chemist master record",
)
async def create_chemist(
    payload: ChemistCreate,
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> ChemistResponse:
    return await MastersService.create_chemist(db=db, principal=principal, data=payload)


@router.patch(
    "/chemists/{id}",
    response_model=ChemistResponse,
    summary="Update chemist master record",
)
async def update_chemist(
    id: uuid.UUID,
    payload: ChemistUpdate,
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> ChemistResponse:
    return await MastersService.update_chemist(
        db=db, principal=principal, chemist_id=id, data=payload
    )


# -----------------------------------------------------------------------------
# Products
# -----------------------------------------------------------------------------
@router.get(
    "/products",
    response_model=PaginatedResponse[ProductResponse],
    summary="List finished products master",
)
async def list_products(
    category_id: uuid.UUID | None = Query(None, description="Filter by category ID"),
    brand_id: uuid.UUID | None = Query(None, description="Filter by brand ID"),
    is_active: bool | None = Query(None, description="Filter by active status"),
    search: str | None = Query(None, description="Search by name, code or generic name"),
    pagination: PaginationParams = Depends(),
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> PaginatedResponse[ProductResponse]:
    return await MastersService.list_products(
        db=db,
        principal=principal,
        pagination=pagination,
        category_id=category_id,
        brand_id=brand_id,
        is_active=is_active,
        search=search,
    )


@router.get(
    "/products/{id}",
    response_model=ProductResponse,
    summary="Get product by ID",
)
async def get_product(
    id: uuid.UUID,
    principal: Principal = Depends(require_roles("admin", "manager", "mr")),
    db: AsyncSession = Depends(tenant_session),
) -> ProductResponse:
    return await MastersService.get_product(db=db, principal=principal, product_id=id)


@router.post(
    "/products",
    response_model=ProductResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create product master record",
)
async def create_product(
    payload: ProductCreate,
    principal: Principal = Depends(require_roles("admin")),
    db: AsyncSession = Depends(tenant_session),
) -> ProductResponse:
    return await MastersService.create_product(db=db, principal=principal, data=payload)


@router.patch(
    "/products/{id}",
    response_model=ProductResponse,
    summary="Update product master record",
)
async def update_product(
    id: uuid.UUID,
    payload: ProductUpdate,
    principal: Principal = Depends(require_roles("admin")),
    db: AsyncSession = Depends(tenant_session),
) -> ProductResponse:
    return await MastersService.update_product(
        db=db, principal=principal, product_id=id, data=payload
    )
