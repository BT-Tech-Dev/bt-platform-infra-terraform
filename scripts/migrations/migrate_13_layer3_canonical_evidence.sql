-- DRAFT ONLY. DO NOT APPLY UNTIL THE CLEAN RELOAD PLAN IS APPROVED.
-- Destructively replaces conflicting Layer 3 and related legacy shapes.
-- MS-05 writes Layer 3 canonical evidence. Reconciliation writes Layer 4.

BEGIN;

DROP VIEW IF EXISTS quality.compression_tests;
DROP VIEW IF EXISTS production.pile_installations;
DROP VIEW IF EXISTS production.prefab_manufactured;
DROP VIEW IF EXISTS production.concrete_deliveries;

DROP TABLE IF EXISTS progress.evidence_link;
DROP TABLE IF EXISTS quality.quality_test_result;
DROP TABLE IF EXISTS quality.prefab_compression_test_result;
DROP TABLE IF EXISTS quality.quality_test_certificate;
DROP TABLE IF EXISTS document.acdat_sync_log;
DROP TABLE IF EXISTS production.prefab_manufactured_element;
DROP TABLE IF EXISTS production.production_record;
DROP TABLE IF EXISTS production.mix_recipe_component;
DROP TABLE IF EXISTS production.mix_recipe;
DROP TABLE IF EXISTS document.document_ref;

