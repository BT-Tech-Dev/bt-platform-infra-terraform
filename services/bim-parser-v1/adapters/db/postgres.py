"""
adapters/db/postgres.py — Adapter PostgreSQL async (SQLAlchemy + asyncpg).

Connessione via Cloud SQL Python Connector (AsyncConnector):
  - NON apre connessione nel __init__
  - connect() è async e viene chiamato dal lifespan di FastAPI
  - usa async_creator per creare il pool SQLAlchemy senza IP diretto

Pattern:
    adapter = PostgresAdapter(settings)
    await adapter.connect()          # apre il pool
    ...
    await adapter.close()            # chiude pool e connector
"""

from __future__ import annotations

import json
import logging
from typing import Optional

from google.cloud.sql.connector import AsyncConnector
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from config import Settings
from domain.models import BimElement, BimModel, BimQuantity
from ports.db_port import DbPort

logger = logging.getLogger(__name__)


class PostgresAdapter(DbPort):
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._connector: Optional[AsyncConnector] = None
        self._engine: Optional[AsyncEngine] = None
        self._session_factory = None

    async def connect(self) -> None:
        self._connector = AsyncConnector()

        async def _getconn():
            return await self._connector.connect(
                self._settings.instance_connection_name,
                "asyncpg",
                user=self._settings.db_user,
                password=self._settings.db_password,
                db=self._settings.db_name,
            )

        self._engine = create_async_engine(
            self._settings.database_url,
            async_creator=_getconn,
            pool_size=2,
            max_overflow=0,
            echo=False,
        )
        self._session_factory = sessionmaker(
            self._engine, class_=AsyncSession, expire_on_commit=False
        )
        logger.info(
            "PostgresAdapter connesso: instance=%s schema=%s",
            self._settings.instance_connection_name,
            self._settings.db_schema,
        )

    async def close(self) -> None:
        if self._engine:
            await self._engine.dispose()
        if self._connector:
            await self._connector.close_async()

    async def upsert_bim_model(self, model: BimModel) -> str:
        sql = text("""
            INSERT INTO bim.bim_model (
                tenant_id, project_code, file_name, export_guid,
                authoring_tool, ifc_version, json_version, exported_at,
                source_gcs_path, source_file_hash,
                total_elements_raw, total_elements_imported, import_status
            ) VALUES (
                :tenant_id, :project_code, :file_name, :export_guid,
                :authoring_tool, :ifc_version, :json_version, :exported_at::timestamptz,
                :source_gcs_path, :source_file_hash,
                :total_elements_raw, :total_elements_imported, :import_status
            )
            ON CONFLICT (tenant_id, source_gcs_path)
                DO UPDATE SET
                    project_code            = EXCLUDED.project_code,
                    file_name               = EXCLUDED.file_name,
                    export_guid             = EXCLUDED.export_guid,
                    json_version            = EXCLUDED.json_version,
                    exported_at             = EXCLUDED.exported_at,
                    source_file_hash        = EXCLUDED.source_file_hash,
                    total_elements_raw      = EXCLUDED.total_elements_raw,
                    total_elements_imported = EXCLUDED.total_elements_imported,
                    import_status           = EXCLUDED.import_status
            RETURNING id
        """)
        async with self._session_factory() as session:
            result = await session.execute(sql, {
                "tenant_id": model.tenant_id,
                "project_code": model.project_code,
                "file_name": model.file_name,
                "export_guid": model.export_guid,
                "authoring_tool": model.authoring_tool,
                "ifc_version": model.ifc_version,
                "json_version": model.json_version,
                "exported_at": model.exported_at,
                "source_gcs_path": model.source_gcs_path,
                "source_file_hash": model.source_file_hash,
                "total_elements_raw": model.total_elements_raw,
                "total_elements_imported": model.total_elements_imported,
                "import_status": model.import_status,
            })
            await session.commit()
            row = result.fetchone()
            model_id = str(row[0])
            logger.info("BimModel upsert OK: id=%s file=%s", model_id, model.file_name)
            return model_id

    async def upsert_elements(self, elements: list[BimElement]) -> dict[str, str]:
        if not elements:
            return {}

        sql = text("""
            INSERT INTO bim.bim_element (
                tenant_id, model_id, ifc_guid, category, family,
                type_name, level, parameters
            ) VALUES (
                :tenant_id, :model_id::uuid, :ifc_guid, :category, :family,
                :type_name, :level, :parameters::jsonb
            )
            ON CONFLICT (model_id, ifc_guid)
                DO UPDATE SET
                    category   = EXCLUDED.category,
                    family     = EXCLUDED.family,
                    type_name  = EXCLUDED.type_name,
                    level      = EXCLUDED.level,
                    parameters = EXCLUDED.parameters
            RETURNING id, ifc_guid
        """)
        ifc_to_id: dict[str, str] = {}
        async with self._session_factory() as session:
            for elem in elements:
                result = await session.execute(sql, {
                    "tenant_id": elem.tenant_id,
                    "model_id": elem.model_id,
                    "ifc_guid": elem.ifc_guid,
                    "category": elem.category,
                    "family": elem.family,
                    "type_name": elem.type_name,
                    "level": elem.level,
                    "parameters": json.dumps(elem.parameters),
                })
                row = result.fetchone()
                if row:
                    ifc_to_id[elem.ifc_guid] = str(row[0])
            await session.commit()
        logger.info("BimElement upsert OK: %d elementi", len(ifc_to_id))
        return ifc_to_id

    async def upsert_quantities(self, quantities: list[BimQuantity]) -> None:
        if not quantities:
            return

        sql = text("""
            INSERT INTO bim.bim_quantity (
                tenant_id, element_id, quantity_type, value, unit_of_measure
            ) VALUES (
                :tenant_id, :element_id::uuid, :quantity_type, :value, :unit_of_measure
            )
            ON CONFLICT (element_id, quantity_type)
                DO UPDATE SET
                    value           = EXCLUDED.value,
                    unit_of_measure = EXCLUDED.unit_of_measure
        """)
        async with self._session_factory() as session:
            for qty in quantities:
                if not qty.element_id:
                    logger.warning(
                        "Quantità senza element_id: %s %s", qty.quantity_type, qty._ifc_guid
                    )
                    continue
                await session.execute(sql, {
                    "tenant_id": qty.tenant_id,
                    "element_id": qty.element_id,
                    "quantity_type": qty.quantity_type,
                    "value": qty.value,
                    "unit_of_measure": qty.unit_of_measure,
                })
            await session.commit()
        logger.info("BimQuantity upsert OK: %d quantità", len(quantities))

    async def update_model_status(
        self, model_id: str, status: str, total_imported: int
    ) -> None:
        sql = text("""
            UPDATE bim.bim_model
            SET import_status = :status, total_elements_imported = :total
            WHERE id = :model_id::uuid
        """)
        async with self._session_factory() as session:
            await session.execute(sql, {
                "status": status,
                "total": total_imported,
                "model_id": model_id,
            })
            await session.commit()


async def get_db_adapter(settings: Settings) -> PostgresAdapter:
    """Factory async: crea e connette il PostgresAdapter."""
    adapter = PostgresAdapter(settings)
    await adapter.connect()
    return adapter
