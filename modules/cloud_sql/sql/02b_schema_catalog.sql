-- =============================================================================
-- 02b_schema_catalog.sql
-- BT reusable/project-aware reference catalog for canonical element types.
--
-- catalog = reusable/project-aware BT element type reference catalog.
-- bim = imported BIM model data and project-specific BIM baseline/registry.
--
-- Matrix-first Excel mapping:
-- - 01_Element_Type_Master maps to catalog.element_type.
-- - 02/04/07/09 *_Definitions sheets map to *_definition tables.
-- - 03/05/08/10 *_Matrix sheets map to element_type_*_applicability tables.
-- - 06_Classification_Table maps to catalog.element_type_classification_mapping.
-- - source_sheet, source_row, helper, and reviewer notes are import/staging
--   metadata and are not DB domain fields in this normalized schema.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS catalog;
COMMENT ON SCHEMA catalog IS
    'Reusable/project-aware BT element type reference catalog independent from BIM imports';

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
    CHECK (
        (tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)
    ),
    CHECK (jsonb_typeof(attributes) = 'object')
);

CREATE TABLE IF NOT EXISTS catalog.property_definition (
    property_definition_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenant.company(id),
    project_code VARCHAR(50),
    property_code VARCHAR(100) NOT NULL,
    property_name VARCHAR(200) NOT NULL,
    property_group VARCHAR(100),
    value_type VARCHAR(50) NOT NULL,
    unit_of_measure VARCHAR(30),
    allowed_values JSONB NOT NULL DEFAULT '[]'::jsonb,
    source_standard VARCHAR(100),
    catalog_version VARCHAR(50) NOT NULL DEFAULT 'draft',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    CHECK (
        (tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)
    ),
    CHECK (value_type IN ('text', 'number', 'integer', 'boolean', 'date', 'datetime', 'json')),
    CHECK (jsonb_typeof(allowed_values) = 'array')
);

CREATE TABLE IF NOT EXISTS catalog.element_type_property_applicability (
    property_applicability_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenant.company(id),
    project_code VARCHAR(50),
    element_type_id UUID NOT NULL REFERENCES catalog.element_type(element_type_id),
    property_definition_id UUID NOT NULL REFERENCES catalog.property_definition(property_definition_id),
    is_required BOOLEAN NOT NULL DEFAULT FALSE,
    default_value TEXT,
    sort_order INTEGER,
    applicability_parameters JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    CHECK (
        (tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)
    ),
    CHECK (sort_order IS NULL OR sort_order >= 0),
    CHECK (jsonb_typeof(applicability_parameters) = 'object')
);

