#!/bin/bash
# Applies only the idempotent IoT schema/grant foundation as postgres.

set -euo pipefail

apt-get update -qq
apt-get install -y -qq postgresql-client
curl -fsSL -o /usr/local/bin/cloud-sql-proxy \
  "https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.14.1/cloud-sql-proxy.linux.amd64"
chmod +x /usr/local/bin/cloud-sql-proxy

DB_PASSWORD=$(gcloud secrets versions access latest \
  --secret="${SECRET_NAME}" \
  --project="${PROJECT_ID}")
export PGPASSWORD="${DB_PASSWORD}"

cloud-sql-proxy "${PROJECT_ID}:${REGION}:${INSTANCE}" --port=5432 --quiet &
PROXY_PID=$!
cleanup() {
  unset PGPASSWORD DB_PASSWORD
  kill "${PROXY_PID}" 2>/dev/null || true
}
trap cleanup EXIT

for i in $(seq 1 30); do
  if pg_isready -h 127.0.0.1 -p 5432 -U postgres -q 2>/dev/null; then
    break
  fi
  if [ "${i}" -eq 30 ]; then
    echo "Cloud SQL Auth Proxy unavailable after 30 seconds" >&2
    exit 1
  fi
  sleep 1
done

psql -h 127.0.0.1 -p 5432 -U postgres -d "${DB_NAME}" \
  -f /workspace/modules/cloud_sql/sql/15_iot_foundation.sql \
  -v ON_ERROR_STOP=1 -q

psql -h 127.0.0.1 -p 5432 -U postgres -d "${DB_NAME}" -v ON_ERROR_STOP=1 -q -c "
  SELECT
    has_schema_privilege('bt_app', 'iot', 'USAGE') AS bt_app_iot_usage,
    has_schema_privilege('bt_app', 'iot', 'CREATE') AS bt_app_iot_create;
  SELECT defaclrole::regrole, defaclacl
  FROM pg_default_acl
  WHERE defaclnamespace = 'iot'::regnamespace
    AND defaclrole = 'postgres'::regrole
  ORDER BY defaclobjtype;"
