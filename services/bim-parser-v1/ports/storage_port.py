"""
ports/storage_port.py — Interfaccia astratta per lo storage dei file.

In architettura esagonale, una "Port" è un'interfaccia che definisce cosa
il domain può richiedere al mondo esterno, SENZA sapere come viene implementato.

Questo file definisce COSA fare con i file (scarica, sposta).
L'IMPLEMENTAZIONE (GCS reale, filesystem locale per test) è negli adapters/.
"""

from abc import ABC, abstractmethod


class StoragePort(ABC):
    """
    Interfaccia astratta per operazioni sui file.

    Implementazioni:
      - GcsAdapter    → Google Cloud Storage (produzione)
      - LocalStorageAdapter → filesystem locale (test)
    """

    @abstractmethod
    def get_file_bytes(self, bucket: str, path: str) -> bytes:
        """
        Scarica un file e restituisce i bytes.

        Args:
            bucket: nome del bucket (es. "bt-platform-staging-prod")
            path:   path del file nel bucket (es. "uploads/file.json")

        Returns:
            Contenuto del file come bytes.

        Raises:
            FileNotFoundError: se il file non esiste
            IOError: per errori di connessione
        """
        ...

    @abstractmethod
    def move_file(
        self,
        src_bucket: str,
        src_path: str,
        dst_bucket: str,
        dst_path: str,
    ) -> None:
        """
        Sposta un file da una posizione a un'altra (copia + elimina sorgente).
        Idempotente: se il file di destinazione esiste già, lo sovrascrive.

        Args:
            src_bucket: bucket sorgente
            src_path:   path sorgente nel bucket
            dst_bucket: bucket destinazione
            dst_path:   path destinazione nel bucket
        """
        ...

    @abstractmethod
    def copy_file(
        self,
        src_bucket: str,
        src_path: str,
        dst_bucket: str,
        dst_path: str,
    ) -> None:
        """
        Copia un file senza eliminare la sorgente.

        Usato per backup/audit: copia il file originale in un prefisso
        di archivio prima di processarlo.
        """
        ...

    @abstractmethod
    def delete_file(self, bucket: str, path: str) -> None:
        """
        Elimina un file dal bucket.

        Args:
            bucket: nome del bucket
            path:   path del file da eliminare
        """
        ...