CREATE TABLE IF NOT EXISTS catalog.activity_definition (
    activity_definition_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenant.company(id),
    project_code VARCHAR(50),
    activity_code VARCHAR(100) NOT NULL,
    activity_name VARCHAR(200) NOT NULL,
    description TEXT,
    completion_event_type VARCHAR(100),
    quantity_basis VARCHAR(50),
    catalog_version VARCHAR(50) NOT NULL DEFAULT 'draft',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    CHECK (
        (tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS catalog.element_type_activity_applicability (
    activity_applicability_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenant.company(id),
    project_code VARCHAR(50),
    element_type_id UUID NOT NULL REFERENCES catalog.element_type(element_type_id),
    activity_definition_id UUID NOT NULL REFERENCES catalog.activity_definition(activity_definition_id),
    sequence_no INTEGER,
    default_weight NUMERIC(8,5),
    is_required BOOLEAN NOT NULL DEFAULT TRUE,
    rule_parameters JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    CHECK (
        (tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)
    ),
    CHECK (sequence_no IS NULL OR sequence_no > 0),
    CHECK (default_weight IS NULL OR default_weight BETWEEN 0 AND 1),
    CHECK (jsonb_typeof(rule_parameters) = 'object')
);

CREATE TABLE IF NOT EXISTS catalog.quality_requirement_definition (
    quality_requirement_definition_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenant.company(id),
    project_code VARCHAR(50),
    requirement_code VARCHAR(100) NOT NULL,
    requirement_name VARCHAR(200) NOT NULL,
    test_type VARCHAR(100) NOT NULL,
    acceptance_criteria JSONB NOT NULL DEFAULT '{}'::jsonb,
    catalog_version VARCHAR(50) NOT NULL DEFAULT 'draft',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    CHECK (
        (tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)
    ),
    CHECK (jsonb_typeof(acceptance_criteria) = 'object')
);

CREATE TABLE IF NOT EXISTS catalog.element_type_quality_applicability (
    quality_applicability_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenant.company(id),
    project_code VARCHAR(50),
    element_type_id UUID NOT NULL REFERENCES catalog.element_type(element_type_id),
    quality_requirement_definition_id UUID NOT NULL
        REFERENCES catalog.quality_requirement_definition(quality_requirement_definition_id),
    applies_at_activity_code VARCHAR(100),
    minimum_test_count INTEGER,
    is_mandatory BOOLEAN NOT NULL DEFAULT TRUE,
    applicability_parameters JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    CHECK (
        (tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)
    ),
    CHECK (minimum_test_count IS NULL OR minimum_test_count >= 0),
    CHECK (jsonb_typeof(applicability_parameters) = 'object')
);

CREATE TABLE IF NOT EXISTS catalog.document_requirement_definition (
    document_requirement_definition_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenant.company(id),
    project_code VARCHAR(50),
    requirement_code VARCHAR(100) NOT NULL,
    requirement_name VARCHAR(200) NOT NULL,
    doc_type VARCHAR(100) NOT NULL,
    requirement_parameters JSONB NOT NULL DEFAULT '{}'::jsonb,
    catalog_version VARCHAR(50) NOT NULL DEFAULT 'draft',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    CHECK (
        (tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)
    ),
    CHECK (jsonb_typeof(requirement_parameters) = 'object')
);

CREATE TABLE IF NOT EXISTS catalog.element_type_document_applicability (
    document_applicability_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenant.company(id),
    project_code VARCHAR(50),
    element_type_id UUID NOT NULL REFERENCES catalog.element_type(element_type_id),
    document_requirement_definition_id UUID NOT NULL
        REFERENCES catalog.document_requirement_definition(document_requirement_definition_id),
    applies_at_activity_code VARCHAR(100),
    minimum_document_count INTEGER,
    is_mandatory BOOLEAN NOT NULL DEFAULT TRUE,
    applicability_parameters JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    CHECK (
        (tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)
    ),
    CHECK (minimum_document_count IS NULL OR minimum_document_count >= 0),
    CHECK (jsonb_typeof(applicability_parameters) = 'object')
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
    CHECK (
        (tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)
    ),
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
COMMENT ON TABLE catalog.property_definition IS
    'Definition table loaded from Excel 02_Parameter_Definitions. Matrix/applicability rows decide which element types use each parameter.';
COMMENT ON TABLE catalog.element_type_property_applicability IS
    'Applicability table loaded from Excel 03_Parameter_Matrix.';
COMMENT ON TABLE catalog.activity_definition IS
    'Definition table loaded from Excel 04_Activity_Definitions.';
COMMENT ON TABLE catalog.element_type_activity_applicability IS
    'Applicability table loaded from Excel 05_Activity_Matrix.';
COMMENT ON TABLE catalog.quality_requirement_definition IS
    'Definition table loaded from Excel 07_Quality_Definitions.';
COMMENT ON TABLE catalog.element_type_quality_applicability IS
    'Applicability table loaded from Excel 08_Quality_Matrix.';
COMMENT ON TABLE catalog.document_requirement_definition IS
    'Definition table loaded from Excel 09_Document_Definitions.';
COMMENT ON TABLE catalog.element_type_document_applicability IS
    'Applicability table loaded from Excel 10_Document_Matrix.';
COMMENT ON TABLE catalog.element_type_classification_mapping IS
    'Explicit mappings from Excel 06_Classification_Table. Importers must not infer IFC/Uniclass mappings silently.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_element_type_global_code_version
    ON catalog.element_type(element_type_code, catalog_version)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_element_type_project_code_version
    ON catalog.element_type(tenant_id, project_code, element_type_code, catalog_version)
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_property_definition_global
    ON catalog.property_definition(property_code, catalog_version)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_property_definition_project
    ON catalog.property_definition(tenant_id, project_code, property_code, catalog_version)
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_property_applicability_global
    ON catalog.element_type_property_applicability(element_type_id, property_definition_id)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_property_applicability_project
    ON catalog.element_type_property_applicability(
        tenant_id,
        project_code,
        element_type_id,
        property_definition_id
    )
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_activity_definition_global
    ON catalog.activity_definition(activity_code, catalog_version)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_activity_definition_project
    ON catalog.activity_definition(tenant_id, project_code, activity_code, catalog_version)
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_activity_applicability_global
    ON catalog.element_type_activity_applicability(element_type_id, activity_definition_id)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_activity_applicability_project
    ON catalog.element_type_activity_applicability(
        tenant_id,
        project_code,
        element_type_id,
        activity_definition_id
    )
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_quality_definition_global
    ON catalog.quality_requirement_definition(requirement_code, catalog_version)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_quality_definition_project
    ON catalog.quality_requirement_definition(tenant_id, project_code, requirement_code, catalog_version)
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_quality_applicability_global
    ON catalog.element_type_quality_applicability(element_type_id, quality_requirement_definition_id)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_quality_applicability_project
    ON catalog.element_type_quality_applicability(
        tenant_id,
        project_code,
        element_type_id,
        quality_requirement_definition_id
    )
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_document_definition_global
    ON catalog.document_requirement_definition(requirement_code, catalog_version)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_document_definition_project
    ON catalog.document_requirement_definition(tenant_id, project_code, requirement_code, catalog_version)
    WHERE tenant_id IS NOT NULL AND project_code IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_document_applicability_global
    ON catalog.element_type_document_applicability(element_type_id, document_requirement_definition_id)
    WHERE tenant_id IS NULL AND project_code IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_catalog_document_applicability_project
    ON catalog.element_type_document_applicability(
        tenant_id,
        project_code,
        element_type_id,
        document_requirement_definition_id
    )
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
