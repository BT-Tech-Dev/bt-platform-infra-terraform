-- MANUAL CLOUD SQL STUDIO APPLY BUNDLE: CLEAN MIGRATIONS 12-14
-- DESTRUCTIVE. BACK UP THE DATABASE AND STOP ALL WRITERS BEFORE USE.
-- This bundle contains the reviewed migration files unchanged, with their
-- independent BEGIN/COMMIT transaction boundaries preserved.
-- Prefer running each migration section one at a time in Cloud SQL Studio.

-- =============================================================================
-- MIGRATION 12: CATALOG AND PROJECT ELEMENT REGISTRY
-- Source: scripts/migrations/migrate_12_bim_catalog_project_element_registry.sql
-- =============================================================================
-- DRAFT ONLY. DO NOT APPLY UNTIL THE CLEAN RELOAD PLAN IS APPROVED.
-- Destructively replaces catalog Layer 0 and BIM Layer 1 canonical identity tables.
-- Known downstream Layer 3/4 tables are removed here and recreated by
-- migrations 13 and 14; the three drafts must be treated as one transition.

BEGIN;

CREATE SCHEMA IF NOT EXISTS catalog;

-- Remove known downstream draft dependencies before replacing catalog Layer 0 and BIM Layer 1.
DROP VIEW IF EXISTS quality.compression_tests;
DROP VIEW IF EXISTS production.pile_installations;
DROP VIEW IF EXISTS production.prefab_manufactured;
DROP VIEW IF EXISTS production.concrete_deliveries;
DROP TABLE IF EXISTS progress.evidence_link;
DROP TABLE IF EXISTS progress.progress_derivation_rule;
DROP TABLE IF EXISTS quality.quality_test_result;
DROP TABLE IF EXISTS quality.prefab_compression_test_result;
DROP TABLE IF EXISTS quality.quality_test_certificate;
DROP TABLE IF EXISTS document.acdat_sync_log;
DROP TABLE IF EXISTS production.prefab_manufactured_element;
DROP TABLE IF EXISTS production.production_record;
DROP TABLE IF EXISTS production.mix_recipe_component;
DROP TABLE IF EXISTS production.mix_recipe;
DROP TABLE IF EXISTS document.document_ref;

DROP TABLE IF EXISTS bim.project_element_identifier;
DROP TABLE IF EXISTS bim.project_element_registry;
DROP TABLE IF EXISTS catalog.element_type_classification_mapping;
DROP TABLE IF EXISTS catalog.element_type_document_requirement;
DROP TABLE IF EXISTS catalog.element_type_quality_requirement;
DROP TABLE IF EXISTS catalog.element_type_activity_template;
DROP TABLE IF EXISTS catalog.element_type_property_template;
DROP TABLE IF EXISTS catalog.element_type;

CREATE TABLE catalog.element_type (
    element_type_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenant.company(id),
    project_code VARCHAR(50),
    element_type_code VARCHAR(100) NOT NULL,
    element_type_name VARCHAR(200) NOT NULL,
    discipline VARCHAR(100),
    description TEXT,
    default_unit_of_measure VARCHAR(30),
    catalog_version VARCHAR(50) NOT NULL DEFAULT 'draft',
    attributes JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    CHECK ((tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)),
    CHECK (jsonb_typeof(attributes) = 'object')
);

CREATE TABLE catalog.element_type_property_template (
    property_template_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenant.company(id),
    project_code VARCHAR(50),
    element_type_id UUID NOT NULL REFERENCES catalog.element_type(element_type_id),
    property_code VARCHAR(100) NOT NULL,
    property_name VARCHAR(200) NOT NULL,
    property_group VARCHAR(100),
    value_type VARCHAR(50) NOT NULL,
    unit_of_measure VARCHAR(30),
    default_value TEXT,
    allowed_values JSONB NOT NULL DEFAULT '[]'::jsonb,
    is_required BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order INTEGER,
    source_standard VARCHAR(100),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    CHECK ((tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)),
    CHECK (value_type IN ('text', 'number', 'integer', 'boolean', 'date', 'datetime', 'json')),
    CHECK (jsonb_typeof(allowed_values) = 'array'),
    CHECK (sort_order IS NULL OR sort_order >= 0)
);

