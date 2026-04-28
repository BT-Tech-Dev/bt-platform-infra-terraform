from __future__ import annotations

from typing import Literal

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Cloud Storage
    staging_bucket: str
    ingest_bucket: str
    storage_backend: Literal["gcs", "s3", "minio"] = "gcs"

    # Cloud SQL — la connessione è costruita dal Cloud SQL Connector,
    # non da una stringa IP diretta.
    instance_connection_name: str
    db_user: str
    db_password: str
    db_name: str
    db_schema: str = "bim"

    # Applicazione
    tenant_id: str
    processed_prefix: str = "processed/"
    max_size_mb: int = 50
    log_level: str = "INFO"

    @property
    def database_url(self) -> str:
        """URL SQLAlchemy asyncpg via Unix socket Cloud SQL Proxy.
        Cloud Run monta automaticamente /cloudsql/<instance>."""
        return (
            f"postgresql+asyncpg://{self.db_user}:{self.db_password}"
            f"@/{self.db_name}"
            f"?host=/cloudsql/{self.instance_connection_name}"
        )

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}
