"""
adapters/local_adapter.py — Implementazioni locali per test senza GCS/DB.
"""

import logging
import uuid
from pathlib import Path

from domain.models import BimElement, BimModel, BimQuantity
from ports.db_port import DbPort
from ports.storage_port import StoragePort

logger = logging.getLogger(__name__)


class LocalStorageAdapter(StoragePort):
    def __init__(self, base_dir: str = "test_data"):
        self._base = Path(base_dir)
        self._base.mkdir(parents=True, exist_ok=True)

    def _path(self, bucket: str, path: str) -> Path:
        return self._base / bucket / path

    def get_file_bytes(self, bucket: str, path: str) -> bytes:
        local = self._path(bucket, path)
        if not local.exists():
            raise FileNotFoundError(f"File locale non trovato: {local}")
        return local.read_bytes()

    def move_file(self, src_bucket: str, src_path: str, dst_bucket: str, dst_path: str) -> None:
        self.copy_file(src_bucket, src_path, dst_bucket, dst_path)
        self.delete_file(src_bucket, src_path)

    def copy_file(self, src_bucket: str, src_path: str, dst_bucket: str, dst_path: str) -> None:
        src = self._path(src_bucket, src_path)
        dst = self._path(dst_bucket, dst_path)
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(src.read_bytes())

    def delete_file(self, bucket: str, path: str) -> None:
        local = self._path(bucket, path)
        if local.exists():
            local.unlink()


class LocalDbAdapter(DbPort):
    """DB adapter in memoria per test unitari."""

    def __init__(self):
        self.bim_models: dict[str, BimModel] = {}
        self.elements: dict[str, BimElement] = {}
        self.quantities: list[BimQuantity] = []

    async def connect(self) -> None:
        pass

    async def close(self) -> None:
        pass

    async def upsert_bim_model(self, model: BimModel) -> str:
        existing_id = next(
            (k for k, v in self.bim_models.items() if v.source_gcs_path == model.source_gcs_path),
            None,
        )
        model_id = existing_id or str(uuid.uuid4())
        model.id = model_id
        self.bim_models[model_id] = model
        return model_id

    async def upsert_elements(self, elements: list[BimElement]) -> dict[str, str]:
        ifc_to_id: dict[str, str] = {}
        for elem in elements:
            existing_id = next(
                (k for k, v in self.elements.items()
                 if v.model_id == elem.model_id and v.ifc_guid == elem.ifc_guid),
                None,
            )
            elem_id = existing_id or str(uuid.uuid4())
            elem.id = elem_id
            self.elements[elem_id] = elem
            ifc_to_id[elem.ifc_guid] = elem_id
        return ifc_to_id

    async def upsert_quantities(self, quantities: list[BimQuantity]) -> None:
        self.quantities.extend(quantities)

    async def update_model_status(self, model_id: str, status: str, total_imported: int) -> None:
        if model_id in self.bim_models:
            self.bim_models[model_id].import_status = status
            self.bim_models[model_id].total_elements_imported = total_imported

    def summary(self) -> dict:
        categories: dict[str, int] = {}
        for elem in self.elements.values():
            categories[elem.category] = categories.get(elem.category, 0) + 1
        return {
            "models": len(self.bim_models),
            "elements": len(self.elements),
            "quantities": len(self.quantities),
            "by_category": categories,
        }
