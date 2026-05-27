-- =============================================================================
-- migrate_09_bim_model_source_project_code.sql
-- Schema: bim - separates BT platform project_code from source Revit/JSON project code
--
-- COSA FA:
--   1. Adds bim.bim_model.source_project_code.
--   2. Backfills source_project_code conservatively from current project_code.
--
-- NOTA:
--   This migration does not correct historical project_code values.
-- =============================================================================

BEGIN;

ALTER TABLE bim.bim_model
    ADD COLUMN IF NOT EXISTS source_project_code VARCHAR(50);

UPDATE bim.bim_model
SET source_project_code = project_code
WHERE source_project_code IS NULL;

COMMIT;
