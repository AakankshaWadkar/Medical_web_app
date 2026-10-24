import logging
import time
import uuid

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint

logger = logging.getLogger("pharmasphere.access")


class RequestIDMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        req_id = request.headers.get("X-Request-ID")
        if not req_id:
            req_id = str(uuid.uuid4())

        request.state.request_id = req_id

        start_time = time.perf_counter()
        response = await call_next(request)
        duration_ms = round((time.perf_counter() - start_time) * 1000, 2)

        response.headers["X-Request-ID"] = req_id

        # Access log without PII (paths, status, duration only)
        # Skip health check from access noise if ok
        if request.url.path != "/healthz":
            logger.info(
                "%s %s -> %s (%sms) [req_id=%s]",
                request.method,
                request.url.path,
                response.status_code,
                duration_ms,
                req_id,
            )

        return response
