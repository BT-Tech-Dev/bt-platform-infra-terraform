-- =============================================================================
-- 08_schema_quality.sql
-- Schema: quality
--
-- Canonical Layer 3 quality evidence plus SAL quality controls.
-- MS-05 writes Layer 3 canonical evidence. Reconciliation writes Layer 4
-- evidence links. The SAL Engine reads Layer 4/progress, not raw parser output.
-- =============================================================================

CREATE TABLE IF NOT EXISTS quality.quality_test_certificate (
    quality_test_certificate_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant.company(id),
    project_code VARCHAR(50) NOT NULL,
    work_progress_id UUID NOT NULL REFERENCES progress.work_progress(id),
    mix_recipe_id UUID,
    test_type VARCHAR(100) NOT NULL,
    sample_date DATE,
    test_date DATE,
    laboratory_name VARCHAR(255),
    standard_ref VARCHAR(100),
    result_value NUMERIC(15,4),
    result_unit VARCHAR(20),
    outcome VARCHAR(10) NOT NULL DEFAULT 'PENDING'
        CHECK (outcome IN ('PASS', 'FAIL', 'PENDING', 'VOID')),
    document_ref_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    FOREIGN KEY (mix_recipe_id, tenant_id, project_code)
        REFERENCES production.mix_recipe(mix_recipe_id, tenant_id, project_code),
    FOREIGN KEY (document_ref_id, tenant_id, project_code)
        REFERENCES document.document_ref(document_ref_id, tenant_id, project_code)
);

CREATE TABLE IF NOT EXISTS quality.non_conformity (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant.company(id),
    work_progress_id UUID NOT NULL REFERENCES progress.work_progress(id),
    detected_date DATE NOT NULL DEFAULT CURRENT_DATE,
    deadline_date DATE,
    severity VARCHAR(10) NOT NULL DEFAULT 'Minor'
        CHECK (severity IN ('Minor', 'Major', 'Critical')),
    description TEXT NOT NULL,
    root_cause TEXT,
    blocks_sal BOOLEAN NOT NULL DEFAULT FALSE,
    status VARCHAR(20) NOT NULL DEFAULT 'Open'
        CHECK (status IN ('Open', 'InProgress', 'Closed', 'Waived')),
    corrective_action TEXT,
    closed_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS quality.quality_test_result (
    quality_test_result_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant.company(id),
    project_code VARCHAR(50) NOT NULL,
    project_element_id UUID,
    test_type VARCHAR(100) NOT NULL,
    test_status VARCHAR(50),
    source_authority VARCHAR(50),
    test_date DATE,
    production_date DATE,
    supplier_name VARCHAR(200),
    plant_id VARCHAR(100),
    specimen_id VARCHAR(100),
    specimen_sequence INTEGER,
    lot_number VARCHAR(100),
    control_type VARCHAR(100),
    curing_days INTEGER,
    dimensions_text VARCHAR(200),
    length_cm NUMERIC(12,4),
    width_cm NUMERIC(12,4),
    height_cm NUMERIC(12,4),
    weight_kg NUMERIC(18,6),
    compressive_strength_n_mm2 NUMERIC(18,6),
    average_strength_n_mm2 NUMERIC(18,6),
    mix_recipe_id UUID,
    related_production_record_id UUID,
    document_ref_id UUID,
    source_file_id UUID REFERENCES raw.import_file(source_file_id),
    ingestion_run_id UUID REFERENCES raw.ingestion_run(ingestion_run_id),
    raw_record_id UUID,
    source_row_hash VARCHAR(128),
    source_sheet_name VARCHAR(200),
    source_row_number INTEGER,
    file_profile VARCHAR(100),
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
    FOREIGN KEY (mix_recipe_id, tenant_id, project_code)
        REFERENCES production.mix_recipe(mix_recipe_id, tenant_id, project_code),
    FOREIGN KEY (related_production_record_id, tenant_id, project_code)
        REFERENCES production.production_record(production_record_id, tenant_id, project_code),
    FOREIGN KEY (document_ref_id, tenant_id, project_code)
        REFERENCES document.document_ref(document_ref_id, tenant_id, project_code),
    UNIQUE (quality_test_result_id, tenant_id, project_code),
    CHECK (specimen_sequence IS NULL OR specimen_sequence > 0),
    CHECK (curing_days IS NULL OR curing_days >= 0),
    CHECK (weight_kg IS NULL OR weight_kg >= 0),
    CHECK (jsonb_typeof(dq_warnings) = 'array'),
    CHECK (jsonb_typeof(dq_errors) = 'array'),
    CHECK (jsonb_typeof(extra_fields) = 'object')
);

COMMENT ON TABLE quality.quality_test_result IS
    'Canonical Layer 3 quality evidence written by MS-05. Reconciliation writes Layer 4 evidence links; the SAL Engine reads progress, not this raw parser output directly.';
COMMENT ON COLUMN quality.quality_test_result.project_element_id IS
    'Nullable until Layer 4 reconciliation confirms a canonical project element match.';
COMMENT ON COLUMN quality.quality_test_result.raw_record_id IS
    'Nullable source record identifier. TODO: add an FK when a canonical raw-record table exists.';

CREATE INDEX IF NOT EXISTS idx_quality_certificate_work_progress
    ON quality.quality_test_certificate(work_progress_id);
CREATE INDEX IF NOT EXISTS idx_quality_non_conformity_work_progress
    ON quality.non_conformity(work_progress_id);
CREATE INDEX IF NOT EXISTS idx_quality_non_conformity_blocks_sal
    ON quality.non_conformity(tenant_id, blocks_sal, status)
    WHERE blocks_sal = TRUE AND status NOT IN ('Closed', 'Waived');
CREATE INDEX IF NOT EXISTS idx_quality_test_result_type_date
    ON quality.quality_test_result(tenant_id, project_code, test_type, test_date);
CREATE INDEX IF NOT EXISTS idx_quality_test_result_element
    ON quality.quality_test_result(project_element_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_quality_test_result_source_row
    ON quality.quality_test_result(source_file_id, source_row_hash)
    WHERE source_file_id IS NOT NULL AND source_row_hash IS NOT NULL;

CREATE OR REPLACE VIEW quality.compression_tests AS
SELECT
    quality_test_result_id AS compression_test_id,
    tenant_id,
    project_code,
    project_element_id,
    test_status,
    source_authority,
    test_date,
    production_date,
    supplier_name,
    plant_id,
    specimen_id,
    specimen_sequence,
    lot_number,
    control_type,
    curing_days,
    dimensions_text,
    length_cm,
    width_cm,
    height_cm,
    weight_kg,
    compressive_strength_n_mm2,
    average_strength_n_mm2,
    mix_recipe_id,
    related_production_record_id,
    document_ref_id,
    dq_status,
    extra_fields
FROM quality.quality_test_result
WHERE test_type = 'compression_28d';
