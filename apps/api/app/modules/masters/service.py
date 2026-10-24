import uuid

from sqlalchemy import or_, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import Principal
from app.core.errors import ConflictError, ForbiddenError, NotFoundError
from app.core.pagination import PaginatedResponse, PaginationParams, paginate
from app.modules.masters.models import Chemist, Doctor, Product, Territory
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
    TerritoryCreate,
    TerritoryResponse,
    TerritoryUpdate,
)
from app.modules.users.models import AppUser


class MastersService:
    @staticmethod
    async def get_app_user(db: AsyncSession, principal: Principal) -> AppUser:
        result = await db.execute(
            select(AppUser).where(
                AppUser.auth_user_id == principal.user_id,
                AppUser.tenant_id == principal.tenant_id,
                AppUser.deleted_at.is_(None),
            )
        )
        user = result.scalar_one_or_none()
        if not user:
            raise NotFoundError("Active app user profile not found for the authenticated account")
        return user

    @staticmethod
    async def get_subordinate_user_ids(db: AsyncSession, app_user: AppUser) -> list[uuid.UUID]:
        if app_user.app_role == "admin":
            return []
        if app_user.app_role == "mr":
            return [app_user.id]

        # Recursive CTE to find self + all direct and indirect reportees
        query = text("""
            with recursive hierarchy as (
                select id from public.app_users
                where id = :user_id and tenant_id = :tenant_id and deleted_at is null
                union all
                select u.id from public.app_users u
                inner join hierarchy h on u.manager_id = h.id
                where u.tenant_id = :tenant_id and u.deleted_at is null
            )
            select id from hierarchy;
        """)
        result = await db.execute(query, {"user_id": app_user.id, "tenant_id": app_user.tenant_id})
        return [row[0] for row in result.fetchall()]

    @staticmethod
    async def get_accessible_territory_ids(
        db: AsyncSession, app_user: AppUser
    ) -> list[uuid.UUID] | None:
        """Returns None if user is admin (unrestricted), else list of territory UUIDs."""
        if app_user.app_role == "admin":
            return None

        subordinate_ids = await MastersService.get_subordinate_user_ids(db, app_user)
        if not subordinate_ids:
            return []

        result = await db.execute(
            select(Territory.id).where(
                Territory.tenant_id == app_user.tenant_id,
                Territory.deleted_at.is_(None),
                Territory.manager_id.in_(subordinate_ids),
            )
        )
        return [row[0] for row in result.fetchall()]

    # -------------------------------------------------------------------------
    # Territories
    # -------------------------------------------------------------------------
    @staticmethod
    async def list_territories(
        db: AsyncSession,
        principal: Principal,
        pagination: PaginationParams,
        area_id: uuid.UUID | None = None,
        search: str | None = None,
    ) -> PaginatedResponse[TerritoryResponse]:
        app_user = await MastersService.get_app_user(db, principal)
        accessible_territories = await MastersService.get_accessible_territory_ids(db, app_user)

        query = select(Territory).where(
            Territory.tenant_id == principal.tenant_id,
            Territory.deleted_at.is_(None),
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
            query = query.where(Territory.id.in_(accessible_territories))

        if area_id:
            query = query.where(Territory.area_id == area_id)

        if search:
            pattern = f"%{search.strip()}%"
            query = query.where(or_(Territory.name.ilike(pattern), Territory.code.ilike(pattern)))

        items, total, total_pages = await paginate(
            db, query.order_by(Territory.code.asc()), pagination
        )
        return PaginatedResponse(
            items=[TerritoryResponse.model_validate(t) for t in items],
            total=total,
            page=pagination.page,
            page_size=pagination.page_size,
            total_pages=total_pages,
        )

    @staticmethod
    async def get_territory(
        db: AsyncSession, principal: Principal, territory_id: uuid.UUID
    ) -> TerritoryResponse:
        app_user = await MastersService.get_app_user(db, principal)
        result = await db.execute(
            select(Territory).where(
                Territory.id == territory_id,
                Territory.tenant_id == principal.tenant_id,
                Territory.deleted_at.is_(None),
            )
        )
        territory = result.scalar_one_or_none()
        if not territory:
            raise NotFoundError("Territory not found")

        accessible = await MastersService.get_accessible_territory_ids(db, app_user)
        if accessible is not None and territory.id not in accessible:
            raise ForbiddenError("You do not have access to this territory")

        return TerritoryResponse.model_validate(territory)

    @staticmethod
    async def create_territory(
        db: AsyncSession, principal: Principal, data: TerritoryCreate
    ) -> TerritoryResponse:
        code_exists = await db.execute(
            select(Territory.id).where(
                Territory.tenant_id == principal.tenant_id,
                Territory.code == data.code,
                Territory.deleted_at.is_(None),
            )
        )
        if code_exists.scalar_one_or_none():
            raise ConflictError(f"Territory with code '{data.code}' already exists")

        if data.manager_id:
            user_res = await db.execute(
                select(AppUser.id).where(
                    AppUser.id == data.manager_id,
                    AppUser.tenant_id == principal.tenant_id,
                    AppUser.deleted_at.is_(None),
                )
            )
            if not user_res.scalar_one_or_none():
                raise NotFoundError("Assigned user not found in this tenant")

        territory = Territory(
            tenant_id=principal.tenant_id,
            area_id=data.area_id,
            code=data.code,
            name=data.name,
            manager_id=data.manager_id,
        )
        db.add(territory)
        await db.flush()
        await db.refresh(territory)
        return TerritoryResponse.model_validate(territory)

    @staticmethod
    async def update_territory(
        db: AsyncSession, principal: Principal, territory_id: uuid.UUID, data: TerritoryUpdate
    ) -> TerritoryResponse:
        result = await db.execute(
            select(Territory).where(
                Territory.id == territory_id,
                Territory.tenant_id == principal.tenant_id,
                Territory.deleted_at.is_(None),
            )
        )
        territory = result.scalar_one_or_none()
        if not territory:
            raise NotFoundError("Territory not found")

        if data.manager_id is not None:
            user_res = await db.execute(
                select(AppUser.id).where(
                    AppUser.id == data.manager_id,
                    AppUser.tenant_id == principal.tenant_id,
                    AppUser.deleted_at.is_(None),
                )
            )
            if not user_res.scalar_one_or_none():
                raise NotFoundError("Assigned user not found in this tenant")
            territory.manager_id = data.manager_id

        if data.name is not None:
            territory.name = data.name
        if data.area_id is not None:
            territory.area_id = data.area_id

        await db.flush()
        await db.refresh(territory)
        return TerritoryResponse.model_validate(territory)

    @staticmethod
    async def assign_mr_to_territory(
        db: AsyncSession, principal: Principal, territory_id: uuid.UUID, mr_id: uuid.UUID
    ) -> TerritoryResponse:
        app_user = await MastersService.get_app_user(db, principal)
        result = await db.execute(
            select(Territory).where(
                Territory.id == territory_id,
                Territory.tenant_id == principal.tenant_id,
                Territory.deleted_at.is_(None),
            )
        )
        territory = result.scalar_one_or_none()
        if not territory:
            raise NotFoundError("Territory not found")

        # Verify target MR
        target_user = await db.execute(
            select(AppUser).where(
                AppUser.id == mr_id,
                AppUser.tenant_id == principal.tenant_id,
                AppUser.deleted_at.is_(None),
            )
        )
        mr = target_user.scalar_one_or_none()
        if not mr:
            raise NotFoundError("User not found in tenant")

        if app_user.app_role == "manager":
            subordinates = await MastersService.get_subordinate_user_ids(db, app_user)
            if mr.id not in subordinates:
                raise ForbiddenError("Manager can only assign territories to self or subordinates")

        territory.manager_id = mr.id
        await db.flush()
        await db.refresh(territory)
        return TerritoryResponse.model_validate(territory)

    # -------------------------------------------------------------------------
    # Doctors
    # -------------------------------------------------------------------------
    @staticmethod
    async def list_doctors(
        db: AsyncSession,
        principal: Principal,
        pagination: PaginationParams,
        territory_id: uuid.UUID | None = None,
        speciality_id: uuid.UUID | None = None,
        category_id: uuid.UUID | None = None,
        status: str | None = None,
        search: str | None = None,
    ) -> PaginatedResponse[DoctorResponse]:
        app_user = await MastersService.get_app_user(db, principal)
        accessible = await MastersService.get_accessible_territory_ids(db, app_user)

        query = select(Doctor).where(
            Doctor.tenant_id == principal.tenant_id,
            Doctor.deleted_at.is_(None),
        )

        if accessible is not None:
            if not accessible:
                return PaginatedResponse(
                    items=[],
                    total=0,
                    page=pagination.page,
                    page_size=pagination.page_size,
                    total_pages=0,
                )
            query = query.where(Doctor.territory_id.in_(accessible))

        if territory_id:
            if accessible is not None and territory_id not in accessible:
                raise ForbiddenError("You do not have access to this territory")
            query = query.where(Doctor.territory_id == territory_id)

        if speciality_id:
            query = query.where(Doctor.speciality_id == speciality_id)
        if category_id:
            query = query.where(Doctor.category_id == category_id)
        if status:
            query = query.where(Doctor.status == status)

        if search:
            pattern = f"%{search.strip()}%"
            query = query.where(or_(Doctor.name.ilike(pattern), Doctor.doctor_code.ilike(pattern)))

        items, total, total_pages = await paginate(
            db, query.order_by(Doctor.name.asc()), pagination
        )
        return PaginatedResponse(
            items=[DoctorResponse.model_validate(d) for d in items],
            total=total,
            page=pagination.page,
            page_size=pagination.page_size,
            total_pages=total_pages,
        )

    @staticmethod
    async def get_doctor(
        db: AsyncSession, principal: Principal, doctor_id: uuid.UUID
    ) -> DoctorResponse:
        app_user = await MastersService.get_app_user(db, principal)
        result = await db.execute(
            select(Doctor).where(
                Doctor.id == doctor_id,
                Doctor.tenant_id == principal.tenant_id,
                Doctor.deleted_at.is_(None),
            )
        )
        doctor = result.scalar_one_or_none()
        if not doctor:
            raise NotFoundError("Doctor not found")

        accessible = await MastersService.get_accessible_territory_ids(db, app_user)
        if accessible is not None and (
            not doctor.territory_id or doctor.territory_id not in accessible
        ):
            raise ForbiddenError("You do not have access to this doctor")

        return DoctorResponse.model_validate(doctor)

    @staticmethod
    async def create_doctor(
        db: AsyncSession, principal: Principal, data: DoctorCreate
    ) -> DoctorResponse:
        app_user = await MastersService.get_app_user(db, principal)
        accessible = await MastersService.get_accessible_territory_ids(db, app_user)
        if accessible is not None and (
            not data.territory_id or data.territory_id not in accessible
        ):
            raise ForbiddenError("Cannot create doctor outside of assigned territories")

        code_exists = await db.execute(
            select(Doctor.id).where(
                Doctor.tenant_id == principal.tenant_id,
                Doctor.doctor_code == data.doctor_code,
                Doctor.deleted_at.is_(None),
            )
        )
        if code_exists.scalar_one_or_none():
            raise ConflictError(f"Doctor with code '{data.doctor_code}' already exists")

        doctor = Doctor(
            tenant_id=principal.tenant_id,
            doctor_code=data.doctor_code,
            name=data.name,
            gender=data.gender,
            mobile=data.mobile,
            email=data.email,
            qualification_id=data.qualification_id,
            speciality_id=data.speciality_id,
            category_id=data.category_id,
            doctor_type=data.doctor_type,
            hospital_id=data.hospital_id,
            visit_frequency=data.visit_frequency,
            dob=data.dob,
            anniversary=data.anniversary,
            division_id=data.division_id,
            territory_id=data.territory_id,
            area_id=data.area_id,
            status=data.status,
        )
        db.add(doctor)
        await db.flush()
        await db.refresh(doctor)
        return DoctorResponse.model_validate(doctor)

    @staticmethod
    async def update_doctor(
        db: AsyncSession, principal: Principal, doctor_id: uuid.UUID, data: DoctorUpdate
    ) -> DoctorResponse:
        app_user = await MastersService.get_app_user(db, principal)
        result = await db.execute(
            select(Doctor).where(
                Doctor.id == doctor_id,
                Doctor.tenant_id == principal.tenant_id,
                Doctor.deleted_at.is_(None),
            )
        )
        doctor = result.scalar_one_or_none()
        if not doctor:
            raise NotFoundError("Doctor not found")

        accessible = await MastersService.get_accessible_territory_ids(db, app_user)
        if accessible is not None:
            if not doctor.territory_id or doctor.territory_id not in accessible:
                raise ForbiddenError("You do not have access to update this doctor")
            if data.territory_id is not None and data.territory_id not in accessible:
                raise ForbiddenError("Cannot reassign doctor outside assigned territories")

        update_dict = data.model_dump(exclude_unset=True)
        for field, value in update_dict.items():
            setattr(doctor, field, value)

        await db.flush()
        await db.refresh(doctor)
        return DoctorResponse.model_validate(doctor)

    # -------------------------------------------------------------------------
    # Chemists
    # -------------------------------------------------------------------------
    @staticmethod
    async def list_chemists(
        db: AsyncSession,
        principal: Principal,
        pagination: PaginationParams,
        territory_id: uuid.UUID | None = None,
        category_id: uuid.UUID | None = None,
        status: str | None = None,
        search: str | None = None,
    ) -> PaginatedResponse[ChemistResponse]:
        app_user = await MastersService.get_app_user(db, principal)
        accessible = await MastersService.get_accessible_territory_ids(db, app_user)

        query = select(Chemist).where(
            Chemist.tenant_id == principal.tenant_id,
            Chemist.deleted_at.is_(None),
        )

        if accessible is not None:
            if not accessible:
                return PaginatedResponse(
                    items=[],
                    total=0,
                    page=pagination.page,
                    page_size=pagination.page_size,
                    total_pages=0,
                )
            query = query.where(Chemist.territory_id.in_(accessible))

        if territory_id:
            if accessible is not None and territory_id not in accessible:
                raise ForbiddenError("You do not have access to this territory")
            query = query.where(Chemist.territory_id == territory_id)

        if category_id:
            query = query.where(Chemist.category_id == category_id)
        if status:
            query = query.where(Chemist.status == status)

        if search:
            pattern = f"%{search.strip()}%"
            query = query.where(
                or_(Chemist.name.ilike(pattern), Chemist.chemist_code.ilike(pattern))
            )

        items, total, total_pages = await paginate(
            db, query.order_by(Chemist.name.asc()), pagination
        )
        return PaginatedResponse(
            items=[ChemistResponse.model_validate(c) for c in items],
            total=total,
            page=pagination.page,
            page_size=pagination.page_size,
            total_pages=total_pages,
        )

    @staticmethod
    async def get_chemist(
        db: AsyncSession, principal: Principal, chemist_id: uuid.UUID
    ) -> ChemistResponse:
        app_user = await MastersService.get_app_user(db, principal)
        result = await db.execute(
            select(Chemist).where(
                Chemist.id == chemist_id,
                Chemist.tenant_id == principal.tenant_id,
                Chemist.deleted_at.is_(None),
            )
        )
        chemist = result.scalar_one_or_none()
        if not chemist:
            raise NotFoundError("Chemist not found")

        accessible = await MastersService.get_accessible_territory_ids(db, app_user)
        if accessible is not None and (
            not chemist.territory_id or chemist.territory_id not in accessible
        ):
            raise ForbiddenError("You do not have access to this chemist")

        return ChemistResponse.model_validate(chemist)

    @staticmethod
    async def create_chemist(
        db: AsyncSession, principal: Principal, data: ChemistCreate
    ) -> ChemistResponse:
        app_user = await MastersService.get_app_user(db, principal)
        accessible = await MastersService.get_accessible_territory_ids(db, app_user)
        if accessible is not None and (
            not data.territory_id or data.territory_id not in accessible
        ):
            raise ForbiddenError("Cannot create chemist outside of assigned territories")

        code_exists = await db.execute(
            select(Chemist.id).where(
                Chemist.tenant_id == principal.tenant_id,
                Chemist.chemist_code == data.chemist_code,
                Chemist.deleted_at.is_(None),
            )
        )
        if code_exists.scalar_one_or_none():
            raise ConflictError(f"Chemist with code '{data.chemist_code}' already exists")

        chemist = Chemist(
            tenant_id=principal.tenant_id,
            chemist_code=data.chemist_code,
            name=data.name,
            contact_person=data.contact_person,
            mobile=data.mobile,
            email=data.email,
            chemist_type=data.chemist_type,
            category_id=data.category_id,
            territory_id=data.territory_id,
            division_id=data.division_id,
            visit_frequency=data.visit_frequency,
            dob=data.dob,
            anniversary=data.anniversary,
            gst_no=data.gst_no,
            dl_no=data.dl_no,
            status=data.status,
        )
        db.add(chemist)
        await db.flush()
        await db.refresh(chemist)
        return ChemistResponse.model_validate(chemist)

    @staticmethod
    async def update_chemist(
        db: AsyncSession, principal: Principal, chemist_id: uuid.UUID, data: ChemistUpdate
    ) -> ChemistResponse:
        app_user = await MastersService.get_app_user(db, principal)
        result = await db.execute(
            select(Chemist).where(
                Chemist.id == chemist_id,
                Chemist.tenant_id == principal.tenant_id,
                Chemist.deleted_at.is_(None),
            )
        )
        chemist = result.scalar_one_or_none()
        if not chemist:
            raise NotFoundError("Chemist not found")

        accessible = await MastersService.get_accessible_territory_ids(db, app_user)
        if accessible is not None:
            if not chemist.territory_id or chemist.territory_id not in accessible:
                raise ForbiddenError("You do not have access to update this chemist")
            if data.territory_id is not None and data.territory_id not in accessible:
                raise ForbiddenError("Cannot reassign chemist outside assigned territories")

        update_dict = data.model_dump(exclude_unset=True)
        for field, value in update_dict.items():
            setattr(chemist, field, value)

        await db.flush()
        await db.refresh(chemist)
        return ChemistResponse.model_validate(chemist)

    # -------------------------------------------------------------------------
    # Products
    # -------------------------------------------------------------------------
    @staticmethod
    async def list_products(
        db: AsyncSession,
        principal: Principal,
        pagination: PaginationParams,
        category_id: uuid.UUID | None = None,
        brand_id: uuid.UUID | None = None,
        is_active: bool | None = None,
        search: str | None = None,
    ) -> PaginatedResponse[ProductResponse]:
        query = select(Product).where(
            Product.tenant_id == principal.tenant_id,
            Product.deleted_at.is_(None),
        )

        if category_id:
            query = query.where(Product.category_id == category_id)
        if brand_id:
            query = query.where(Product.brand_id == brand_id)
        if is_active is not None:
            query = query.where(Product.is_active == is_active)

        if search:
            pattern = f"%{search.strip()}%"
            query = query.where(
                or_(
                    Product.name.ilike(pattern),
                    Product.product_code.ilike(pattern),
                    Product.generic_name.ilike(pattern),
                )
            )

        items, total, total_pages = await paginate(
            db, query.order_by(Product.name.asc()), pagination
        )
        return PaginatedResponse(
            items=[ProductResponse.model_validate(p) for p in items],
            total=total,
            page=pagination.page,
            page_size=pagination.page_size,
            total_pages=total_pages,
        )

    @staticmethod
    async def get_product(
        db: AsyncSession, principal: Principal, product_id: uuid.UUID
    ) -> ProductResponse:
        result = await db.execute(
            select(Product).where(
                Product.id == product_id,
                Product.tenant_id == principal.tenant_id,
                Product.deleted_at.is_(None),
            )
        )
        product = result.scalar_one_or_none()
        if not product:
            raise NotFoundError("Product not found")
        return ProductResponse.model_validate(product)

    @staticmethod
    async def create_product(
        db: AsyncSession, principal: Principal, data: ProductCreate
    ) -> ProductResponse:
        code_exists = await db.execute(
            select(Product.id).where(
                Product.tenant_id == principal.tenant_id,
                Product.product_code == data.product_code,
                Product.deleted_at.is_(None),
            )
        )
        if code_exists.scalar_one_or_none():
            raise ConflictError(f"Product with code '{data.product_code}' already exists")

        product = Product(
            tenant_id=principal.tenant_id,
            division_id=data.division_id,
            category_id=data.category_id,
            brand_id=data.brand_id,
            uom_id=data.uom_id,
            product_code=data.product_code,
            name=data.name,
            generic_name=data.generic_name,
            description=data.description,
            mrp=data.mrp,
            ptr=data.ptr,
            pts=data.pts,
            is_active=data.is_active,
            is_prescription_required=data.is_prescription_required,
        )
        db.add(product)
        await db.flush()
        await db.refresh(product)
        return ProductResponse.model_validate(product)

    @staticmethod
    async def update_product(
        db: AsyncSession, principal: Principal, product_id: uuid.UUID, data: ProductUpdate
    ) -> ProductResponse:
        result = await db.execute(
            select(Product).where(
                Product.id == product_id,
                Product.tenant_id == principal.tenant_id,
                Product.deleted_at.is_(None),
            )
        )
        product = result.scalar_one_or_none()
        if not product:
            raise NotFoundError("Product not found")

        update_dict = data.model_dump(exclude_unset=True)
        for field, value in update_dict.items():
            setattr(product, field, value)

        await db.flush()
        await db.refresh(product)
        return ProductResponse.model_validate(product)
