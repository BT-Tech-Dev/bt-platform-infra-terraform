-- =============================================================================
-- migrate_11_quality_prefab_compression_test_result.sql
-- Schema: quality - MS-05 prefab concrete compression test results
--
-- COSA FA:
--   1. Creates quality.prefab_compression_test_result.
--   2. Links normalized/domain rows to raw.import_file and raw.ingestion_run.
--   3. Adds idempotency constraints, query indexes, and updated_at trigger.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS quality.prefab_compression_test_result (
    prefab_compression_test_result_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                         UUID NOT NULL REFERENCES tenant.company(id),
    project_code                      VARCHAR NOT NULL,
    source_file_id                    UUID NOT NULL REFERENCES raw.import_file(source_file_id),
    ingestion_run_id                  UUID NOT NULL REFERENCES raw.ingestion_run(ingestion_run_id),
    raw_record_id                     UUID,
    source_row_hash                   VARCHAR(64) NOT NULL,
    source_sheet_name                 VARCHAR,
    source_row_number                 INTEGER NOT NULL,
    file_profile                      VARCHAR NOT NULL,
    parser_name                       VARCHAR NOT NULL,
    parser_version                    VARCHAR NOT NULL,

    supplier_name                     VARCHAR,
    register_year                     INTEGER,
    control_type                      VARCHAR,
    specimen_sequence                 INTEGER,
    production_date                   DATE,
    test_date                         DATE,
    curing_days                       INTEGER,
    weight_kg                         NUMERIC,
    dimensions_text                   VARCHAR,
    length_cm                         NUMERIC,
    width_cm                          NUMERIC,
    height_cm                         NUMERIC,
    cement_type                       VARCHAR,
    compressive_strength_n_mm2        NUMERIC,
    average_strength_n_mm2            NUMERIC,
    test_status                       VARCHAR,
    steel_batch_text                  TEXT,
    prefab_types_text                 TEXT,

    dq_status                         VARCHAR NOT NULL DEFAULT 'OK',
    dq_warnings                       JSONB NOT NULL DEFAULT '[]'::jsonb,
    dq_errors                         JSONB NOT NULL DEFAULT '[]'::jsonb,
    extra_fields                      JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at                        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_prefab_compression_test_result_file_row_hash
        UNIQUE (source_file_id, source_row_hash),
    CONSTRAINT uq_prefab_compression_test_result_source_row
        UNIQUE NULLS NOT DISTINCT (source_file_id, source_sheet_name, source_row_number)
);

COMMENT ON TABLE quality.prefab_compression_test_result IS 'MS-05 normalized/domain table for prefab concrete compression test register rows.';
COMMENT ON COLUMN quality.prefab_compression_test_result.source_file_id IS 'Raw artifact index reference in raw.import_file.';
COMMENT ON COLUMN quality.prefab_compression_test_result.ingestion_run_id IS 'Parser execution audit reference in raw.ingestion_run.';

DROP TRIGGER IF EXISTS trg_prefab_compression_test_result_updated_at ON quality.prefab_compression_test_result;
CREATE TRIGGER trg_prefab_compression_test_result_updated_at
    BEFORE UPDATE ON quality.prefab_compression_test_result
    FOR EACH ROW EXECUTE FUNCTION tenant.update_updated_at();

CREATE INDEX IF NOT EXISTS idx_qual_prefab_comp_project_production_date
    ON quality.prefab_compression_test_result(project_code, production_date);
CREATE INDEX IF NOT EXISTS idx_qual_prefab_comp_project_test_date
    ON quality.prefab_compression_test_result(project_code, test_date);
CREATE INDEX IF NOT EXISTS idx_qual_prefab_comp_project_test_status
    ON quality.prefab_compression_test_result(project_code, test_status);
CREATE INDEX IF NOT EXISTS idx_qual_prefab_comp_source_file
    ON quality.prefab_compression_test_result(source_file_id);
CREATE INDEX IF NOT EXISTS idx_qual_prefab_comp_ingestion_run
    ON quality.prefab_compression_test_result(ingestion_run_id);
CREATE INDEX IF NOT EXISTS idx_qual_prefab_comp_steel_batch_text
    ON quality.prefab_compression_test_result(steel_batch_text);

COMMIT;
