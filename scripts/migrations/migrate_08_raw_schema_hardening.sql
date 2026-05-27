-- =============================================================================
-- migrate_08_raw_schema_hardening.sql
-- Schema: raw - hardens MS-05 raw artifact index constraints
--
-- COSA FA:
--   1. Fails clearly if existing raw.import_file rows have NULL idempotency_key
--      or NULL/invalid source_file_hash.
--   2. Fails clearly if duplicate non-null idempotency_key values exist.
--   3. Adds/repairs the unique constraint on raw.import_file.idempotency_key.
--   4. Makes raw.import_file.idempotency_key and source_file_hash NOT NULL.
--   5. Adds a SHA-256 hex CHECK on raw.import_file.source_file_hash.
--   6. Adds updated_at maintenance triggers on raw.import_file and
--      raw.ingestion_run using the existing tenant.update_updated_at() pattern.
-- =============================================================================

BEGIN;

DO $$
BEGIN
    IF to_regprocedure('tenant.update_updated_at()') IS NULL THEN
        RAISE EXCEPTION
            'Cannot harden raw schema: required trigger function tenant.update_updated_at() does not exist';
    END IF;
END $$;

DO $$
DECLARE
    null_idempotency_count BIGINT;
    duplicate_key_count    BIGINT;
    null_hash_count        BIGINT;
    invalid_hash_count     BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO null_idempotency_count
    FROM raw.import_file
    WHERE idempotency_key IS NULL;

    IF null_idempotency_count > 0 THEN
        RAISE EXCEPTION
            'Cannot set raw.import_file.idempotency_key NOT NULL: % rows have NULL idempotency_key',
            null_idempotency_count;
    END IF;

    SELECT COUNT(*)
    INTO duplicate_key_count
    FROM (
        SELECT idempotency_key
        FROM raw.import_file
        WHERE idempotency_key IS NOT NULL
        GROUP BY idempotency_key
        HAVING COUNT(*) > 1
    ) duplicate_keys;

    IF duplicate_key_count > 0 THEN
        RAISE EXCEPTION
            'Cannot add uq_raw_import_file_idempotency: duplicate idempotency_key values exist.';
    END IF;

    SELECT COUNT(*)
    INTO null_hash_count
    FROM raw.import_file
    WHERE source_file_hash IS NULL;

    IF null_hash_count > 0 THEN
        RAISE EXCEPTION
            'Cannot set raw.import_file.source_file_hash NOT NULL: % rows have NULL source_file_hash',
            null_hash_count;
    END IF;

    SELECT COUNT(*)
    INTO invalid_hash_count
    FROM raw.import_file
    WHERE source_file_hash !~ '^[0-9A-Fa-f]{64}$';

    IF invalid_hash_count > 0 THEN
        RAISE EXCEPTION
            'Cannot add raw.import_file.source_file_hash SHA-256 CHECK: % rows have non-hex or non-64-character source_file_hash',
            invalid_hash_count;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'raw.import_file'::regclass
          AND conname = 'uq_raw_import_file_idempotency'
    ) THEN
        ALTER TABLE raw.import_file
            ADD CONSTRAINT uq_raw_import_file_idempotency UNIQUE (idempotency_key);
    END IF;
END $$;

ALTER TABLE raw.import_file
    ALTER COLUMN idempotency_key SET NOT NULL,
    ALTER COLUMN source_file_hash SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'raw.import_file'::regclass
          AND conname = 'ck_raw_import_file_source_file_hash_sha256'
    ) THEN
        ALTER TABLE raw.import_file
            ADD CONSTRAINT ck_raw_import_file_source_file_hash_sha256
            CHECK (source_file_hash ~ '^[0-9A-Fa-f]{64}$');
    END IF;
END $$;

ALTER TABLE raw.ingestion_run
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

UPDATE raw.ingestion_run
SET updated_at = NOW()
WHERE updated_at IS NULL;

DROP TRIGGER IF EXISTS trg_raw_import_file_updated_at ON raw.import_file;
CREATE TRIGGER trg_raw_import_file_updated_at
    BEFORE UPDATE ON raw.import_file
    FOR EACH ROW EXECUTE FUNCTION tenant.update_updated_at();

DROP TRIGGER IF EXISTS trg_raw_ingestion_run_updated_at ON raw.ingestion_run;
CREATE TRIGGER trg_raw_ingestion_run_updated_at
    BEFORE UPDATE ON raw.ingestion_run
    FOR EACH ROW EXECUTE FUNCTION tenant.update_updated_at();

COMMIT;
