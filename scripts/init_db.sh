#!/usr/bin/env bash
# =============================================================================
# scripts/init_db.sh — Inizializza gli 11 schemi PostgreSQL nel Cloud SQL
#
# Uso: bash scripts/init_db.sh [PROJECT_ID] [INSTANCE] [DB_NAME] [DB_USER]
# Es:  bash scripts/init_db.sh bt-platform-prod bt-platform-pg-prod db_bt_platform postgres
#
# Prerequisiti:
#   - gcloud autenticato: gcloud auth application-default login
#   - cloud-sql-proxy installato (o disponibile via gcloud)
#   - psql installato localmente
#
# Questo script:
#   1. Avvia Cloud SQL Auth Proxy in background (porta 5432 locale)
#   2. Esegue gli SQL script in ordine
#   3. Ferma il proxy
#
# Idempotente: usa CREATE TABLE IF NOT EXISTS e ON CONFLICT DO NOTHING.
# Si può rieseguire senza danni se già eseguito.
# =============================================================================

set -euo pipefail

# ─── Parametri ───────────────────────────────────────────────────────────────
PROJECT_ID="${1:-bt-platform-prod}"
INSTANCE="${2:-bt-platform-pg-prod}"
DB_NAME="${3:-db_bt_platform}"
DB_USER="${4:-postgres}"

REGION="europe-west8"
CONNECTION_NAME="${PROJECT_ID}:${REGION}:${INSTANCE}"
PROXY_PORT=5432
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="${SCRIPT_DIR}/../modules/cloud_sql/sql"

echo "========================================================"
echo "  BuildTrust Platform — Inizializzazione Database"
echo "========================================================"
echo "  Progetto:   ${PROJECT_ID}"
echo "  Istanza:    ${INSTANCE}"
echo "  Database:   ${DB_NAME}"
echo "  Utente:     ${DB_USER}"
echo "  Connection: ${CONNECTION_NAME}"
echo "========================================================"

# ─── Verifica prerequisiti ───────────────────────────────────────────────────
if ! command -v psql &>/dev/null; then
    echo "ERRORE: psql non trovato. Installa postgresql-client."
    echo "  Ubuntu/Debian: apt-get install postgresql-client"
    echo "  macOS: brew install libpq && brew link --force libpq"
    exit 1
fi

if ! command -v cloud-sql-proxy &>/dev/null; then
    echo "ERRORE: cloud-sql-proxy non trovato."
    echo "  Installa da: https://cloud.google.com/sql/docs/postgres/sql-proxy"
    echo "  Oppure: gcloud components install cloud-sql-proxy"
    exit 1
fi

# ─── Recupera password da Secret Manager ─────────────────────────────────────
SECRET_NAME="bt-platform-db-password-${PROJECT_ID##*-}"  # estrae "prod" da "bt-platform-prod"
SECRET_NAME="bt-platform-db-password-prod"

echo "→ Recupero password da Secret Manager (${SECRET_NAME})..."
DB_PASSWORD=$(gcloud secrets versions access latest \
    --secret="${SECRET_NAME}" \
    --project="${PROJECT_ID}" 2>/dev/null) || {
    echo "ATTENZIONE: secret non trovato o non valorizzato."
    echo "  Imposta la password con:"
    echo "  gcloud secrets versions add ${SECRET_NAME} --data-file=<(echo -n 'LA_TUA_PASSWORD')"
    echo ""
    echo "  Vuoi inserire la password manualmente? (solo per test locale)"
    read -s -p "  Password postgres: " DB_PASSWORD
    echo ""
}

export PGPASSWORD="${DB_PASSWORD}"

# ─── Avvio Cloud SQL Auth Proxy ───────────────────────────────────────────────
echo "→ Avvio Cloud SQL Auth Proxy..."
cloud-sql-proxy "${CONNECTION_NAME}" \
    --port "${PROXY_PORT}" \
    --credentials-file <(gcloud auth application-default print-access-token 2>/dev/null || echo "") \
    &>/tmp/cloud-sql-proxy.log &
PROXY_PID=$!
echo "  Proxy PID: ${PROXY_PID}"

