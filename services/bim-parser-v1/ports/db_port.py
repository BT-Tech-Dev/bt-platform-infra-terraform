from abc import ABC, abstractmethod

from domain.models import BimElement, BimModel, BimQuantity


class DbPort(ABC):
    @abstractmethod
    async def connect(self) -> None: ...

    @abstractmethod
    async def close(self) -> None: ...

    @abstractmethod
    async def upsert_bim_model(self, model: BimModel) -> str: ...

    @abstractmethod
    async def upsert_elements(self, elements: list[BimElement]) -> dict[str, str]: ...

    @abstractmethod
    async def upsert_quantities(self, quantities: list[BimQuantity]) -> None: ...

    @abstractmethod
    async def update_model_status(
        self, model_id: str, status: str, total_imported: int
    ) -> None: ...
