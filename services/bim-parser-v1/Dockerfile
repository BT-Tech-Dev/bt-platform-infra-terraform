# =============================================================================
# Dockerfile — bim-parser-v1
#
# Build multi-stage non necessario qui (app Python pura, nessuna compilazione C).
# Immagine base: python:3.12-slim (Debian Bookworm slim, ~45MB vs ~900MB full)
#
# Struttura cartelle nel container:
#   /app/
#   ├── domain/
#   ├── ports/
#   ├── adapters/
#   └── main.py
# =============================================================================

FROM python:3.12-slim

# ─── Metadata ─────────────────────────────────────────────────────────────────
LABEL service="bim-parser-v1"
LABEL project="bt-platform"
LABEL maintainer="BuildTrust Platform Team"

# ─── Dipendenze di sistema ────────────────────────────────────────────────────
# asyncpg distribuisce wheel precompilate per linux/amd64 + Python 3.12:
# nessuna compilazione C richiesta nel container.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ─── Utente non-root ─────────────────────────────────────────────────────────
# Best practice di sicurezza: non girare come root nel container.
# Cloud Run supporta utenti non-root senza problemi.
RUN useradd --create-home --shell /bin/bash appuser

# ─── Working directory ────────────────────────────────────────────────────────
WORKDIR /app

# ─── Dipendenze Python ────────────────────────────────────────────────────────
# Copia requirements.txt PRIMA del codice sorgente.
# Docker usa il layer caching: se requirements.txt non cambia, questo layer
# viene riusato anche se il codice sorgente cambia → build più veloci.
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# ─── Codice sorgente ──────────────────────────────────────────────────────────
COPY domain/     ./domain/
COPY ports/      ./ports/
COPY adapters/   ./adapters/
COPY main.py     .

# ─── Proprietà file ───────────────────────────────────────────────────────────
RUN chown -R appuser:appuser /app
USER appuser

# ─── Porta ────────────────────────────────────────────────────────────────────
# Cloud Run si aspetta che l'app ascolti sulla porta 8080 (configurabile via PORT env var).
EXPOSE 8080

# ─── Avvio ────────────────────────────────────────────────────────────────────
# --workers 1: un solo worker per processo Cloud Run.
#   Cloud Run scala con più istanze (non worker), quindi 1 worker per istanza
#   è la configurazione corretta. Evita problemi di shared state.
# --timeout-graceful-shutdown 10: aspetta 10s per le richieste in corso prima di spegnersi.
CMD ["uvicorn", "main:app", \
     "--host", "0.0.0.0", \
     "--port", "8080", \
     "--workers", "1", \
     "--timeout-graceful-shutdown", "10"]
