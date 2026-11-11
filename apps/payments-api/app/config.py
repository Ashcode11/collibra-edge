"""Configuration from environment variables (12-factor).

Non-secret settings come from a ConfigMap; DB_USER/DB_PASSWORD come from a
Kubernetes Secret. Nothing secret has a default value.
"""
import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    app_name: str
    app_env: str
    app_version: str
    log_level: str
    db_host: str
    db_port: int
    db_name: str
    db_user: str
    db_password: str
    db_pool_min: int
    db_pool_max: int
    db_timeout_seconds: float

    @property
    def dsn(self) -> str:
        return (
            f"host={self.db_host} port={self.db_port} dbname={self.db_name} "
            f"user={self.db_user} password={self.db_password} "
            f"connect_timeout={int(self.db_timeout_seconds)} application_name={self.app_name}"
        )


def load() -> Settings:
    return Settings(
        app_name=os.getenv("APP_NAME", "payments-api"),
        app_env=os.getenv("APP_ENV", "local"),
        app_version=os.getenv("APP_VERSION", "dev"),
        log_level=os.getenv("LOG_LEVEL", "INFO").upper(),
        db_host=os.getenv("DB_HOST", "localhost"),
        db_port=int(os.getenv("DB_PORT", "5432")),
        db_name=os.getenv("DB_NAME", "bank_core"),
        db_user=os.getenv("DB_USER", ""),
        db_password=os.getenv("DB_PASSWORD", ""),
        db_pool_min=int(os.getenv("DB_POOL_MIN", "1")),
        db_pool_max=int(os.getenv("DB_POOL_MAX", "5")),
        db_timeout_seconds=float(os.getenv("DB_TIMEOUT_SECONDS", "3")),
    )
