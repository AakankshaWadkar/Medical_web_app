import math
from collections.abc import Sequence
from typing import Any, Generic, TypeVar

from fastapi import Query
from pydantic import BaseModel
from sqlalchemy import Select, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings

T = TypeVar("T")


class PaginationParams:
    def __init__(
        self,
        page: int = Query(1, ge=1, description="Page number starting at 1"),
        page_size: int = Query(
            settings.default_page_size,
            ge=1,
            le=settings.max_page_size,
            description="Page size limit",
        ),
    ) -> None:
        self.page = page
        self.page_size = page_size

    @property
    def offset(self) -> int:
        return (self.page - 1) * self.page_size

    @property
    def limit(self) -> int:
        return self.page_size


class PaginatedResponse(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int
    page_size: int
    total_pages: int


async def paginate(
    db: AsyncSession,
    stmt: Select,
    params: PaginationParams,
    count_stmt: Select | None = None,
) -> tuple[Sequence[Any], int, int]:
    """Execute query with limit/offset and count total matching rows."""
    if count_stmt is None:
        count_stmt = select(func.count()).select_from(stmt.order_by(None).subquery())

    total_result = await db.execute(count_stmt)
    total = total_result.scalar_one() or 0

    paged_stmt = stmt.offset(params.offset).limit(params.limit)
    items_result = await db.execute(paged_stmt)
    items = items_result.scalars().all()

    total_pages = math.ceil(total / params.page_size) if total > 0 else 0
    return items, total, total_pages