# Aspetta che il proxy sia pronto (max 30 secondi)
echo "→ Attendo che il proxy sia pronto..."
for i in $(seq 1 30); do
    if pg_isready -h 127.0.0.1 -p ${PROXY_PORT} -U "${DB_USER}" -d "${DB_NAME}" &>/dev/null; then
        echo "  ✓ Proxy pronto dopo ${i} secondi"
        break
    fi
    sleep 1
    if [ $i -eq 30 ]; then
        echo "ERRORE: proxy non si è avviato in 30 secondi."
        echo "  Log proxy: cat /tmp/cloud-sql-proxy.log"
        kill $PROXY_PID 2>/dev/null
        exit 1
    fi
done

# ─── Funzione per eseguire un file SQL ────────────────────────────────────────
run_sql() {
    local file="$1"
    local description="$2"
    echo "→ ${description}..."
    psql \
        -h 127.0.0.1 \
        -p "${PROXY_PORT}" \
        -U "${DB_USER}" \
        -d "${DB_NAME}" \
        -f "${file}" \
        --set ON_ERROR_STOP=1 \
        -q
    echo "  ✓ ${description}"
}

# ─── Esecuzione script SQL in ordine ─────────────────────────────────────────
echo ""
echo "→ Esecuzione script SQL..."
echo ""

run_sql "${SQL_DIR}/01_schemas_extensions.sql"  "Creazione schemi e estensioni"
run_sql "${SQL_DIR}/02_schema_tenant.sql"        "Schema tenant (master)"
run_sql "${SQL_DIR}/14_schema_raw.sql"           "Schema raw (MS-05 ingestion)"
run_sql "${SQL_DIR}/02b_schema_catalog.sql"      "Schema catalog (Layer 0 reference data)"
run_sql "${SQL_DIR}/03_schema_bim.sql"           "Schema bim (dati Revit)"
run_sql "${SQL_DIR}/04_schema_process.sql"       "Schema process (lavorazioni)"
run_sql "${SQL_DIR}/05_schema_boq.sql"           "Schema boq (computo metrico)"
run_sql "${SQL_DIR}/09_schema_document.sql"      "Schema document (canonical Layer 3 evidence)"
run_sql "${SQL_DIR}/06_schema_production.sql"    "Schema production (OPC UA, Grigolin)"
run_sql "${SQL_DIR}/07_schema_progress.sql"      "Schema progress (SAL)"
run_sql "${SQL_DIR}/08_schema_quality.sql"       "Schema quality (certificati, NCR)"
run_sql "${SQL_DIR}/10_schema_read.sql"          "Schema read (CQRS proiezioni)"
run_sql "${SQL_DIR}/11_schema_external.sql"      "Schema external (integrazioni)"
run_sql "${SQL_DIR}/12_seed_tenants.sql"         "Seed tenant iniziali (PPDL, BAL2)"

# ─── Verifica finale ──────────────────────────────────────────────────────────
echo ""
echo "→ Verifica schemi creati..."
psql \
    -h 127.0.0.1 \
    -p "${PROXY_PORT}" \
    -U "${DB_USER}" \
    -d "${DB_NAME}" \
    -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name IN ('bim','process','boq','production','progress','quality','tenant','document','read','external','raw') ORDER BY schema_name;" \
    -q

echo ""
echo "→ Verifica tenant inseriti..."
psql \
    -h 127.0.0.1 \
    -p "${PROXY_PORT}" \
    -U "${DB_USER}" \
    -d "${DB_NAME}" \
    -c "SELECT code, name, status FROM tenant.company ORDER BY created_at;" \
    -q

# ─── Pulizia ─────────────────────────────────────────────────────────────────
echo ""
echo "→ Fermo il Cloud SQL Proxy..."
kill $PROXY_PID 2>/dev/null
unset PGPASSWORD

echo ""
echo "========================================================"
echo "  ✓ Database inizializzato con successo!"
echo ""
echo "  Prossimi passi:"
echo "  1. Imposta password utente bt_app:"
echo "     gcloud sql users set-password bt_app \\"
echo "       --instance=${INSTANCE} --project=${PROJECT_ID} \\"
echo "       --password=\$(openssl rand -base64 32)"
echo ""
echo "  2. Salva la password in Secret Manager:"
echo "     echo -n 'PASSWORD' | gcloud secrets versions add \\"
echo "       bt-platform-db-password-prod --data-file=-"
echo "========================================================"
