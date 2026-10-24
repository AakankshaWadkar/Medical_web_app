import json
import uuid
from datetime import datetime
from uuid import UUID

from sqlalchemy import func, or_, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import Principal
from app.core.errors import BadRequestError, ConflictError, NotFoundError
from app.core.pagination import PaginationParams, paginate
from app.core.supabase_admin import ban_auth_user, create_auth_user
from app.modules.users.models import AppUser
from app.modules.users.schemas import UserCreate, UserUpdate


class UserService:
    @staticmethod
    async def list_users(
        db: AsyncSession,
        params: PaginationParams,
        role: str | None = None,
        status: str | None = None,
        search: str | None = None,
    ) -> tuple[list[AppUser], int, int]:
        stmt = select(AppUser).where(AppUser.deleted_at.is_(None))

        if role:
            stmt = stmt.where(AppUser.app_role == role)
        if status:
            stmt = stmt.where(AppUser.status == status)
        if search:
            term = f"%{search.strip()}%"
            stmt = stmt.where(or_(AppUser.full_name.ilike(term), AppUser.employee_code.ilike(term)))

        stmt = stmt.order_by(AppUser.created_at.desc(), AppUser.id.desc())
        items, total, total_pages = await paginate(db, stmt, params)
        return list(items), total, total_pages

    @staticmethod
    async def get_user(db: AsyncSession, user_id: UUID) -> AppUser:
        stmt = select(AppUser).where(AppUser.id == user_id, AppUser.deleted_at.is_(None))
        result = await db.execute(stmt)
        user = result.scalar_one_or_none()
        if not user:
            raise NotFoundError(f"User {user_id} not found")
        return user

    @staticmethod
    async def create_user(
        db: AsyncSession,
        principal: Principal,
        data: UserCreate,
        ip_address: str | None = None,
        user_agent: str | None = None,
    ) -> AppUser:
        # 1. Validate manager if given
        if data.manager_id:
            manager_stmt = select(AppUser.id).where(
                AppUser.id == data.manager_id, AppUser.deleted_at.is_(None)
            )
            manager_res = await db.execute(manager_stmt)
            if not manager_res.scalar_one_or_none():
                raise BadRequestError(f"Manager {data.manager_id} not found")

        # 2. Validate branch if given
        if data.branch_id:
            branch_res = await db.execute(
                text("select id from public.branches where id = :bid and deleted_at is null"),
                {"bid": data.branch_id},
            )
            if not branch_res.scalar_one_or_none():
                raise BadRequestError(f"Branch {data.branch_id} not found")

        # 3. Check employee_code collision in tenant if provided
        if data.employee_code:
            emp_check = await db.execute(
                select(AppUser.id).where(
                    AppUser.employee_code == data.employee_code, AppUser.deleted_at.is_(None)
                )
            )
            if emp_check.scalar_one_or_none():
                raise ConflictError(f"Employee code '{data.employee_code}' already in use")

        # 4. Create user in Supabase Auth via Admin API
        auth_user_id = await create_auth_user(data.email, data.password, data.full_name)
        app_user_id = uuid.uuid4()

        # 5. Insert public.app_users
        user = AppUser(
            id=app_user_id,
            tenant_id=principal.tenant_id,
            auth_user_id=auth_user_id,
            app_role=data.app_role,
            full_name=data.full_name,
            manager_id=data.manager_id,
            employee_code=data.employee_code,
            phone=data.phone,
            branch_id=data.branch_id,
            status="active",
        )
        db.add(user)
        await db.flush()
        await db.refresh(user)

        # 6. Insert audit_logs
        await db.execute(
            text("""
                insert into public.audit_logs (
                    id, tenant_id, user_id, entity_name, entity_id, action, new_values, ip_address, user_agent, created_at, updated_at, version
                )
                values (
                    gen_random_uuid(), :tenant_id, :admin_id, 'app_users', :entity_id, 'insert',
                    cast(:new_values as jsonb), :ip, :ua, now(), now(), 1
                )
            """),
            {
                "tenant_id": principal.tenant_id,
                "admin_id": user.id,
                "entity_id": app_user_id,
                "new_values": json.dumps(
                    {
                        "app_role": data.app_role,
                        "full_name": data.full_name,
                        "email": data.email,
                        "employee_code": data.employee_code,
                        "manager_id": str(data.manager_id) if data.manager_id else None,
                    }
                ),
                "ip": ip_address,
                "ua": user_agent,
            },
        )

        return user

    @staticmethod
    async def update_user(
        db: AsyncSession,
        principal: Principal,
        user_id: UUID,
        data: UserUpdate,
        ip_address: str | None = None,
        user_agent: str | None = None,
    ) -> AppUser:
        user = await UserService.get_user(db, user_id)

        old_values = {
            "app_role": user.app_role,
            "full_name": user.full_name,
            "phone": user.phone,
            "employee_code": user.employee_code,
            "manager_id": str(user.manager_id) if user.manager_id else None,
            "branch_id": str(user.branch_id) if user.branch_id else None,
            "status": user.status,
        }

        # Check self-management
        if data.manager_id:
            if data.manager_id == user_id:
                raise BadRequestError("A user cannot be their own manager")
            manager_stmt = select(AppUser.id).where(
                AppUser.id == data.manager_id, AppUser.deleted_at.is_(None)
            )
            manager_res = await db.execute(manager_stmt)
            if not manager_res.scalar_one_or_none():
                raise BadRequestError(f"Manager {data.manager_id} not found")

        # Check branch
        if data.branch_id:
            branch_res = await db.execute(
                text("select id from public.branches where id = :bid and deleted_at is null"),
                {"bid": data.branch_id},
            )
            if not branch_res.scalar_one_or_none():
                raise BadRequestError(f"Branch {data.branch_id} not found")

        # Check employee_code collision
        if data.employee_code and data.employee_code != user.employee_code:
            emp_check = await db.execute(
                select(AppUser.id).where(
                    AppUser.employee_code == data.employee_code,
                    AppUser.id != user_id,
                    AppUser.deleted_at.is_(None),
                )
            )
            if emp_check.scalar_one_or_none():
                raise ConflictError(f"Employee code '{data.employee_code}' already in use")

        # Apply updates
        if data.full_name is not None:
            user.full_name = data.full_name
        if data.phone is not None:
            user.phone = data.phone
        if data.employee_code is not None:
            user.employee_code = data.employee_code
        if data.manager_id is not None:
            user.manager_id = data.manager_id
        if data.branch_id is not None:
            user.branch_id = data.branch_id
        if data.app_role is not None:
            user.app_role = data.app_role
        if data.status is not None:
            user.status = data.status

        user.updated_at = datetime.now()
        await db.flush()
        await db.refresh(user)

        new_values = {
            "app_role": user.app_role,
            "full_name": user.full_name,
            "phone": user.phone,
            "employee_code": user.employee_code,
            "manager_id": str(user.manager_id) if user.manager_id else None,
            "branch_id": str(user.branch_id) if user.branch_id else None,
            "status": user.status,
        }

        # Audit log
        await db.execute(
            text("""
                insert into public.audit_logs (
                    id, tenant_id, user_id, entity_name, entity_id, action, old_values, new_values, ip_address, user_agent, created_at, updated_at, version
                )
                values (
                    gen_random_uuid(), :tenant_id, :admin_id, 'app_users', :entity_id, 'update',
                    cast(:old_values as jsonb), cast(:new_values as jsonb), :ip, :ua, now(), now(), 1
                )
            """),
            {
                "tenant_id": principal.tenant_id,
                "admin_id": user.id,
                "entity_id": user.id,
                "old_values": json.dumps(old_values),
                "new_values": json.dumps(new_values),
                "ip": ip_address,
                "ua": user_agent,
            },
        )

        return user

    @staticmethod
    async def deactivate_user(
        db: AsyncSession,
        principal: Principal,
        user_id: UUID,
        ip_address: str | None = None,
        user_agent: str | None = None,
    ) -> AppUser:
        user = await UserService.get_user(db, user_id)

        user.status = "suspended"
        user.deleted_at = func.now()
        await db.flush()
        await db.refresh(user)

        # Disable in Supabase Auth via Admin API
        await ban_auth_user(user.auth_user_id)

        # Audit log
        await db.execute(
            text("""
                insert into public.audit_logs (
                    id, tenant_id, user_id, entity_name, entity_id, action, old_values, new_values, ip_address, user_agent, created_at, updated_at, version
                )
                values (
                    gen_random_uuid(), :tenant_id, :admin_id, 'app_users', :entity_id, 'delete',
                    cast(:old_values as jsonb), cast('{"status":"suspended"}' as jsonb), :ip, :ua, now(), now(), 1
                )
            """),
            {
                "tenant_id": principal.tenant_id,
                "admin_id": user.id,
                "entity_id": user.id,
                "old_values": json.dumps({"status": "active", "id": str(user.id)}),
                "ip": ip_address,
                "ua": user_agent,
            },
        )

        return user