CREATE TABLE catalog.element_type_activity_template (
    activity_template_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenant.company(id),
    project_code VARCHAR(50),
    element_type_id UUID NOT NULL REFERENCES catalog.element_type(element_type_id),
    activity_code VARCHAR(100) NOT NULL,
    activity_name VARCHAR(200) NOT NULL,
    sequence_no INTEGER,
    completion_event_type VARCHAR(100),
    quantity_basis VARCHAR(50),
    default_weight NUMERIC(8,5),
    rule_parameters JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_required BOOLEAN NOT NULL DEFAULT TRUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    CHECK ((tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)),
    CHECK (sequence_no IS NULL OR sequence_no > 0),
    CHECK (default_weight IS NULL OR default_weight BETWEEN 0 AND 1),
    CHECK (jsonb_typeof(rule_parameters) = 'object')
);

CREATE TABLE catalog.element_type_quality_requirement (
    quality_requirement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenant.company(id),
    project_code VARCHAR(50),
    element_type_id UUID NOT NULL REFERENCES catalog.element_type(element_type_id),
    requirement_code VARCHAR(100) NOT NULL,
    requirement_name VARCHAR(200) NOT NULL,
    test_type VARCHAR(100) NOT NULL,
    applies_at_activity_code VARCHAR(100),
    minimum_test_count INTEGER,
    acceptance_criteria JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_mandatory BOOLEAN NOT NULL DEFAULT TRUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    CHECK ((tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)),
    CHECK (minimum_test_count IS NULL OR minimum_test_count >= 0),
    CHECK (jsonb_typeof(acceptance_criteria) = 'object')
);

CREATE TABLE catalog.element_type_document_requirement (
    document_requirement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenant.company(id),
    project_code VARCHAR(50),
    element_type_id UUID NOT NULL REFERENCES catalog.element_type(element_type_id),
    requirement_code VARCHAR(100) NOT NULL,
    requirement_name VARCHAR(200) NOT NULL,
    doc_type VARCHAR(100) NOT NULL,
    applies_at_activity_code VARCHAR(100),
    minimum_document_count INTEGER,
    requirement_parameters JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_mandatory BOOLEAN NOT NULL DEFAULT TRUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    CHECK ((tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)),
    CHECK (minimum_document_count IS NULL OR minimum_document_count >= 0),
    CHECK (jsonb_typeof(requirement_parameters) = 'object')
);

CREATE TABLE catalog.element_type_classification_mapping (
    classification_mapping_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenant.company(id),
    project_code VARCHAR(50),
    element_type_id UUID NOT NULL REFERENCES catalog.element_type(element_type_id),
    mapping_source VARCHAR(50) NOT NULL,
    revit_category VARCHAR(200),
    revit_family VARCHAR(200),
    revit_type VARCHAR(200),
    ifc_class VARCHAR(100),
    ifc_predefined_type VARCHAR(100),
    uniclass_system VARCHAR(10),
    uniclass_code VARCHAR(50),
    uniclass_title VARCHAR(250),
    bt_element_type_code VARCHAR(100) NOT NULL,
    mapping_confidence NUMERIC(4,3),
    notes TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    CHECK ((tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)),
    CHECK (mapping_source IN ('revit', 'ifc', 'uniclass', 'bt')),
    CHECK (uniclass_system IS NULL OR uniclass_system IN ('EF', 'Ss', 'Pr')),
    CHECK (mapping_confidence IS NULL OR mapping_confidence BETWEEN 0 AND 1),
    CHECK (mapping_source <> 'revit'
        OR revit_category IS NOT NULL
        OR revit_family IS NOT NULL
        OR revit_type IS NOT NULL),
    CHECK (mapping_source <> 'ifc'
        OR ifc_class IS NOT NULL
        OR ifc_predefined_type IS NOT NULL),
    CHECK (mapping_source <> 'uniclass' OR uniclass_code IS NOT NULL)
);

