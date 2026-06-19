-- =============================================================================
-- migrate_20_grant_catalog_read_to_app.sql
-- Schema: catalog - grant Layer 0 catalog read access to application role
--
-- DRAFT ONLY. DO NOT APPLY UNTIL REVIEWED.
--
-- Scope:
--   - Grants only.
--   - Does not change tables, constraints, indexes, or data.
--   - Does not create classifier rule tables.
--   - Does not touch BIM registry, production, quality, progress,
--     reconciliation, or SAL tables.
--
-- Notes:
--   catalog.* stores Layer 0 reference data. Application services need
--   read-only access to resolve BT element type codes and validate classifier
--   configuration, including MS-01 classifier dry-runs.
--
--   This migration grants SELECT only. It does not grant INSERT, UPDATE,
--   DELETE, TRUNCATE, REFERENCES, or TRIGGER privileges on catalog tables.
-- =============================================================================

BEGIN;

GRANT USAGE ON SCHEMA catalog TO bt_app;

GRANT SELECT ON ALL TABLES IN SCHEMA catalog TO bt_app;

-- Keep future Layer 0 catalog reference tables readable by application
-- services when they are created by the same migration owner role that runs
-- this statement.
ALTER DEFAULT PRIVILEGES IN SCHEMA catalog
    GRANT SELECT ON TABLES TO bt_app;

COMMIT;

-- =============================================================================
-- Validation queries
-- =============================================================================

-- SELECT has_schema_privilege('bt_app', 'catalog', 'USAGE') AS bt_app_catalog_usage;

-- SELECT table_schema, table_name,
--        has_table_privilege('bt_app', format('%I.%I', table_schema, table_name), 'SELECT') AS bt_app_can_select
-- FROM information_schema.tables
-- WHERE table_schema = 'catalog'
--   AND table_type = 'BASE TABLE'
-- ORDER BY table_name;
