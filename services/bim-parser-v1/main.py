"""
main.py — FastAPI app per bim-parser-v1.

Pipeline: EventArc → POST /ingest → bim-parser-v1 → bim.bim_model/element/quantity

ENV vars lette da config.py (Pydantic Settings):
  STAGING_BUCKET, INGEST_BUCKET, INSTANCE_CONNECTION_NAME,
  DB_USER, DB_PASSWORD, DB_NAME, DB_SCHEMA, TENANT_ID, LOG_LEVEL
"""

import base64
import json
import logging
import os
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request

from adapters.db.postgres import get_db_adapter
from adapters.gcs_adapter import GcsAdapter
from config import Settings
from domain.parser import compute_file_hash, parse_bim_json
from ports.db_port import DbPort
from ports.storage_port import StoragePort

settings = Settings()

log_level = getattr(logging, settings.log_level.upper(), logging.INFO)
logging.basicConfig(
    level=log_level,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    stream=sys.stdout,
)
logger = logging.getLogger("bim-parser-v1")


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Warm-up bim-parser-v1: inizializzazione adapter...")
    app.state.storage = GcsAdapter()

    try:
        app.state.db = await get_db_adapter(settings)
        logger.info("Warm-up completato. Pronto a ricevere eventi da EventArc.")
    except Exception as exc:
        logger.warning("DB non raggiungibile al warm-up: %s — avvio senza DB", exc)
        app.state.db = None

    yield

    logger.info("Shutdown bim-parser-v1...")
    if app.state.db is not None:
        await app.state.db.close()


app = FastAPI(
    title="bim-parser-v1",
    description="Parsing JSON Revit → PostgreSQL per BuildTrust Platform",
    version="1.0.0",
    lifespan=lifespan,
)


@app.get("/health")
def health():
    return {"status": "ok", "service": "bim-parser-v1"}


@app.post("/ingest")
async def ingest(request: Request):
    storage: StoragePort = request.app.state.storage
    db: DbPort | None = request.app.state.db

    if db is None:
        raise HTTPException(status_code=503, detail="DB non disponibile")

    # ── 1. Decodifica payload EventArc ──────────────────────────────────────
    try:
        body = await request.json()
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Payload non valido: {exc}")

    message = body.get("message", {})
    encoded_data = message.get("data", "")
    if not encoded_data:
        logger.warning("Messaggio Pub/Sub senza campo 'data': %s", body)
        return {"status": "ignored", "reason": "messaggio senza dati"}

    try:
        gcs_event = json.loads(base64.b64decode(encoded_data).decode("utf-8"))
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"Payload GCS non valido: {exc}")

    bucket = gcs_event.get("bucket", "")
    file_path = gcs_event.get("name", "")

    if not bucket or not file_path:
        return {"status": "ignored", "reason": "evento GCS incompleto"}

    if not file_path.startswith("uploads/"):
        return {"status": "ignored", "reason": f"file non in uploads/: {file_path}"}

    if not file_path.lower().endswith(".json"):
        return {"status": "ignored", "reason": f"file non JSON: {file_path}"}

    logger.info("Inizio elaborazione: gs://%s/%s", bucket, file_path)

    # ── 2. Download da GCS ───────────────────────────────────────────────────
    try:
        file_bytes = storage.get_file_bytes(bucket, file_path)
    except FileNotFoundError:
        logger.error("File non trovato su GCS: gs://%s/%s", bucket, file_path)
        return {"status": "ignored", "reason": "file non trovato su GCS"}

    max_bytes = settings.max_size_mb * 1024 * 1024
    if len(file_bytes) > max_bytes:
        raise HTTPException(status_code=413, detail=f"File > {settings.max_size_mb}MB")

    # ── 3. Parsing JSON ──────────────────────────────────────────────────────
    try:
        json_data = json.loads(file_bytes.decode("utf-8"))
    except json.JSONDecodeError as exc:
        logger.error("JSON non valido nel file %s: %s", file_path, exc)
        _move_to_error(storage, bucket, file_path, f"json_invalid: {exc}")
        raise HTTPException(status_code=422, detail=f"File JSON non valido: {exc}")

    gcs_path_full = f"gs://{bucket}/{file_path}"
    file_hash = compute_file_hash(file_bytes)

    try:
        bim_model, elements, quantities = parse_bim_json(
            json_data=json_data,
            tenant_id=settings.tenant_id,
            gcs_path=gcs_path_full,
        )
        bim_model.source_file_hash = file_hash
    except Exception as exc:
        logger.error("Errore parsing BIM: %s", exc, exc_info=True)
        _move_to_error(storage, bucket, file_path, f"parse_error: {exc}")
        raise HTTPException(status_code=500, detail=f"Errore parsing: {exc}")

    # ── 4. Salvataggio PostgreSQL ────────────────────────────────────────────
    try:
        model_id = await db.upsert_bim_model(bim_model)

        for elem in elements:
            elem.model_id = model_id
        ifc_to_id = await db.upsert_elements(elements)

        for qty in quantities:
            if qty._ifc_guid and qty._ifc_guid in ifc_to_id:
                qty.element_id = ifc_to_id[qty._ifc_guid]
        await db.upsert_quantities(quantities)

        await db.update_model_status(model_id, "completed", len(elements))

    except Exception as exc:
        logger.error("Errore salvataggio DB: %s", exc, exc_info=True)
        _move_to_error(storage, bucket, file_path, f"db_error: {exc}")
        raise HTTPException(status_code=500, detail=f"Errore DB: {exc}")

    # ── 5. Sposta in processed/ ──────────────────────────────────────────────
    file_name = os.path.basename(file_path)
    processed_path = f"{settings.processed_prefix}{file_name}"
    try:
        storage.move_file(
            src_bucket=bucket,
            src_path=file_path,
            dst_bucket=settings.staging_bucket,
            dst_path=processed_path,
        )
        logger.info(
            "File spostato in processed: gs://%s/%s", settings.staging_bucket, processed_path
        )
    except Exception as exc:
        logger.warning("Move file fallito (non critico): %s", exc)

    result = {
        "status": "ok",
        "model_id": model_id,
        "file": file_path,
        "elements_imported": len(elements),
        "quantities_imported": len(quantities),
    }
    logger.info("Elaborazione completata: %s", result)
    return result


def _move_to_error(storage: StoragePort, bucket: str, file_path: str, reason: str) -> None:
    try:
        file_name = os.path.basename(file_path)
        error_path = f"error/parser/{file_name}"
        storage.move_file(bucket, file_path, bucket, error_path)
        logger.info("File spostato in error/: %s (motivo: %s)", error_path, reason)
    except Exception as exc:
        logger.warning("Impossibile spostare in error/: %s", exc)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8080, reload=True)
