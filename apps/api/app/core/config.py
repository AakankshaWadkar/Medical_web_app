import os

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Connect as role app_backend (NOT postgres). Local: port 54122 direct, or pooler 6543 in prod.
    database_url: str = (
        os.getenv("APP_DB_URL")
        or "postgresql+asyncpg://app_backend:app_backend_dev@127.0.0.1:54122/postgres"
    )
    # Admin/Platform connection used strictly for CLI provisioning (never in request handlers)
    platform_admin_url: str = (
        os.getenv("ADMIN_DB_URL")
        or "postgresql+asyncpg://postgres:postgres@127.0.0.1:54122/postgres"
    )
    supabase_url: str = os.getenv("SUPABASE_URL", "http://127.0.0.1:54121")
    # Only for legacy HS256 projects; leave empty to verify via JWKS (asymmetric keys).
    supabase_jwt_secret: str = os.getenv("SUPABASE_JWT_SECRET", "")
    supabase_service_role_key: str = os.getenv(
        "SUPABASE_SERVICE_ROLE_KEY",
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU",
    )
    jwt_audience: str = "authenticated"

    default_page_size: int = 20
    max_page_size: int = 100


settings = Settings()
