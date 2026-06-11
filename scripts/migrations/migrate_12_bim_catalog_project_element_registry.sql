-- DRAFT ONLY. DO NOT APPLY UNTIL THE CLEAN RELOAD PLAN IS APPROVED.
-- Destructively replaces Layer 0/1 canonical identity tables.
-- Known downstream Layer 3/4 tables are removed here and recreated by
-- migrations 13 and 14; the three drafts must be treated as one transition.

BEGIN;

-- Remove known downstream draft dependencies before replacing Layer 0/1.
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
DROP TABLE IF EXISTS bim.bt_element_type_document_requirement;
DROP TABLE IF EXISTS bim.bt_element_type_quality_requirement;
DROP TABLE IF EXISTS bim.bt_element_type_activity_template;
DROP TABLE IF EXISTS bim.bt_element_type_catalog;

CREATE TABLE bim.bt_element_type_catalog (
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

CREATE TABLE bim.bt_element_type_activity_template (
    activity_template_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenant.company(id),
    project_code VARCHAR(50),
    element_type_id UUID NOT NULL REFERENCES bim.bt_element_type_catalog(element_type_id),
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

CREATE TABLE bim.bt_element_type_quality_requirement (
    quality_requirement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenant.company(id),
    project_code VARCHAR(50),
    element_type_id UUID NOT NULL REFERENCES bim.bt_element_type_catalog(element_type_id),
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

CREATE TABLE bim.bt_element_type_document_requirement (
    document_requirement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenant.company(id),
    project_code VARCHAR(50),
    element_type_id UUID NOT NULL REFERENCES bim.bt_element_type_catalog(element_type_id),
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

CREATE TABLE bim.project_element_registry (
    project_element_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant.company(id),
    project_code VARCHAR(50) NOT NULL,
    element_type_id UUID REFERENCES bim.bt_element_type_catalog(element_type_id),
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

CREATE UNIQUE INDEX uq_bt_element_type_catalog_global_code_version
    ON bim.bt_element_type_catalog(element_type_code, catalog_version)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX uq_bt_element_type_catalog_project_code_version
    ON bim.bt_element_type_catalog(tenant_id, project_code, element_type_code, catalog_version)
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;
CREATE UNIQUE INDEX uq_bt_activity_template_global
    ON bim.bt_element_type_activity_template(element_type_id, activity_code)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX uq_bt_activity_template_project
    ON bim.bt_element_type_activity_template(tenant_id, project_code, element_type_id, activity_code)
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;
CREATE UNIQUE INDEX uq_bt_quality_requirement_global
    ON bim.bt_element_type_quality_requirement(element_type_id, requirement_code)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX uq_bt_quality_requirement_project
    ON bim.bt_element_type_quality_requirement(tenant_id, project_code, element_type_id, requirement_code)
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;
CREATE UNIQUE INDEX uq_bt_document_requirement_global
    ON bim.bt_element_type_document_requirement(element_type_id, requirement_code)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX uq_bt_document_requirement_project
    ON bim.bt_element_type_document_requirement(tenant_id, project_code, element_type_id, requirement_code)
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
    'Layer 1 canonical project element identity used by Layer 3 evidence and Layer 4 reconciliation.';
COMMENT ON COLUMN bim.project_element_registry.bim_element_id IS
    'TODO: confirm tenant/project compatibility and behavior across BIM model revisions.';

COMMIT;
