from dataclasses import dataclass
from uuid import UUID

import jwt
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWKClient

from app.core.config import settings
from app.core.errors import ForbiddenError, UnauthorizedError

_bearer = HTTPBearer(auto_error=False)
_jwks = (
    None
    if settings.supabase_jwt_secret
    else PyJWKClient(f"{settings.supabase_url}/auth/v1/.well-known/jwks.json", cache_keys=True)
)


@dataclass(frozen=True)
class Principal:
    user_id: UUID  # auth_user_id from auth.users (JWT 'sub')
    tenant_id: UUID
    role: str  # admin | manager | mr


def _decode(token: str) -> dict:
    if settings.supabase_jwt_secret:
        return jwt.decode(
            token,
            settings.supabase_jwt_secret,
            algorithms=["HS256"],
            audience=settings.jwt_audience,
            options={"require": ["exp", "sub"]},
        )
    key = _jwks.get_signing_key_from_jwt(token).key  # type: ignore[union-attr]
    return jwt.decode(
        token,
        key,
        algorithms=["RS256", "ES256"],
        audience=settings.jwt_audience,
        options={"require": ["exp", "sub"]},
    )


def get_principal(creds: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> Principal:
    if creds is None:
        raise UnauthorizedError("Missing authorization header")
    try:
        claims = _decode(creds.credentials)
        if "tenant_id" not in claims or "app_role" not in claims:
            raise UnauthorizedError("Token missing tenant_id or app_role claims")
        return Principal(UUID(claims["sub"]), UUID(claims["tenant_id"]), claims["app_role"])
    except (jwt.PyJWTError, KeyError, ValueError) as err:
        raise UnauthorizedError(f"Invalid token: {err!s}") from None


def require_roles(*roles: str):
    def dep(p: Principal = Depends(get_principal)) -> Principal:
        if p.role not in roles:
            raise ForbiddenError("Insufficient role permissions")
        return p

    return dep
