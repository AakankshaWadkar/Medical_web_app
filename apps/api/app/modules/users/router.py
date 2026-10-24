from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import Principal, require_roles
from app.core.db import tenant_session
from app.core.pagination import PaginatedResponse, PaginationParams
from app.modules.users.schemas import UserCreate, UserResponse, UserRole, UserStatus, UserUpdate
from app.modules.users.service import UserService

router = APIRouter(prefix="/v1/users", tags=["Users"])


@router.post(
    "",
    response_model=UserResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new tenant user (Admin only)",
)
async def create_user(
    data: UserCreate,
    request: Request,
    principal: Principal = Depends(require_roles("admin")),
    db: AsyncSession = Depends(tenant_session),
) -> UserResponse:
    ip = request.client.host if request.client else None
    ua = request.headers.get("User-Agent")
    user = await UserService.create_user(db, principal, data, ip_address=ip, user_agent=ua)
    return UserResponse.model_validate(user)


@router.get(
    "",
    response_model=PaginatedResponse[UserResponse],
    summary="List tenant users with filters (Admin only)",
)
async def list_users(
    params: PaginationParams = Depends(),
    role: UserRole | None = Query(default=None, description="Filter by user role"),
    user_status: UserStatus | None = Query(
        default=None, alias="status", description="Filter by status"
    ),
    search: str | None = Query(default=None, description="Search by name or employee code"),
    principal: Principal = Depends(require_roles("admin")),
    db: AsyncSession = Depends(tenant_session),
) -> PaginatedResponse[UserResponse]:
    items, total, total_pages = await UserService.list_users(
        db, params, role=role, status=user_status, search=search
    )
    return PaginatedResponse[UserResponse](
        items=[UserResponse.model_validate(u) for u in items],
        total=total,
        page=params.page,
        page_size=params.page_size,
        total_pages=total_pages,
    )


@router.get(
    "/{user_id}",
    response_model=UserResponse,
    summary="Get user details by ID (Admin only)",
)
async def get_user(
    user_id: UUID,
    principal: Principal = Depends(require_roles("admin")),
    db: AsyncSession = Depends(tenant_session),
) -> UserResponse:
    user = await UserService.get_user(db, user_id)
    return UserResponse.model_validate(user)


@router.patch(
    "/{user_id}",
    response_model=UserResponse,
    summary="Update user details (Admin only)",
)
async def update_user(
    user_id: UUID,
    data: UserUpdate,
    request: Request,
    principal: Principal = Depends(require_roles("admin")),
    db: AsyncSession = Depends(tenant_session),
) -> UserResponse:
    ip = request.client.host if request.client else None
    ua = request.headers.get("User-Agent")
    user = await UserService.update_user(db, principal, user_id, data, ip_address=ip, user_agent=ua)
    return UserResponse.model_validate(user)


@router.delete(
    "/{user_id}",
    response_model=UserResponse,
    summary="Deactivate a user and disable auth login (Admin only)",
)
async def deactivate_user(
    user_id: UUID,
    request: Request,
    principal: Principal = Depends(require_roles("admin")),
    db: AsyncSession = Depends(tenant_session),
) -> UserResponse:
    ip = request.client.host if request.client else None
    ua = request.headers.get("User-Agent")
    user = await UserService.deactivate_user(db, principal, user_id, ip_address=ip, user_agent=ua)
    return UserResponse.model_validate(user)