CREATE TABLE bim.project_element_registry (
    project_element_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant.company(id),
    project_code VARCHAR(50) NOT NULL,
    element_type_id UUID REFERENCES catalog.element_type(element_type_id),
    bim_element_id UUID REFERENCES bim.bim_element(id),
    canonical_element_code VARCHAR(200) NOT NULL,
    element_name VARCHAR(250),
    description TEXT,
    parent_project_element_id UUID,
    design_status VARCHAR(50) NOT NULL DEFAULT 'active',
    planned_quantity NUMERIC(18,6),
    unit_of_measure VARCHAR(30),
    planned_start_date DATE,
    planned_finish_date DATE,
    design_attributes JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    FOREIGN KEY (parent_project_element_id, tenant_id, project_code)
        REFERENCES bim.project_element_registry(project_element_id, tenant_id, project_code),
    UNIQUE (project_element_id, tenant_id, project_code),
    UNIQUE (tenant_id, project_code, canonical_element_code),
    CHECK (planned_quantity IS NULL OR planned_quantity >= 0),
    CHECK (jsonb_typeof(design_attributes) = 'object')
);

CREATE TABLE bim.project_element_identifier (
    identifier_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant.company(id),
    project_code VARCHAR(50) NOT NULL,
    project_element_id UUID NOT NULL,
    identifier_type VARCHAR(50) NOT NULL,
    identifier_value VARCHAR(200) NOT NULL,
    source_system VARCHAR(100),
    source_document_ref VARCHAR(200),
    confidence NUMERIC(4,3),
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    FOREIGN KEY (project_element_id, tenant_id, project_code)
        REFERENCES bim.project_element_registry(project_element_id, tenant_id, project_code),
    UNIQUE (identifier_id, tenant_id, project_code),
    UNIQUE (tenant_id, project_code, identifier_type, identifier_value),
    CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1)
);

CREATE UNIQUE INDEX uq_catalog_element_type_global_code_version
    ON catalog.element_type(element_type_code, catalog_version)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX uq_catalog_element_type_project_code_version
    ON catalog.element_type(tenant_id, project_code, element_type_code, catalog_version)
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;
CREATE UNIQUE INDEX uq_catalog_property_template_global
    ON catalog.element_type_property_template(element_type_id, property_code)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX uq_catalog_property_template_project
    ON catalog.element_type_property_template(tenant_id, project_code, element_type_id, property_code)
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;
CREATE UNIQUE INDEX uq_catalog_activity_template_global
    ON catalog.element_type_activity_template(element_type_id, activity_code)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX uq_catalog_activity_template_project
    ON catalog.element_type_activity_template(tenant_id, project_code, element_type_id, activity_code)
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;
CREATE UNIQUE INDEX uq_catalog_quality_requirement_global
    ON catalog.element_type_quality_requirement(element_type_id, requirement_code)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX uq_catalog_quality_requirement_project
    ON catalog.element_type_quality_requirement(tenant_id, project_code, element_type_id, requirement_code)
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;
CREATE UNIQUE INDEX uq_catalog_document_requirement_global
    ON catalog.element_type_document_requirement(element_type_id, requirement_code)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX uq_catalog_document_requirement_project
    ON catalog.element_type_document_requirement(tenant_id, project_code, element_type_id, requirement_code)
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;
CREATE UNIQUE INDEX uq_catalog_classification_mapping_global
    ON catalog.element_type_classification_mapping(
        element_type_id,
        mapping_source,
        (COALESCE(revit_category, '')),
        (COALESCE(revit_family, '')),
        (COALESCE(revit_type, '')),
        (COALESCE(ifc_class, '')),
        (COALESCE(ifc_predefined_type, '')),
        (COALESCE(uniclass_system, '')),
        (COALESCE(uniclass_code, ''))
    )
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX uq_catalog_classification_mapping_project
    ON catalog.element_type_classification_mapping(
        tenant_id,
        project_code,
        element_type_id,
        mapping_source,
        (COALESCE(revit_category, '')),
        (COALESCE(revit_family, '')),
        (COALESCE(revit_type, '')),
        (COALESCE(ifc_class, '')),
        (COALESCE(ifc_predefined_type, '')),
        (COALESCE(uniclass_system, '')),
        (COALESCE(uniclass_code, ''))
    )
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;
CREATE INDEX idx_project_element_registry_type
    ON bim.project_element_registry(tenant_id, project_code, element_type_id);
