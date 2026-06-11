#!/bin/bash
# =============================================================================
# scripts/init_db_cloudbuild.sh — Eseguito da Cloud Build per inizializzare il DB
#
# NON eseguire direttamente. Viene chiamato da cloudbuild-init-db.yaml.
# Le variabili d'ambiente vengono iniettate da Cloud Build:
#   PROJECT_ID  — progetto GCP (iniettato automaticamente da Cloud Build)
#   DB_NAME     — nome del database PostgreSQL
#   REGION      — regione dell'istanza Cloud SQL
#   INSTANCE    — nome dell'istanza Cloud SQL
#   SECRET_NAME — nome del secret in Secret Manager con la password postgres
# =============================================================================

set -euo pipefail

echo "========================================================"
echo "  BuildTrust Platform — Inizializzazione Database"
echo "  Progetto:  ${PROJECT_ID}"
echo "  Istanza:   ${REGION}:${INSTANCE}"
echo "  Database:  ${DB_NAME}"
echo "========================================================"

# ── 1. Installa psql ──────────────────────────────────────────────────────────
echo "-> Installo postgresql-client..."
apt-get update -qq
apt-get install -y -qq postgresql-client
echo "   OK: $(psql --version)"

# ── 2. Scarica Cloud SQL Auth Proxy ───────────────────────────────────────────
echo "-> Scarico cloud-sql-proxy..."
curl -sSL -o /usr/local/bin/cloud-sql-proxy \
  "https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.14.1/cloud-sql-proxy.linux.amd64"
chmod +x /usr/local/bin/cloud-sql-proxy
echo "   OK"

# ── 3. Recupera password da Secret Manager ────────────────────────────────────
echo "-> Recupero password da Secret Manager..."
DB_PASSWORD=$(gcloud secrets versions access latest \
  --secret="${SECRET_NAME}" \
  --project="${PROJECT_ID}")
export PGPASSWORD="${DB_PASSWORD}"
echo "   OK"

# ── 4. Avvia proxy in background ──────────────────────────────────────────────
echo "-> Avvio Cloud SQL Auth Proxy sulla porta 5432..."
cloud-sql-proxy "${PROJECT_ID}:${REGION}:${INSTANCE}" --port=5432 --quiet &
PROXY_PID=$!

# Attendi che la porta sia pronta (max 30 secondi)
for i in $(seq 1 30); do
  if pg_isready -h 127.0.0.1 -p 5432 -U postgres -q 2>/dev/null; then
    echo "   Proxy pronto dopo ${i}s"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERRORE: proxy non disponibile dopo 30s"
    kill "$PROXY_PID" 2>/dev/null || true
    exit 1
  fi
  sleep 1
done

# ── 5. Esegui gli script SQL in ordine ────────────────────────────────────────
echo ""
echo "-> Esecuzione script SQL..."
SQL_DIR="/workspace/modules/cloud_sql/sql"

SQL_FILES=(
  "01_schemas_extensions.sql"
  "02_schema_tenant.sql"
  "14_schema_raw.sql"
  "03_schema_bim.sql"
  "04_schema_process.sql"
  "05_schema_boq.sql"
  "09_schema_document.sql"
  "06_schema_production.sql"
  "07_schema_progress.sql"
  "08_schema_quality.sql"
  "10_schema_read.sql"
  "11_schema_external.sql"
  "12_seed_tenants.sql"
)

for BASENAME in "${SQL_FILES[@]}"; do
  f="${SQL_DIR}/${BASENAME}"
  BASENAME=$(basename "$f")
  echo "   -> ${BASENAME}..."
  psql -h 127.0.0.1 -p 5432 -U postgres -d "${DB_NAME}" \
    -f "$f" -v ON_ERROR_STOP=1 -q
  echo "      OK"
done

# ── 6. Verifica finale ────────────────────────────────────────────────────────
echo ""
echo "-> Verifica schemi creati:"
psql -h 127.0.0.1 -p 5432 -U postgres -d "${DB_NAME}" -c "
  SELECT schema_name
  FROM information_schema.schemata
  WHERE schema_name IN (
    'bim','process','boq','production','progress',
    'quality','tenant','document','read','external','raw'
  )
  ORDER BY schema_name;"

echo ""
echo "-> Verifica tenant:"
psql -h 127.0.0.1 -p 5432 -U postgres -d "${DB_NAME}" -c "
  SELECT code, name, status FROM tenant.company ORDER BY created_at;"

# ── Cleanup ───────────────────────────────────────────────────────────────────
kill "$PROXY_PID" 2>/dev/null || true

echo ""
echo "========================================================"
echo "  Database inizializzato con successo!"
echo "========================================================"
