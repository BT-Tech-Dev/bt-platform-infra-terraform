-- =============================================================================
-- migrate_31_grant_revit_export_operational_event.sql
-- Post-migrate_30 least-privilege read access for the Revit actual export Job.
--
-- Prerequisites:
--   - migrate_30_moretti_manufactured_unit.sql has moved the canonical
--     operational evidence table to process.operational_event.
--   - The Terraform-managed built-in role revit_export_ro already exists.
--
-- Scope:
--   - Grants schema USAGE and column-level SELECT only.
--   - Does not grant table-level SELECT, write privileges, or access to other
--     process tables or columns.
-- =============================================================================

BEGIN;

DO $$
BEGIN
    IF to_regrole('revit_export_ro') IS NULL THEN
        RAISE EXCEPTION 'Required role revit_export_ro does not exist';
    END IF;

    IF to_regclass('process.operational_event') IS NULL THEN
        RAISE EXCEPTION 'Required table process.operational_event does not exist; apply migrate_30 first';
    END IF;
END
$$;

GRANT USAGE ON SCHEMA process TO revit_export_ro;

GRANT SELECT (operational_event_id, event_date)
    ON process.operational_event TO revit_export_ro;

COMMIT;

-- Read-only verification:
-- SELECT
--     has_schema_privilege('revit_export_ro', 'process', 'USAGE') AS process_usage,
--     has_column_privilege('revit_export_ro', 'process.operational_event', 'operational_event_id', 'SELECT') AS operational_event_id_select,
--     has_column_privilege('revit_export_ro', 'process.operational_event', 'event_date', 'SELECT') AS event_date_select;
