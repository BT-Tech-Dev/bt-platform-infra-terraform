-- DRAFT ONLY. DO NOT APPLY UNTIL REVIEWED.
-- Refactors Layer 0 BT element type catalog out of bim into catalog.
-- This migration does not DROP CASCADE and does not destroy Layer 3 or progress data.

BEGIN;

CREATE SCHEMA IF NOT EXISTS catalog;
COMMENT ON SCHEMA catalog IS
    'Reusable/project-aware BT element type reference catalog independent from BIM imports';
COMMENT ON SCHEMA bim IS
    'Imported BIM model data and project-specific BIM baseline/registry';

CREATE TABLE IF NOT EXISTS catalog.element_type (
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

CREATE TABLE IF NOT EXISTS catalog.element_type_property_template (
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

CREATE TABLE IF NOT EXISTS catalog.element_type_activity_template (
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

CREATE TABLE IF NOT EXISTS catalog.element_type_quality_requirement (
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

CREATE TABLE IF NOT EXISTS catalog.element_type_document_requirement (
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

CREATE TABLE IF NOT EXISTS catalog.element_type_classification_mapping (
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

COMMENT ON TABLE catalog.element_type IS
    'Layer 0 governed BT element type catalog. Global rows have tenant_id/project_code NULL; project overrides set both.';
COMMENT ON TABLE catalog.element_type_classification_mapping IS
    'Explicit mappings from Revit, IFC, Uniclass, or BT codes to BT element types. Importers must not infer IFC/Uniclass mappings silently.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_element_type_global_code_version
    ON catalog.element_type(element_type_code, catalog_version)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_element_type_project_code_version
    ON catalog.element_type(tenant_id, project_code, element_type_code, catalog_version)
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_property_template_global
    ON catalog.element_type_property_template(element_type_id, property_code)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_property_template_project
    ON catalog.element_type_property_template(tenant_id, project_code, element_type_id, property_code)
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_activity_template_global
    ON catalog.element_type_activity_template(element_type_id, activity_code)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_activity_template_project
    ON catalog.element_type_activity_template(tenant_id, project_code, element_type_id, activity_code)
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_quality_requirement_global
    ON catalog.element_type_quality_requirement(element_type_id, requirement_code)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_quality_requirement_project
    ON catalog.element_type_quality_requirement(tenant_id, project_code, element_type_id, requirement_code)
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_document_requirement_global
    ON catalog.element_type_document_requirement(element_type_id, requirement_code)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_document_requirement_project
    ON catalog.element_type_document_requirement(tenant_id, project_code, element_type_id, requirement_code)
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_classification_mapping_global
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
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_classification_mapping_project
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

DO $$
BEGIN
    IF to_regclass('bim.bt_element_type_catalog') IS NOT NULL THEN
        EXECUTE '
            INSERT INTO catalog.element_type (
                element_type_id, tenant_id, project_code, element_type_code,
                element_type_name, discipline, description, default_unit_of_measure,
                catalog_version, attributes, is_active, created_at, updated_at
            )
            SELECT element_type_id, tenant_id, project_code, element_type_code,
                   element_type_name, discipline, description, default_unit_of_measure,
                   catalog_version, attributes, is_active, created_at, updated_at
            FROM bim.bt_element_type_catalog
            ON CONFLICT (element_type_id) DO NOTHING';
    END IF;

    IF to_regclass('bim.bt_element_type_activity_template') IS NOT NULL THEN
        EXECUTE '
            INSERT INTO catalog.element_type_activity_template (
                activity_template_id, tenant_id, project_code, element_type_id,
                activity_code, activity_name, sequence_no, completion_event_type,
                quantity_basis, default_weight, rule_parameters, is_required,
                is_active, created_at, updated_at
            )
            SELECT activity_template_id, tenant_id, project_code, element_type_id,
                   activity_code, activity_name, sequence_no, completion_event_type,
                   quantity_basis, default_weight, rule_parameters, is_required,
                   is_active, created_at, updated_at
            FROM bim.bt_element_type_activity_template
            ON CONFLICT (activity_template_id) DO NOTHING';
    END IF;

    IF to_regclass('bim.bt_element_type_quality_requirement') IS NOT NULL THEN
        EXECUTE '
            INSERT INTO catalog.element_type_quality_requirement (
                quality_requirement_id, tenant_id, project_code, element_type_id,
                requirement_code, requirement_name, test_type, applies_at_activity_code,
                minimum_test_count, acceptance_criteria, is_mandatory, is_active,
                created_at, updated_at
            )
            SELECT quality_requirement_id, tenant_id, project_code, element_type_id,
                   requirement_code, requirement_name, test_type, applies_at_activity_code,
                   minimum_test_count, acceptance_criteria, is_mandatory, is_active,
                   created_at, updated_at
            FROM bim.bt_element_type_quality_requirement
            ON CONFLICT (quality_requirement_id) DO NOTHING';
    END IF;

    IF to_regclass('bim.bt_element_type_document_requirement') IS NOT NULL THEN
        EXECUTE '
            INSERT INTO catalog.element_type_document_requirement (
                document_requirement_id, tenant_id, project_code, element_type_id,
                requirement_code, requirement_name, doc_type, applies_at_activity_code,
                minimum_document_count, requirement_parameters, is_mandatory,
                is_active, created_at, updated_at
            )
            SELECT document_requirement_id, tenant_id, project_code, element_type_id,
                   requirement_code, requirement_name, doc_type, applies_at_activity_code,
                   minimum_document_count, requirement_parameters, is_mandatory,
                   is_active, created_at, updated_at
            FROM bim.bt_element_type_document_requirement
            ON CONFLICT (document_requirement_id) DO NOTHING';
    END IF;
END $$;

DO $$
DECLARE
    old_catalog_oid OID := to_regclass('bim.bt_element_type_catalog');
    constraint_row RECORD;
BEGIN
    IF old_catalog_oid IS NOT NULL AND to_regclass('bim.project_element_registry') IS NOT NULL THEN
        FOR constraint_row IN
            SELECT conname
            FROM pg_constraint
            WHERE conrelid = 'bim.project_element_registry'::regclass
              AND contype = 'f'
              AND confrelid = old_catalog_oid
        LOOP
            EXECUTE format(
                'ALTER TABLE bim.project_element_registry DROP CONSTRAINT %I',
                constraint_row.conname
            );
        END LOOP;
    END IF;

    IF to_regclass('bim.project_element_registry') IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
           FROM pg_constraint
           WHERE conrelid = 'bim.project_element_registry'::regclass
             AND conname = 'fk_project_element_registry_element_type'
       )
    THEN
        ALTER TABLE bim.project_element_registry
            ADD CONSTRAINT fk_project_element_registry_element_type
            FOREIGN KEY (element_type_id)
            REFERENCES catalog.element_type(element_type_id);
    END IF;
END $$;

DO $$
DECLARE
    old_catalog_oid OID := to_regclass('bim.bt_element_type_catalog');
    constraint_row RECORD;
BEGIN
    IF old_catalog_oid IS NOT NULL AND to_regclass('progress.progress_derivation_rule') IS NOT NULL THEN
        FOR constraint_row IN
            SELECT conname
            FROM pg_constraint
            WHERE conrelid = 'progress.progress_derivation_rule'::regclass
              AND contype = 'f'
              AND confrelid = old_catalog_oid
        LOOP
            EXECUTE format(
                'ALTER TABLE progress.progress_derivation_rule DROP CONSTRAINT %I',
                constraint_row.conname
            );
        END LOOP;
    END IF;

    IF to_regclass('progress.progress_derivation_rule') IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
           FROM pg_constraint
           WHERE conrelid = 'progress.progress_derivation_rule'::regclass
             AND conname = 'fk_progress_derivation_rule_element_type'
       )
    THEN
        ALTER TABLE progress.progress_derivation_rule
            ADD CONSTRAINT fk_progress_derivation_rule_element_type
            FOREIGN KEY (element_type_id)
            REFERENCES catalog.element_type(element_type_id);
    END IF;
END $$;

COMMENT ON TABLE bim.project_element_registry IS
    'Layer 1 canonical project element identity. BIM stores imported/project-specific baseline data; reusable element type reference data lives in catalog.';

DO $$
BEGIN
    IF to_regclass('bim.bt_element_type_document_requirement') IS NOT NULL
       AND to_regclass('bim.deprecated_bt_element_type_document_requirement') IS NULL
    THEN
        ALTER TABLE bim.bt_element_type_document_requirement
            RENAME TO deprecated_bt_element_type_document_requirement;
    END IF;

    IF to_regclass('bim.bt_element_type_quality_requirement') IS NOT NULL
       AND to_regclass('bim.deprecated_bt_element_type_quality_requirement') IS NULL
    THEN
        ALTER TABLE bim.bt_element_type_quality_requirement
            RENAME TO deprecated_bt_element_type_quality_requirement;
    END IF;

    IF to_regclass('bim.bt_element_type_activity_template') IS NOT NULL
       AND to_regclass('bim.deprecated_bt_element_type_activity_template') IS NULL
    THEN
        ALTER TABLE bim.bt_element_type_activity_template
            RENAME TO deprecated_bt_element_type_activity_template;
    END IF;

    IF to_regclass('bim.bt_element_type_catalog') IS NOT NULL
       AND to_regclass('bim.deprecated_bt_element_type_catalog') IS NULL
    THEN
        ALTER TABLE bim.bt_element_type_catalog
            RENAME TO deprecated_bt_element_type_catalog;
    END IF;
END $$;

COMMIT;
