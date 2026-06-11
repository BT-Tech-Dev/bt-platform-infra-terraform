#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "${name} is required." >&2
    exit 1
  fi
}

refuse_production_value() {
  local name="$1"
  local value="${!name:-}"
  if [[ -n "${value}" && "${value,,}" =~ prod|production ]]; then
    echo "Refusing to run: ${name} appears to reference production." >&2
    exit 1
  fi
}

require_env DEV_DB_HOST
require_env DEV_DB_NAME
require_env DEV_DB_USER
require_env DEV_DB_PASSWORD

refuse_production_value DEV_DB_HOST
refuse_production_value DEV_DB_NAME
refuse_production_value DEV_GCP_PROJECT
refuse_production_value DEV_DB_SECRET_NAME

if [[ "${CONFIRM_DEV_DB_RESET:-}" != "YES" ]]; then
  echo "Refusing to run: set CONFIRM_DEV_DB_RESET=YES." >&2
  exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "psql is required and was not found on PATH." >&2
  exit 1
fi

DEV_DB_PORT="${DEV_DB_PORT:-5432}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
MIGRATIONS=(
  "scripts/migrations/migrate_12_bim_catalog_project_element_registry.sql"
  "scripts/migrations/migrate_13_layer3_canonical_evidence.sql"
  "scripts/migrations/migrate_14_progress_reconciliation_draft.sql"
)

echo "DESTRUCTIVE DEV MIGRATION TARGET"
echo "  Host: ${DEV_DB_HOST}"
echo "  Port: ${DEV_DB_PORT}"
echo "  Database: ${DEV_DB_NAME}"
echo "  User: ${DEV_DB_USER}"

export PGPASSWORD="${DEV_DB_PASSWORD}"
trap 'unset PGPASSWORD' EXIT

for migration in "${MIGRATIONS[@]}"; do
  migration_path="${REPO_ROOT}/${migration}"
  if [[ ! -f "${migration_path}" ]]; then
    echo "Migration file not found: ${migration_path}" >&2
    exit 1
  fi

  echo "Applying ${migration}"
  psql -X \
    -h "${DEV_DB_HOST}" \
    -p "${DEV_DB_PORT}" \
    -U "${DEV_DB_USER}" \
    -d "${DEV_DB_NAME}" \
    -v ON_ERROR_STOP=1 \
    -f "${migration_path}"
done

echo "Clean migrations 12-14 applied to the development database."
