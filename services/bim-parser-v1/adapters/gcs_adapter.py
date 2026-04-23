"""
adapters/gcs_adapter.py — Implementazione GCS della StoragePort.

Questo adapter traduce le operazioni astratte della StoragePort in
chiamate reali a Google Cloud Storage.

Librerie usate:
  - google-cloud-storage: client GCS ufficiale Google
  - Il SA del Cloud Run (sa-bt-parser-prod) ha roles/storage.objectAdmin
    su tutti i bucket della pipeline, quindi non servono credenziali esplicite.
    Cloud Run inietta automaticamente le credenziali del SA.
"""

import logging
from google.cloud import storage
from ports.storage_port import StoragePort

logger = logging.getLogger(__name__)


class GcsAdapter(StoragePort):
    """
    Adapter per Google Cloud Storage.
    Viene istanziato UNA volta all'avvio del Cloud Run (singleton de facto).
    """

    def __init__(self):
        # Il client usa automaticamente le credenziali Application Default (ADC):
        # in Cloud Run = credenziali del SA sa-bt-parser-prod.
        # In locale = credenziali gcloud del tuo account (gcloud auth application-default login).
        self._client = storage.Client()
        logger.info("GcsAdapter inizializzato (ADC project: %s)", self._client.project)

    def get_file_bytes(self, bucket: str, path: str) -> bytes:
        """Scarica il contenuto di un file GCS come bytes."""
        logger.debug("GCS download: gs://%s/%s", bucket, path)
        blob = self._client.bucket(bucket).blob(path)
        if not blob.exists():
            raise FileNotFoundError(f"File non trovato: gs://{bucket}/{path}")
        return blob.download_as_bytes()

    def move_file(
        self,
        src_bucket: str,
        src_path: str,
        dst_bucket: str,
        dst_path: str,
    ) -> None:
        """
        Sposta un file: copia nel bucket di destinazione, poi elimina la sorgente.
        In GCS non esiste una primitiva "move" nativa: copia + delete è lo standard.
        """
        self.copy_file(src_bucket, src_path, dst_bucket, dst_path)
        self.delete_file(src_bucket, src_path)
        logger.info("GCS move: gs://%s/%s → gs://%s/%s", src_bucket, src_path, dst_bucket, dst_path)

    def copy_file(
        self,
        src_bucket: str,
        src_path: str,
        dst_bucket: str,
        dst_path: str,
    ) -> None:
        """Copia un file da un bucket/path a un altro bucket/path."""
        src_blob = self._client.bucket(src_bucket).blob(src_path)
        dst_bucket_obj = self._client.bucket(dst_bucket)
        # rewrite è più efficiente di download+upload per file grandi
        self._client.bucket(src_bucket).copy_blob(src_blob, dst_bucket_obj, dst_path)
        logger.debug("GCS copy: gs://%s/%s → gs://%s/%s", src_bucket, src_path, dst_bucket, dst_path)

    def delete_file(self, bucket: str, path: str) -> None:
        """Elimina un file dal bucket. Non fallisce se il file non esiste."""
        blob = self._client.bucket(bucket).blob(path)
        if blob.exists():
            blob.delete()
            logger.debug("GCS delete: gs://%s/%s", bucket, path)
        else:
            logger.warning("GCS delete: file non trovato (già eliminato?): gs://%s/%s", bucket, path)
