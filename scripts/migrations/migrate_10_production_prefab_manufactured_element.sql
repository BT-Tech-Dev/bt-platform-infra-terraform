-- =============================================================================
-- migrate_10_production_prefab_manufactured_element.sql
-- Schema: production - MS-05 Moretti prefab manufactured element domain table
--
-- COSA FA:
--   1. Creates production.prefab_manufactured_element.
--   2. Links normalized/domain rows to raw.import_file and raw.ingestion_run.
--   3. Adds idempotency constraints, query indexes, and updated_at trigger.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS production.prefab_manufactured_element (
    prefab_manufactured_element_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                      UUID NOT NULL,
    project_code                   VARCHAR NOT NULL,
    source_file_id                 UUID NOT NULL REFERENCES raw.import_file(source_file_id),
    ingestion_run_id               UUID NOT NULL REFERENCES raw.ingestion_run(ingestion_run_id),
    raw_record_id                  UUID,
    source_row_hash                VARCHAR(64) NOT NULL,
    source_sheet_name              VARCHAR,
    source_row_number              INTEGER NOT NULL,
    file_profile                   VARCHAR NOT NULL,
    parser_name                    VARCHAR NOT NULL,
    parser_version                 VARCHAR NOT NULL,

    element_code                   VARCHAR NOT NULL,
    element_serial_number          VARCHAR,
    order_number                   VARCHAR,
    order_status_code              VARCHAR,
    department_code                VARCHAR,
    customer_name                  VARCHAR,
    quantity                       NUMERIC,
    unit_of_measure                VARCHAR,
    length_m                       NUMERIC,
    width_m                        NUMERIC,
    height_m                       NUMERIC,
    volume_m3                      NUMERIC,
    weight_kg                      NUMERIC,
    mould_id                       VARCHAR,
    mould_description              VARCHAR,
    rck                            VARCHAR,
    exposure_class                 VARCHAR,
    fire_resistance                VARCHAR,
    recipe_id                      VARCHAR,
    element_type                   VARCHAR,
    production_date                DATE,
    storage_date                   DATE,
    planned_date                   DATE,
    completed_quantity             NUMERIC,

    dq_status                      VARCHAR NOT NULL DEFAULT 'OK',
    dq_warnings                    JSONB NOT NULL DEFAULT '[]'::jsonb,
    dq_errors                      JSONB NOT NULL DEFAULT '[]'::jsonb,
    extra_fields                   JSONB NOT NULL DEFAULT '{}'::jsonb,
    raw_payload_json               JSONB NOT NULL,
    created_at                     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_prefab_manufactured_element_file_row_hash
        UNIQUE (source_file_id, source_row_hash),
    CONSTRAINT uq_prefab_manufactured_element_source_row
        UNIQUE NULLS NOT DISTINCT (source_file_id, source_sheet_name, source_row_number)
);

ALTER TABLE production.prefab_manufactured_element
    DROP CONSTRAINT IF EXISTS uq_prefab_manufactured_element_source_row_hash;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'production.prefab_manufactured_element'::regclass
          AND conname = 'uq_prefab_manufactured_element_file_row_hash'
    ) THEN
        ALTER TABLE production.prefab_manufactured_element
            ADD CONSTRAINT uq_prefab_manufactured_element_file_row_hash
            UNIQUE (source_file_id, source_row_hash);
    END IF;
END $$;

COMMENT ON TABLE production.prefab_manufactured_element IS 'MS-05 normalized/domain table for Moretti prefabricated manufactured elements.';
COMMENT ON COLUMN production.prefab_manufactured_element.source_file_id IS 'Raw artifact index reference in raw.import_file.';
COMMENT ON COLUMN production.prefab_manufactured_element.ingestion_run_id IS 'Parser execution audit reference in raw.ingestion_run.';

DROP TRIGGER IF EXISTS trg_prefab_manufactured_element_updated_at ON production.prefab_manufactured_element;
CREATE TRIGGER trg_prefab_manufactured_element_updated_at
    BEFORE UPDATE ON production.prefab_manufactured_element
    FOR EACH ROW EXECUTE FUNCTION tenant.update_updated_at();

CREATE INDEX IF NOT EXISTS idx_prod_prefab_project_element
    ON production.prefab_manufactured_element(project_code, element_code);
CREATE INDEX IF NOT EXISTS idx_prod_prefab_project_serial
    ON production.prefab_manufactured_element(project_code, element_serial_number);
CREATE INDEX IF NOT EXISTS idx_prod_prefab_project_planned
    ON production.prefab_manufactured_element(project_code, planned_date);
CREATE INDEX IF NOT EXISTS idx_prod_prefab_source_file
    ON production.prefab_manufactured_element(source_file_id);
CREATE INDEX IF NOT EXISTS idx_prod_prefab_ingestion_run
    ON production.prefab_manufactured_element(ingestion_run_id);

COMMIT;
