-- =============================================================================
-- migrate_12_prefab_manufactured_element_raw_payload_nullable.sql
-- Schema: production - makes raw_payload_json optional for normalized prefab rows
--
-- COSA FA:
--   1. Drops NOT NULL from production.prefab_manufactured_element.raw_payload_json.
-- =============================================================================

BEGIN;

ALTER TABLE production.prefab_manufactured_element
    ALTER COLUMN raw_payload_json DROP NOT NULL;

COMMIT;
