-- =============================================================================
-- 09_schema_document.sql
-- Schema: document
--
-- Canonical Layer 3 document evidence. MS-05 writes Layer 3 canonical evidence.
-- Reconciliation writes Layer 4 evidence links in progress.
-- =============================================================================

CREATE TABLE IF NOT EXISTS document.document_ref (
    document_ref_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant.company(id),
    project_code VARCHAR(50) NOT NULL,
    project_element_id UUID,
    doc_type VARCHAR(100) NOT NULL,
    document_number VARCHAR(200),
    title VARCHAR(500),
    issuer_name VARCHAR(200),
    recipient_name VARCHAR(200),
    document_date DATE,
    revision VARCHAR(50),
    status VARCHAR(50),
    source_authority VARCHAR(50),
    source_uri TEXT,
    source_document_hash VARCHAR(128),
    source_file_id UUID REFERENCES raw.import_file(source_file_id),
    ingestion_run_id UUID REFERENCES raw.ingestion_run(ingestion_run_id),
    raw_record_id UUID,
    source_row_hash VARCHAR(128),
    source_sheet_name VARCHAR(200),
    source_row_number INTEGER,
    parser_name VARCHAR(100),
    parser_version VARCHAR(50),
    dq_status VARCHAR(30) NOT NULL DEFAULT 'OK',
    dq_warnings JSONB NOT NULL DEFAULT '[]'::jsonb,
    dq_errors JSONB NOT NULL DEFAULT '[]'::jsonb,
    extra_fields JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    FOREIGN KEY (project_element_id, tenant_id, project_code)
        REFERENCES bim.project_element_registry(project_element_id, tenant_id, project_code),
    UNIQUE (document_ref_id, tenant_id, project_code),
    CHECK (jsonb_typeof(dq_warnings) = 'array'),
    CHECK (jsonb_typeof(dq_errors) = 'array'),
    CHECK (jsonb_typeof(extra_fields) = 'object')
);

COMMENT ON TABLE document.document_ref IS
    'Canonical Layer 3 document evidence written by MS-05. Reconciliation writes Layer 4 evidence links.';
COMMENT ON COLUMN document.document_ref.project_element_id IS
    'Nullable until Layer 4 reconciliation confirms a canonical project element match.';
COMMENT ON COLUMN document.document_ref.source_row_hash IS
    'Nullable for document-level sources without a stable row concept.';
COMMENT ON COLUMN document.document_ref.raw_record_id IS
    'Nullable source record identifier. TODO: add an FK when a canonical raw-record table exists.';

CREATE TABLE IF NOT EXISTS document.acdat_sync_log (
    acdat_sync_log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant.company(id),
    project_code VARCHAR(50) NOT NULL,
    document_ref_id UUID,
    acdat_document_id VARCHAR(255),
    direction VARCHAR(10) NOT NULL CHECK (direction IN ('INBOUND', 'OUTBOUND')),
    operation_type VARCHAR(20) NOT NULL
        CHECK (operation_type IN ('CREATE', 'UPDATE', 'DELETE', 'DOWNLOAD', 'STATUS_CHECK')),
    status VARCHAR(10) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('SUCCESS', 'FAILED', 'PENDING')),
    request_payload JSONB,
    response_payload JSONB,
    error_message TEXT,
    synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    FOREIGN KEY (document_ref_id, tenant_id, project_code)
        REFERENCES document.document_ref(document_ref_id, tenant_id, project_code)
);

CREATE INDEX IF NOT EXISTS idx_document_ref_type_date
    ON document.document_ref(tenant_id, project_code, doc_type, document_date);
CREATE INDEX IF NOT EXISTS idx_document_ref_element
    ON document.document_ref(project_element_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_document_ref_source_row
    ON document.document_ref(source_file_id, source_row_hash)
    WHERE source_file_id IS NOT NULL AND source_row_hash IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_document_ref_source_document
    ON document.document_ref(tenant_id, project_code, doc_type, source_document_hash)
    WHERE source_document_hash IS NOT NULL AND source_row_hash IS NULL;
CREATE INDEX IF NOT EXISTS idx_acdat_sync_log_document
    ON document.acdat_sync_log(document_ref_id);
