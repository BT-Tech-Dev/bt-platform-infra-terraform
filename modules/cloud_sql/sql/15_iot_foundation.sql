-- Terraform/infra owns this foundation only. Application migrations own all
-- iot.* tables and must run as postgres (or an explicitly equivalent migrator).

BEGIN;

CREATE SCHEMA IF NOT EXISTS iot;
COMMENT ON SCHEMA iot IS 'IoT gateway, device assignment, ingestion, and measurement domain';

GRANT USAGE ON SCHEMA iot TO bt_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA iot TO bt_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA iot TO bt_app;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA iot
  GRANT SELECT, INSERT, UPDATE ON TABLES TO bt_app;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA iot
  GRANT USAGE, SELECT ON SEQUENCES TO bt_app;

COMMIT;
