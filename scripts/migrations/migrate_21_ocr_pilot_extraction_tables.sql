-- =============================================================================
-- migrate_21_ocr_pilot_extraction_tables.sql
-- Schema: document - OCR pilot extraction run and candidate tables
--
-- COSA FA:
--   1. Creates document.extraction_run for OCR/LLM extraction executions.
--   2. Creates document.extraction_candidate for extracted logical documents.
--   3. Adds idempotency constraints, validation checks, indexes, and updated_at
--      triggers using tenant.update_updated_at().
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS document.extraction_run (
    extraction_run_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_ref_id UUID NOT NULL REFERENCES document.document_ref(document_ref_id),
    provider VARCHAR(100) NOT NULL,
    model_id VARCHAR(200) NOT NULL,
    extractor_profile VARCHAR(100) NOT NULL,
    prompt_version VARCHAR(50),
    prompt_hash VARCHAR(128) NOT NULL,
    schema_version VARCHAR(50) NOT NULL,
    source_hash VARCHAR(128) NOT NULL,
    idempotency_key VARCHAR(256) NOT NULL,
    status VARCHAR(30) NOT NULL
        CHECK (status IN ('pending', 'success', 'partial', 'failed')),
    raw_response_gcs_uri TEXT,
    provider_request_id VARCHAR(200),
    token_count_input INTEGER,
    token_count_output INTEGER,
    cost_estimate NUMERIC(18,6),
    latency_ms INTEGER,
    retry_count INTEGER NOT NULL DEFAULT 0,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_extraction_run_idempotency_key UNIQUE (idempotency_key),
    CONSTRAINT uq_extraction_run_semantic_config UNIQUE (
        document_ref_id,
        source_hash,
        extractor_profile,
        model_id,
        prompt_hash,
        schema_version
    ),
    CHECK (token_count_input IS NULL OR token_count_input >= 0),
    CHECK (token_count_output IS NULL OR token_count_output >= 0),
    CHECK (cost_estimate IS NULL OR cost_estimate >= 0),
    CHECK (latency_ms IS NULL OR latency_ms >= 0),
    CHECK (retry_count >= 0)
);

CREATE TABLE IF NOT EXISTS document.extraction_candidate (
    extraction_candidate_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    extraction_run_id UUID NOT NULL REFERENCES document.extraction_run(extraction_run_id),
    logical_document_type VARCHAR(100) NOT NULL,
    logical_document_index INTEGER NOT NULL,
    page_start INTEGER,
    page_end INTEGER,
    extracted_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    model_confidence NUMERIC,
    validation_status VARCHAR(30) NOT NULL DEFAULT 'pending'
        CHECK (validation_status IN ('pending', 'pass', 'warning', 'fail')),
    validation_flags JSONB NOT NULL DEFAULT '[]'::jsonb,
    review_status VARCHAR(30) NOT NULL DEFAULT 'pending'
        CHECK (review_status IN ('pending', 'approved', 'rejected')),
    corrected_payload JSONB,
    reviewed_by VARCHAR(255),
    reviewed_at TIMESTAMPTZ,
    review_notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_extraction_candidate_run_index
        UNIQUE (extraction_run_id, logical_document_index),
    CHECK (logical_document_index >= 0),
    CHECK (page_start IS NULL OR page_start >= 1),
    CHECK (page_end IS NULL OR page_end >= 1),
    CHECK (page_start IS NULL OR page_end IS NULL OR page_end >= page_start),
    CHECK (model_confidence IS NULL OR (model_confidence >= 0 AND model_confidence <= 1)),
    CHECK (reviewed_at IS NULL OR reviewed_by IS NOT NULL),
    CHECK (jsonb_typeof(extracted_payload) = 'object'),
    CHECK (jsonb_typeof(validation_flags) = 'array'),
    CHECK (corrected_payload IS NULL OR jsonb_typeof(corrected_payload) = 'object')
);

DROP TRIGGER IF EXISTS trg_extraction_run_updated_at ON document.extraction_run;
CREATE TRIGGER trg_extraction_run_updated_at
    BEFORE UPDATE ON document.extraction_run
    FOR EACH ROW EXECUTE FUNCTION tenant.update_updated_at();

DROP TRIGGER IF EXISTS trg_extraction_candidate_updated_at ON document.extraction_candidate;
CREATE TRIGGER trg_extraction_candidate_updated_at
    BEFORE UPDATE ON document.extraction_candidate
    FOR EACH ROW EXECUTE FUNCTION tenant.update_updated_at();

CREATE INDEX IF NOT EXISTS idx_extraction_run_document_ref
    ON document.extraction_run(document_ref_id);
CREATE INDEX IF NOT EXISTS idx_extraction_run_status
    ON document.extraction_run(status);
CREATE INDEX IF NOT EXISTS idx_extraction_run_created_at
    ON document.extraction_run(created_at);

CREATE INDEX IF NOT EXISTS idx_extraction_candidate_run
    ON document.extraction_candidate(extraction_run_id);
CREATE INDEX IF NOT EXISTS idx_extraction_candidate_validation_status
    ON document.extraction_candidate(validation_status);
CREATE INDEX IF NOT EXISTS idx_extraction_candidate_review_status
    ON document.extraction_candidate(review_status);
CREATE INDEX IF NOT EXISTS idx_extraction_candidate_logical_type
    ON document.extraction_candidate(logical_document_type);

COMMIT;
