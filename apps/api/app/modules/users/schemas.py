from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

UserRole = Literal["admin", "manager", "mr"]
UserStatus = Literal["active", "invited", "suspended"]

EmailType = Annotated[
    str,
    StringConstraints(
        pattern=r"^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$",
        to_lower=True,
    ),
]


class UserCreate(BaseModel):
    email: EmailType
    password: str = Field(min_length=8, description="Password min 8 chars")
    full_name: str = Field(min_length=1, max_length=255)
    app_role: UserRole
    phone: str | None = Field(default=None, max_length=30)
    employee_code: str | None = Field(default=None, max_length=50)
    manager_id: UUID | None = None
    branch_id: UUID | None = None


class UserUpdate(BaseModel):
    full_name: str | None = Field(default=None, min_length=1, max_length=255)
    phone: str | None = Field(default=None, max_length=30)
    employee_code: str | None = Field(default=None, max_length=50)
    manager_id: UUID | None = None
    branch_id: UUID | None = None
    app_role: UserRole | None = None
    status: UserStatus | None = None


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    tenant_id: UUID
    auth_user_id: UUID
    app_role: str
    full_name: str
    phone: str | None
    employee_code: str | None
    manager_id: UUID | None
    branch_id: UUID | None
    status: str
    created_at: datetime
    updated_at: datetime
