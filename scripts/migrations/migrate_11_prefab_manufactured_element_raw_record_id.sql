-- =============================================================================
-- migrate_11_prefab_manufactured_element_raw_record_id.sql
-- Schema: production - adds parsed row lineage to Moretti prefab elements
--
-- COSA FA:
--   1. Adds production.prefab_manufactured_element.raw_record_id.
-- =============================================================================

BEGIN;

ALTER TABLE production.prefab_manufactured_element
    ADD COLUMN IF NOT EXISTS raw_record_id UUID;

COMMIT;