CREATE TABLE document.document_ref (
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

CREATE TABLE document.acdat_sync_log (
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

CREATE TABLE production.mix_recipe (
    mix_recipe_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant.company(id),
    project_code VARCHAR(50) NOT NULL,
    supplier_name VARCHAR(200),
    plant_id VARCHAR(100),
    recipe_code VARCHAR(100) NOT NULL,
    recipe_name VARCHAR(200),
    concrete_strength_class VARCHAR(50),
    exposure_class VARCHAR(100),
    consistency_class VARCHAR(50),
    max_aggregate_size_mm NUMERIC(10,3),
    water_cement_ratio NUMERIC(8,5),
    valid_from DATE,
    valid_to DATE,
    source_authority VARCHAR(50),
    source_file_id UUID REFERENCES raw.import_file(source_file_id),
    ingestion_run_id UUID REFERENCES raw.ingestion_run(ingestion_run_id),
    raw_record_id UUID,
    source_row_hash VARCHAR(128),
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
    UNIQUE (mix_recipe_id, tenant_id, project_code),
    UNIQUE (tenant_id, project_code, supplier_name, plant_id, recipe_code),
    CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from),
    CHECK (jsonb_typeof(dq_warnings) = 'array'),
    CHECK (jsonb_typeof(dq_errors) = 'array'),
    CHECK (jsonb_typeof(extra_fields) = 'object')
);

CREATE TABLE production.mix_recipe_component (
    mix_recipe_component_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant.company(id),
    project_code VARCHAR(50) NOT NULL,
    mix_recipe_id UUID NOT NULL,
    component_type VARCHAR(50) NOT NULL,
    component_code VARCHAR(100),
    component_name VARCHAR(200) NOT NULL,
    quantity NUMERIC(18,6),
    unit_of_measure VARCHAR(30),
    supplier_name VARCHAR(200),
    batch_tracking_required BOOLEAN NOT NULL DEFAULT FALSE,
    source_authority VARCHAR(50),
    source_file_id UUID REFERENCES raw.import_file(source_file_id),
    ingestion_run_id UUID REFERENCES raw.ingestion_run(ingestion_run_id),
    raw_record_id UUID,
    source_row_hash VARCHAR(128),
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
    FOREIGN KEY (mix_recipe_id, tenant_id, project_code)
        REFERENCES production.mix_recipe(mix_recipe_id, tenant_id, project_code),
    UNIQUE (mix_recipe_id, component_type, component_code, component_name),
    CHECK (quantity IS NULL OR quantity >= 0),
    CHECK (jsonb_typeof(dq_warnings) = 'array'),
    CHECK (jsonb_typeof(dq_errors) = 'array'),
    CHECK (jsonb_typeof(extra_fields) = 'object')
);

CREATE TABLE production.production_record (
    production_record_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant.company(id),
    project_code VARCHAR(50) NOT NULL,
    project_element_id UUID,
    event_type VARCHAR(100) NOT NULL,
    event_status VARCHAR(50),
    source_authority VARCHAR(50),
    event_date DATE,
    event_at TIMESTAMPTZ,
    quantity NUMERIC(18,6),
    unit_of_measure VARCHAR(30),
    supplier_name VARCHAR(200),
    plant_id VARCHAR(100),
    element_type VARCHAR(200),
    element_code VARCHAR(200),
    element_serial_number VARCHAR(200),
    order_number VARCHAR(100),
    lot_number VARCHAR(100),
    pile_number VARCHAR(100),
    panel_number VARCHAR(100),
    delivery_note_number VARCHAR(100),
    source_recipe_code VARCHAR(100),
    concrete_volume_actual_m3 NUMERIC(18,6),
    mix_recipe_id UUID,
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
    FOREIGN KEY (document_ref_id, tenant_id, project_code)
        REFERENCES document.document_ref(document_ref_id, tenant_id, project_code),
    UNIQUE (production_record_id, tenant_id, project_code),
    CHECK (quantity IS NULL OR quantity >= 0),
    CHECK (concrete_volume_actual_m3 IS NULL OR concrete_volume_actual_m3 >= 0),
    CHECK (jsonb_typeof(dq_warnings) = 'array'),
    CHECK (jsonb_typeof(dq_errors) = 'array'),
    CHECK (jsonb_typeof(extra_fields) = 'object')
);

CREATE TABLE quality.quality_test_certificate (
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

CREATE TABLE quality.quality_test_result (
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

COMMENT ON TABLE production.production_record IS
    'Canonical Layer 3 production evidence written by MS-05. Reconciliation writes Layer 4 evidence links; the SAL Engine reads progress.';
COMMENT ON TABLE quality.quality_test_result IS
    'Canonical Layer 3 quality evidence written by MS-05. Reconciliation writes Layer 4 evidence links; the SAL Engine reads progress.';

CREATE INDEX idx_document_ref_type_date
    ON document.document_ref(tenant_id, project_code, doc_type, document_date);
CREATE INDEX idx_document_ref_element
    ON document.document_ref(project_element_id);
CREATE UNIQUE INDEX uq_document_ref_source_row
    ON document.document_ref(source_file_id, source_row_hash)
    WHERE source_file_id IS NOT NULL AND source_row_hash IS NOT NULL;
CREATE UNIQUE INDEX uq_document_ref_source_document
    ON document.document_ref(tenant_id, project_code, doc_type, source_document_hash)
    WHERE source_document_hash IS NOT NULL AND source_row_hash IS NULL;
CREATE INDEX idx_acdat_sync_log_document
    ON document.acdat_sync_log(document_ref_id);
CREATE INDEX idx_mix_recipe_project_code
    ON production.mix_recipe(tenant_id, project_code, recipe_code);
CREATE INDEX idx_mix_recipe_component_recipe
    ON production.mix_recipe_component(mix_recipe_id);
CREATE INDEX idx_production_record_type_date
    ON production.production_record(tenant_id, project_code, event_type, event_date);
CREATE INDEX idx_production_record_element
    ON production.production_record(project_element_id);
CREATE UNIQUE INDEX uq_production_record_source_row
    ON production.production_record(source_file_id, source_row_hash)
    WHERE source_file_id IS NOT NULL AND source_row_hash IS NOT NULL;
CREATE INDEX idx_production_record_match_candidates
    ON production.production_record(
        tenant_id, project_code, pile_number, panel_number, element_serial_number, element_code
    );
CREATE INDEX idx_quality_test_result_type_date
    ON quality.quality_test_result(tenant_id, project_code, test_type, test_date);
CREATE INDEX idx_quality_test_result_element
    ON quality.quality_test_result(project_element_id);
CREATE UNIQUE INDEX uq_quality_test_result_source_row
    ON quality.quality_test_result(source_file_id, source_row_hash)
    WHERE source_file_id IS NOT NULL AND source_row_hash IS NOT NULL;
CREATE INDEX idx_quality_certificate_work_progress
    ON quality.quality_test_certificate(work_progress_id);

CREATE VIEW production.prefab_manufactured AS
SELECT production_record_id AS prefab_manufactured_id, tenant_id, project_code,
       project_element_id, event_status AS manufacturing_status, source_authority,
       event_date AS production_date, element_type, element_code,
       element_serial_number, order_number, lot_number, quantity, unit_of_measure,
       supplier_name, mix_recipe_id, dq_status, extra_fields
FROM production.production_record
WHERE event_type = 'prefab_manufactured';

CREATE VIEW production.pile_installations AS
SELECT production_record_id AS pile_installation_id, tenant_id, project_code,
       project_element_id, event_status AS installation_status, source_authority,
       event_date AS installation_date, event_at AS installed_at, pile_number,
       element_type AS pile_type, quantity, unit_of_measure, supplier_name,
       document_ref_id, dq_status, extra_fields
FROM production.production_record
WHERE event_type = 'pile_installed';

CREATE VIEW production.concrete_deliveries AS
SELECT production_record_id AS concrete_delivery_id, tenant_id, project_code,
       project_element_id, event_status AS delivery_status, source_authority,
       event_date AS delivery_date, event_at AS delivered_at, delivery_note_number,
       supplier_name, plant_id, source_recipe_code, concrete_volume_actual_m3,
       mix_recipe_id, document_ref_id, dq_status, extra_fields
FROM production.production_record
WHERE event_type = 'concrete_delivery';

CREATE VIEW quality.compression_tests AS
SELECT quality_test_result_id AS compression_test_id, tenant_id, project_code,
       project_element_id, test_status, source_authority, test_date,
       production_date, supplier_name, plant_id, specimen_id, specimen_sequence,
       lot_number, control_type, curing_days, dimensions_text, length_cm, width_cm,
       height_cm, weight_kg, compressive_strength_n_mm2, average_strength_n_mm2,
       mix_recipe_id, related_production_record_id, document_ref_id, dq_status,
       extra_fields
FROM quality.quality_test_result
WHERE test_type = 'compression_28d';

COMMIT;
