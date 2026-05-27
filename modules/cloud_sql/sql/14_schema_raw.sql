-- =============================================================================
-- 14_schema_raw.sql
-- Schema: raw
--
-- MS-05 raw artifact index and ingestion audit layer.
-- The authoritative raw artifact remains in object storage (GCS/MinIO). This
-- schema stores technical indexing, parser status, idempotency, audit trail,
-- data-quality issues, and references to the original file/payload only.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS raw;

COMMENT ON SCHEMA raw IS 'MS-05 raw artifact index and ingestion audit layer. Raw files stay in object storage.';

GRANT USAGE ON SCHEMA raw TO bt_app;
GRANT USAGE ON SCHEMA raw TO bt_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA raw GRANT ALL PRIVILEGES ON TABLES TO bt_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA raw GRANT ALL PRIVILEGES ON SEQUENCES TO bt_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA raw GRANT SELECT ON TABLES TO bt_readonly;

-- =============================================================================
-- Raw artifact index
-- =============================================================================

CREATE TABLE IF NOT EXISTS raw.import_file (
    source_file_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               UUID,
    project_code            VARCHAR(50) NOT NULL,
    doc_type                VARCHAR(100) NOT NULL,
    file_profile            VARCHAR(100),
    source_system           VARCHAR(100),
    source_file_name        VARCHAR(255),
    source_file_path        TEXT NOT NULL,
    source_bucket           VARCHAR(255),
    source_file_hash        VARCHAR(64) NOT NULL,
    source_file_size_bytes  BIGINT,
    source_mime_type        VARCHAR(100),
    parser_name             VARCHAR(100),
    parser_version          VARCHAR(50),
    ingestion_status        VARCHAR(30) DEFAULT 'received',
    idempotency_key         VARCHAR(128) NOT NULL,
    rows_total              INTEGER,
    rows_parsed             INTEGER,
    rows_failed             INTEGER,
    dq_warnings             JSONB DEFAULT '[]'::jsonb,
    dq_errors               JSONB DEFAULT '[]'::jsonb,
    created_at              TIMESTAMPTZ DEFAULT NOW(),
    updated_at              TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_raw_import_file_idempotency UNIQUE (idempotency_key),
    CONSTRAINT ck_raw_import_file_source_file_hash_sha256
        CHECK (source_file_hash ~ '^[0-9A-Fa-f]{64}$')
);

COMMENT ON TABLE raw.import_file IS 'Technical index for raw source files stored in object storage.';

-- =============================================================================
-- Ingestion audit trail
-- =============================================================================

CREATE TABLE IF NOT EXISTS raw.ingestion_run (
    ingestion_run_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id      UUID REFERENCES raw.import_file(source_file_id),
    tenant_id           UUID,
    project_code        VARCHAR(50) NOT NULL,
    doc_type            VARCHAR(100) NOT NULL,
    file_profile        VARCHAR(100),
    parser_name         VARCHAR(100),
    parser_version      VARCHAR(50),
    run_status          VARCHAR(30) NOT NULL,
    started_at          TIMESTAMPTZ DEFAULT NOW(),
    completed_at        TIMESTAMPTZ,
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    rows_total          INTEGER,
    rows_parsed         INTEGER,
    rows_failed         INTEGER,
    error_summary       TEXT,
    dq_warnings         JSONB DEFAULT '[]'::jsonb,
    dq_errors           JSONB DEFAULT '[]'::jsonb
);

COMMENT ON TABLE raw.ingestion_run IS 'Audit trail for parser executions against raw source files.';

CREATE TABLE IF NOT EXISTS raw.ingestion_issue (
    issue_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ingestion_run_id    UUID REFERENCES raw.ingestion_run(ingestion_run_id),
    source_file_id      UUID REFERENCES raw.import_file(source_file_id),
    severity            VARCHAR(20) NOT NULL,
    issue_code          VARCHAR(100),
    issue_message       TEXT,
    source_sheet_name   VARCHAR(100),
    source_row_number   INTEGER,
    source_column_name  VARCHAR(100),
    raw_context_json    JSONB DEFAULT '{}'::jsonb,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE raw.ingestion_issue IS 'Structured parser and data-quality issues raised during ingestion.';

DROP TRIGGER IF EXISTS trg_raw_import_file_updated_at ON raw.import_file;
CREATE TRIGGER trg_raw_import_file_updated_at
    BEFORE UPDATE ON raw.import_file
    FOR EACH ROW EXECUTE FUNCTION tenant.update_updated_at();

DROP TRIGGER IF EXISTS trg_raw_ingestion_run_updated_at ON raw.ingestion_run;
CREATE TRIGGER trg_raw_ingestion_run_updated_at
    BEFORE UPDATE ON raw.ingestion_run
    FOR EACH ROW EXECUTE FUNCTION tenant.update_updated_at();

-- =============================================================================
-- Indexes
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_raw_import_file_project_doc_profile
    ON raw.import_file(project_code, doc_type, file_profile);
CREATE INDEX IF NOT EXISTS idx_raw_import_file_source_hash
    ON raw.import_file(source_file_hash);
CREATE INDEX IF NOT EXISTS idx_raw_import_file_idempotency_key
    ON raw.import_file(idempotency_key);
CREATE INDEX IF NOT EXISTS idx_raw_import_file_ingestion_status
    ON raw.import_file(ingestion_status);

CREATE INDEX IF NOT EXISTS idx_raw_ingestion_run_source_file
    ON raw.ingestion_run(source_file_id);
CREATE INDEX IF NOT EXISTS idx_raw_ingestion_run_project_doc_profile
    ON raw.ingestion_run(project_code, doc_type, file_profile);
CREATE INDEX IF NOT EXISTS idx_raw_ingestion_run_status
    ON raw.ingestion_run(run_status);

CREATE INDEX IF NOT EXISTS idx_raw_ingestion_issue_run
    ON raw.ingestion_issue(ingestion_run_id);
CREATE INDEX IF NOT EXISTS idx_raw_ingestion_issue_source_file
    ON raw.ingestion_issue(source_file_id);
CREATE INDEX IF NOT EXISTS idx_raw_ingestion_issue_severity
    ON raw.ingestion_issue(severity);

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA raw TO bt_app;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA raw TO bt_app;
GRANT SELECT ON ALL TABLES IN SCHEMA raw TO bt_readonly;