CREATE INDEX idx_project_element_registry_parent
    ON bim.project_element_registry(parent_project_element_id);
CREATE INDEX idx_project_element_registry_bim_element
    ON bim.project_element_registry(bim_element_id);
CREATE INDEX idx_project_element_identifier_element
    ON bim.project_element_identifier(project_element_id);
CREATE UNIQUE INDEX uq_project_element_identifier_primary_type
    ON bim.project_element_identifier(tenant_id, project_code, project_element_id, identifier_type)
    WHERE is_primary;

COMMENT ON TABLE bim.project_element_registry IS
    'Layer 1 canonical project element identity. BIM stores imported/project-specific baseline data; reusable element type reference data lives in catalog.';
COMMENT ON COLUMN bim.project_element_registry.bim_element_id IS
    'TODO: confirm tenant/project compatibility and behavior across BIM model revisions.';
COMMENT ON TABLE catalog.element_type_classification_mapping IS
    'Explicit mappings from Revit, IFC, Uniclass, or BT codes to BT element types. Importers must not infer IFC/Uniclass mappings silently.';

COMMIT;

-- =============================================================================
-- MIGRATION 13: LAYER 3 CANONICAL EVIDENCE
-- Source: scripts/migrations/migrate_13_layer3_canonical_evidence.sql
-- =============================================================================
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

-- =============================================================================
-- MIGRATION 14: LAYER 4 RECONCILIATION
-- Source: scripts/migrations/migrate_14_progress_reconciliation_draft.sql
-- =============================================================================
-- DRAFT ONLY. DO NOT APPLY UNTIL THE CLEAN RELOAD PLAN IS APPROVED.
-- Destructively replaces Layer 4 reconciliation/rule draft tables.
-- Reconciliation writes Layer 4. MS-05 writes Layer 3 only.
-- The SAL Engine reads Layer 4/progress, not raw parser output.

BEGIN;

DROP TABLE IF EXISTS progress.evidence_link;
DROP TABLE IF EXISTS progress.progress_derivation_rule;

CREATE TABLE progress.evidence_link (
    evidence_link_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant.company(id),
    project_code VARCHAR(50) NOT NULL,
    project_element_id UUID,
    evidence_kind VARCHAR(30) NOT NULL,
    evidence_id UUID NOT NULL,
    evidence_type VARCHAR(100) NOT NULL,
    matched_identifier_id UUID,
    match_method VARCHAR(50),
    match_value VARCHAR(200),
    confidence NUMERIC(4,3),
    link_status VARCHAR(30) NOT NULL DEFAULT 'unmatched',
    is_effective BOOLEAN NOT NULL DEFAULT FALSE,
    reason TEXT,
    matched_by VARCHAR(200),
    matched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_by VARCHAR(200),
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    FOREIGN KEY (project_element_id, tenant_id, project_code)
        REFERENCES bim.project_element_registry(project_element_id, tenant_id, project_code),
    FOREIGN KEY (matched_identifier_id, tenant_id, project_code)
        REFERENCES bim.project_element_identifier(identifier_id, tenant_id, project_code),
    CHECK (evidence_kind IN ('production_record', 'quality_test_result', 'document_ref')),
    CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
    CHECK (link_status IN ('confirmed', 'needs_review', 'unmatched', 'rejected', 'superseded')),
    CHECK (link_status <> 'confirmed' OR project_element_id IS NOT NULL),
    CHECK (
        link_status <> 'unmatched'
        OR (project_element_id IS NULL AND matched_identifier_id IS NULL)
    ),
    CHECK (
        NOT is_effective
        OR (link_status = 'confirmed' AND project_element_id IS NOT NULL)
    )
);

