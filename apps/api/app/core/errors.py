import logging
from typing import Any

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from starlette.exceptions import HTTPException as StarletteHTTPException

logger = logging.getLogger("pharmasphere.errors")


class ErrorResponse(BaseModel):
    code: str
    message: str
    details: Any = None


class AppError(Exception):
    def __init__(
        self,
        code: str,
        message: str,
        status_code: int = status.HTTP_400_BAD_REQUEST,
        details: Any = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code
        self.details = details


class BadRequestError(AppError):
    def __init__(self, message: str, code: str = "BAD_REQUEST", details: Any = None) -> None:
        super().__init__(
            code=code, message=message, status_code=status.HTTP_400_BAD_REQUEST, details=details
        )


class UnauthorizedError(AppError):
    def __init__(self, message: str, code: str = "UNAUTHORIZED", details: Any = None) -> None:
        super().__init__(
            code=code, message=message, status_code=status.HTTP_401_UNAUTHORIZED, details=details
        )


class ForbiddenError(AppError):
    def __init__(self, message: str, code: str = "FORBIDDEN", details: Any = None) -> None:
        super().__init__(
            code=code, message=message, status_code=status.HTTP_403_FORBIDDEN, details=details
        )


class NotFoundError(AppError):
    def __init__(self, message: str, code: str = "NOT_FOUND", details: Any = None) -> None:
        super().__init__(
            code=code, message=message, status_code=status.HTTP_404_NOT_FOUND, details=details
        )


class ConflictError(AppError):
    def __init__(self, message: str, code: str = "CONFLICT", details: Any = None) -> None:
        super().__init__(
            code=code, message=message, status_code=status.HTTP_409_CONFLICT, details=details
        )


class UnprocessableEntityError(AppError):
    def __init__(
        self, message: str, code: str = "UNPROCESSABLE_ENTITY", details: Any = None
    ) -> None:
        super().__init__(
            code=code,
            message=message,
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            details=details,
        )


async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={"code": exc.code, "message": exc.message, "details": exc.details},
    )


async def http_exception_handler(
    request: Request, exc: HTTPException | StarletteHTTPException
) -> JSONResponse:
    code_map = {
        status.HTTP_400_BAD_REQUEST: "BAD_REQUEST",
        status.HTTP_401_UNAUTHORIZED: "UNAUTHORIZED",
        status.HTTP_403_FORBIDDEN: "FORBIDDEN",
        status.HTTP_404_NOT_FOUND: "NOT_FOUND",
        status.HTTP_409_CONFLICT: "CONFLICT",
        status.HTTP_422_UNPROCESSABLE_CONTENT: "UNPROCESSABLE_ENTITY",
    }
    code = code_map.get(exc.status_code, "ERROR")
    message = str(exc.detail) if exc.detail else "An HTTP error occurred"
    return JSONResponse(
        status_code=exc.status_code,
        content={"code": code, "message": message, "details": None},
    )


async def validation_exception_handler(
    request: Request, exc: RequestValidationError
) -> JSONResponse:
    # Sanitize errors to avoid leaking internal structure
    details = [
        {
            "field": ".".join(str(loc) for loc in err["loc"] if loc != "body"),
            "issue": err["msg"],
            "type": err["type"],
        }
        for err in exc.errors()
    ]
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        content={
            "code": "VALIDATION_ERROR",
            "message": "Input validation failed",
            "details": details,
        },
    )


async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    req_id = getattr(request.state, "request_id", "unknown")
    logger.exception("Unhandled server error [req_id=%s]: %s", req_id, type(exc).__name__)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "code": "INTERNAL_SERVER_ERROR",
            "message": "An unexpected server error occurred",
            "details": None,
        },
    )


def register_error_handlers(app: FastAPI) -> None:
    app.add_exception_handler(AppError, app_error_handler)
    app.add_exception_handler(HTTPException, http_exception_handler)
    app.add_exception_handler(StarletteHTTPException, http_exception_handler)
    app.add_exception_handler(RequestValidationError, validation_exception_handler)
    app.add_exception_handler(Exception, unhandled_exception_handler)
