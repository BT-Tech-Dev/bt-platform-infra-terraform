-- =============================================================================
-- migrate_22_boq_source_tracking.sql
-- Schema: boq - adds source file tracking to boq.boq for the ingestion
--   revision guard (mirror of migrate_09_bim_model_source_project_code.sql /
--   bim.bim_model.source_file_hash).
--
-- COSA FA:
--   1. Adds boq.boq.source_gcs_path and boq.boq.source_file_hash.
--
-- NOTA:
--   No backfill: no existing boq.boq row today has a tracked source file.
--   Both columns are nullable so existing rows remain valid without a value.
-- =============================================================================

BEGIN;

ALTER TABLE boq.boq
    ADD COLUMN IF NOT EXISTS source_gcs_path TEXT,
    ADD COLUMN IF NOT EXISTS source_file_hash VARCHAR(64);

COMMIT;