CREATE TABLE progress.progress_derivation_rule (
    progress_derivation_rule_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenant.company(id),
    project_code VARCHAR(50),
    element_type_id UUID REFERENCES catalog.element_type(element_type_id),
    activity_code VARCHAR(100) NOT NULL,
    rule_name VARCHAR(200) NOT NULL,
    evidence_kind VARCHAR(30) NOT NULL,
    evidence_type VARCHAR(100) NOT NULL,
    derivation_method VARCHAR(50) NOT NULL,
    progress_weight NUMERIC(8,5),
    rule_expression JSONB NOT NULL DEFAULT '{}'::jsonb,
    rule_version INTEGER NOT NULL DEFAULT 1,
    effective_from DATE,
    effective_to DATE,
    approval_status VARCHAR(30) NOT NULL DEFAULT 'draft',
    approved_by VARCHAR(200),
    approved_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    CHECK ((tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)),
    CHECK (evidence_kind IN ('production_record', 'quality_test_result', 'document_ref')),
    CHECK (progress_weight IS NULL OR progress_weight BETWEEN 0 AND 1),
    CHECK (rule_version > 0),
    CHECK (effective_to IS NULL OR effective_from IS NULL OR effective_to >= effective_from),
    CHECK (approval_status IN ('draft', 'approved', 'retired')),
    CHECK (jsonb_typeof(rule_expression) = 'object')
);

COMMENT ON TABLE progress.evidence_link IS
    'Layer 4 evidence links written by reconciliation. MS-05 writes Layer 3 only; the SAL Engine reads Layer 4/progress.';
COMMENT ON COLUMN progress.evidence_link.evidence_id IS
    'Controlled polymorphic Layer 3 reference selected by evidence_kind. TODO: enforce target existence with reviewed triggers or reconciliation-service validation.';
COMMENT ON COLUMN progress.evidence_link.link_status IS
    'confirmed/effective=evidence linked to a project element and eligible for SAL/progress; unmatched/needs_review=one current unresolved review/audit outcome per evidence; rejected/superseded=non-effective history.';
COMMENT ON COLUMN progress.evidence_link.reason IS
    'Reason for unmatched, needs_review, rejected, or superseded reconciliation outcomes.';
COMMENT ON COLUMN progress.evidence_link.is_effective IS
    'Only confirmed links with a project_element_id may be effective. SAL/progress derivation must consume confirmed effective links only.';
COMMENT ON TABLE progress.progress_derivation_rule IS
    'Approved-rule model for deriving Layer 4 progress facts consumed by the SAL Engine.';

CREATE UNIQUE INDEX uq_evidence_link_effective
    ON progress.evidence_link(tenant_id, project_code, evidence_kind, evidence_id)
    WHERE is_effective
      AND link_status = 'confirmed'
      AND project_element_id IS NOT NULL;
-- Reconciliation-service ON CONFLICT must repeat this predicate exactly.
CREATE UNIQUE INDEX uq_evidence_link_current_unresolved
    ON progress.evidence_link(tenant_id, project_code, evidence_kind, evidence_id)
    WHERE link_status IN ('unmatched', 'needs_review')
      AND is_effective = FALSE;
CREATE INDEX idx_evidence_link_element_effective
    ON progress.evidence_link(tenant_id, project_code, project_element_id)
    WHERE is_effective
      AND link_status = 'confirmed'
      AND project_element_id IS NOT NULL;
CREATE INDEX idx_evidence_link_review_queue
    ON progress.evidence_link(tenant_id, project_code, link_status, confidence)
    WHERE link_status = 'needs_review';
CREATE INDEX idx_evidence_link_unmatched_reprocess
    ON progress.evidence_link(tenant_id, project_code, evidence_kind, evidence_type)
    WHERE link_status = 'unmatched';
CREATE UNIQUE INDEX uq_progress_derivation_rule_scope_version
    ON progress.progress_derivation_rule(
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(project_code, ''),
        COALESCE(element_type_id, '00000000-0000-0000-0000-000000000000'::uuid),
        activity_code,
        evidence_kind,
        evidence_type,
        rule_version
    );
CREATE INDEX idx_progress_derivation_rule_lookup
    ON progress.progress_derivation_rule(
        tenant_id,
        project_code,
        element_type_id,
        evidence_kind,
        evidence_type
    )
    WHERE is_active AND approval_status = 'approved';

COMMIT;
