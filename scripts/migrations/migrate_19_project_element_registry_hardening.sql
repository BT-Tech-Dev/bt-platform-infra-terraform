-- =============================================================================
-- migrate_19_project_element_registry_hardening.sql
-- Schema: bim - Layer 1 project element registry hardening for MS-01
--
-- DRAFT ONLY. DO NOT APPLY UNTIL REVIEWED.
--
-- Scope:
--   - Only bim.project_element_registry.
--   - Does not touch Layer 0 catalog tables.
--   - Does not touch bim.bim_element, production, quality, progress, SAL,
--     reconciliation, or classifier rule tables.
--
-- Notes:
--   canonical_element_code remains NOT NULL and has no database default.
--   MS-01 must populate it explicitly. It is a display/log/report code, not
--   the primary matching key. Matching should use bim.project_element_identifier.
-- =============================================================================

BEGIN;

ALTER TABLE bim.project_element_registry
    ADD COLUMN IF NOT EXISTS is_synthetic BOOLEAN DEFAULT FALSE;

UPDATE bim.project_element_registry
SET is_synthetic = FALSE
WHERE is_synthetic IS NULL;

ALTER TABLE bim.project_element_registry
    ALTER COLUMN is_synthetic SET DEFAULT FALSE,
    ALTER COLUMN is_synthetic SET NOT NULL;

COMMENT ON COLUMN bim.project_element_registry.is_synthetic IS
    'FALSE = project element is backed by BIM or normal source data. TRUE = project element was created before BIM existed or without direct BIM backing, for example from production, supplier, or document data.';

ALTER TABLE bim.project_element_registry
    ADD COLUMN IF NOT EXISTS source_system VARCHAR(30) DEFAULT 'BIM';

UPDATE bim.project_element_registry
SET source_system = 'BIM'
WHERE source_system IS NULL;

-- One-time normalization for existing registry rows created by reconciliation
-- before Layer 1 BIM backing existed. Keep all other existing rows at the BIM
-- default.
UPDATE bim.project_element_registry AS registry
SET is_synthetic = TRUE,
    source_system = 'RECONCILIATION'
WHERE registry.bim_element_id IS NULL
  AND EXISTS (
      SELECT 1
      FROM bim.project_element_identifier AS identifier
      WHERE identifier.project_element_id = registry.project_element_id
        AND identifier.tenant_id = registry.tenant_id
        AND identifier.project_code = registry.project_code
        AND identifier.source_system ILIKE 'RECONCILIATION%'
  );

ALTER TABLE bim.project_element_registry
    ALTER COLUMN source_system SET DEFAULT 'BIM',
    ALTER COLUMN source_system SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'bim.project_element_registry'::regclass
          AND conname = 'ck_project_element_registry_source_system'
    ) THEN
        ALTER TABLE bim.project_element_registry
            ADD CONSTRAINT ck_project_element_registry_source_system
            CHECK (source_system IN ('BIM', 'SYNTHETIC', 'MANUAL', 'RECONCILIATION'));
    END IF;
END$$;

COMMENT ON COLUMN bim.project_element_registry.source_system IS
    'Origin of the Layer 1 project element registry row: BIM, SYNTHETIC, MANUAL, or RECONCILIATION.';

-- source_system is expected to be a common operational filter for MS-01,
-- reconciliation review, and synthetic/manual element audits. is_synthetic is
-- deliberately not indexed separately because it is low-cardinality and covered
-- by source_system for the expected review workflows.
CREATE INDEX IF NOT EXISTS idx_project_element_registry_source_system
    ON bim.project_element_registry(tenant_id, project_code, source_system);

-- Existing rows default to source_system = 'BIM'. Rows without BIM backing and
-- with reconciliation identifiers are normalized to source_system =
-- 'RECONCILIATION' and is_synthetic = TRUE.

COMMIT;

-- =============================================================================
-- Validation queries
-- =============================================================================

-- Confirm columns exist.
-- SELECT column_name, data_type, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_schema = 'bim'
--   AND table_name = 'project_element_registry'
--   AND column_name IN ('is_synthetic', 'source_system', 'canonical_element_code')
-- ORDER BY column_name;

-- Confirm no NULLs.
-- SELECT
--     COUNT(*) FILTER (WHERE is_synthetic IS NULL) AS null_is_synthetic,
--     COUNT(*) FILTER (WHERE source_system IS NULL) AS null_source_system
-- FROM bim.project_element_registry;

-- Confirm CHECK constraint exists.
-- SELECT conname, pg_get_constraintdef(oid) AS definition
-- FROM pg_constraint
-- WHERE conrelid = 'bim.project_element_registry'::regclass
--   AND conname = 'ck_project_element_registry_source_system';

-- Count rows by source_system and is_synthetic.
-- SELECT source_system, is_synthetic, COUNT(*) AS row_count
-- FROM bim.project_element_registry
-- GROUP BY source_system, is_synthetic
-- ORDER BY source_system, is_synthetic;

-- List BIM-default rows without BIM backing for manual review.
-- SELECT project_element_id, tenant_id, project_code, canonical_element_code,
--        element_name, source_system, is_synthetic
-- FROM bim.project_element_registry
-- WHERE source_system = 'BIM'
--   AND bim_element_id IS NULL
-- ORDER BY tenant_id, project_code, canonical_element_code;

-- Confirm canonical_element_code still NOT NULL and has no default.
-- SELECT column_name, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_schema = 'bim'
--   AND table_name = 'project_element_registry'
--   AND column_name = 'canonical_element_code';
