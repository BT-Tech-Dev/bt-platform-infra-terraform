-- DRAFT ONLY. DO NOT APPLY UNTIL REVIEWED.
-- Refactors catalog Layer 0 from long per-element template tables to a
-- normalized definition/applicability model aligned with BT_Element_Catalog_Master.xlsx.
--
-- Excel mapping:
-- - 02_Parameter_Definitions -> catalog.property_definition
-- - 03_Parameter_Matrix -> catalog.element_type_property_applicability
-- - 04_Activity_Definitions -> catalog.activity_definition
-- - 05_Activity_Matrix -> catalog.element_type_activity_applicability
-- - 07_Quality_Definitions -> catalog.quality_requirement_definition
-- - 08_Quality_Matrix -> catalog.element_type_quality_applicability
-- - 09_Document_Definitions -> catalog.document_requirement_definition
-- - 10_Document_Matrix -> catalog.element_type_document_applicability
-- - 06_Classification_Table -> catalog.element_type_classification_mapping
--
-- source_sheet, source_row, helper, and reviewer notes are import/staging
-- metadata and are not DB domain fields in this normalized schema.
--
-- This migration prepares schema, migrates existing catalog data when old
-- template tables exist, then removes obsolete template tables. It does not
-- seed from Excel, does not use DROP CASCADE, and does not touch
-- production/quality/progress/bim Layer 1 data.

BEGIN;

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
    CHECK ((tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)),
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
    CHECK ((tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)),
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
    CHECK ((tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL))
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
    CHECK ((tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)),
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
    CHECK ((tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)),
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
    CHECK ((tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)),
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
    CHECK ((tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)),
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
    CHECK ((tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)),
    CHECK (minimum_document_count IS NULL OR minimum_document_count >= 0),
    CHECK (jsonb_typeof(applicability_parameters) = 'object')
);

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
    ON catalog.element_type_property_applicability(tenant_id, project_code, element_type_id, property_definition_id)
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
    ON catalog.element_type_activity_applicability(tenant_id, project_code, element_type_id, activity_definition_id)
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

DO $$
BEGIN
    IF to_regclass('catalog.element_type_property_template') IS NOT NULL THEN
        EXECUTE '
            INSERT INTO catalog.property_definition (
                tenant_id, project_code, property_code, property_name,
                property_group, value_type, unit_of_measure, allowed_values,
                source_standard, is_active, created_at, updated_at
            )
            SELECT tenant_id, project_code, property_code, MIN(property_name),
                   MIN(property_group), MIN(value_type), MIN(unit_of_measure),
                   (MIN(allowed_values::text))::jsonb, MIN(source_standard),
                   BOOL_OR(is_active), MIN(created_at), MAX(updated_at)
            FROM catalog.element_type_property_template AS src
            WHERE NOT EXISTS (
                SELECT 1
                FROM catalog.property_definition AS dst
                WHERE dst.tenant_id IS NOT DISTINCT FROM src.tenant_id
                  AND dst.project_code IS NOT DISTINCT FROM src.project_code
                  AND dst.property_code = src.property_code
                  AND dst.catalog_version = ''draft''
            )
            GROUP BY tenant_id, project_code, property_code';

        EXECUTE '
            INSERT INTO catalog.element_type_property_applicability (
                tenant_id, project_code, element_type_id, property_definition_id,
                is_required, default_value, sort_order, is_active, created_at, updated_at
            )
            SELECT src.tenant_id, src.project_code, src.element_type_id,
                   def.property_definition_id, BOOL_OR(src.is_required),
                   MIN(src.default_value), MIN(src.sort_order),
                   BOOL_OR(src.is_active), MIN(src.created_at), MAX(src.updated_at)
            FROM catalog.element_type_property_template AS src
            JOIN catalog.property_definition AS def
              ON def.tenant_id IS NOT DISTINCT FROM src.tenant_id
             AND def.project_code IS NOT DISTINCT FROM src.project_code
             AND def.property_code = src.property_code
             AND def.catalog_version = ''draft''
            WHERE NOT EXISTS (
                SELECT 1
                FROM catalog.element_type_property_applicability AS dst
                WHERE dst.tenant_id IS NOT DISTINCT FROM src.tenant_id
                  AND dst.project_code IS NOT DISTINCT FROM src.project_code
                  AND dst.element_type_id = src.element_type_id
                  AND dst.property_definition_id = def.property_definition_id
            )
            GROUP BY src.tenant_id, src.project_code, src.element_type_id,
                     def.property_definition_id';
    END IF;

    IF to_regclass('catalog.element_type_activity_template') IS NOT NULL THEN
        EXECUTE '
            INSERT INTO catalog.activity_definition (
                tenant_id, project_code, activity_code, activity_name,
                completion_event_type, quantity_basis, is_active, created_at, updated_at
            )
            SELECT tenant_id, project_code, activity_code, MIN(activity_name),
                   MIN(completion_event_type), MIN(quantity_basis), BOOL_OR(is_active),
                   MIN(created_at), MAX(updated_at)
            FROM catalog.element_type_activity_template AS src
            WHERE NOT EXISTS (
                SELECT 1
                FROM catalog.activity_definition AS dst
                WHERE dst.tenant_id IS NOT DISTINCT FROM src.tenant_id
                  AND dst.project_code IS NOT DISTINCT FROM src.project_code
                  AND dst.activity_code = src.activity_code
                  AND dst.catalog_version = ''draft''
            )
            GROUP BY tenant_id, project_code, activity_code';

        EXECUTE '
            INSERT INTO catalog.element_type_activity_applicability (
                tenant_id, project_code, element_type_id, activity_definition_id,
                sequence_no, default_weight, is_required, rule_parameters,
                is_active, created_at, updated_at
            )
            SELECT src.tenant_id, src.project_code, src.element_type_id,
                   def.activity_definition_id, MIN(src.sequence_no),
                   MAX(src.default_weight), BOOL_OR(src.is_required),
                   (MIN(src.rule_parameters::text))::jsonb, BOOL_OR(src.is_active),
                   MIN(src.created_at), MAX(src.updated_at)
            FROM catalog.element_type_activity_template AS src
            JOIN catalog.activity_definition AS def
              ON def.tenant_id IS NOT DISTINCT FROM src.tenant_id
             AND def.project_code IS NOT DISTINCT FROM src.project_code
             AND def.activity_code = src.activity_code
             AND def.catalog_version = ''draft''
            WHERE NOT EXISTS (
                SELECT 1
                FROM catalog.element_type_activity_applicability AS dst
                WHERE dst.tenant_id IS NOT DISTINCT FROM src.tenant_id
                  AND dst.project_code IS NOT DISTINCT FROM src.project_code
                  AND dst.element_type_id = src.element_type_id
                  AND dst.activity_definition_id = def.activity_definition_id
            )
            GROUP BY src.tenant_id, src.project_code, src.element_type_id,
                     def.activity_definition_id';
    END IF;

    IF to_regclass('catalog.element_type_quality_requirement') IS NOT NULL THEN
        EXECUTE '
            INSERT INTO catalog.quality_requirement_definition (
                tenant_id, project_code, requirement_code, requirement_name,
                test_type, acceptance_criteria, is_active, created_at, updated_at
            )
            SELECT tenant_id, project_code, requirement_code, MIN(requirement_name),
                   MIN(test_type), (MIN(acceptance_criteria::text))::jsonb,
                   BOOL_OR(is_active), MIN(created_at), MAX(updated_at)
            FROM catalog.element_type_quality_requirement AS src
            WHERE NOT EXISTS (
                SELECT 1
                FROM catalog.quality_requirement_definition AS dst
                WHERE dst.tenant_id IS NOT DISTINCT FROM src.tenant_id
                  AND dst.project_code IS NOT DISTINCT FROM src.project_code
                  AND dst.requirement_code = src.requirement_code
                  AND dst.catalog_version = ''draft''
            )
            GROUP BY tenant_id, project_code, requirement_code';

        EXECUTE '
            INSERT INTO catalog.element_type_quality_applicability (
                tenant_id, project_code, element_type_id, quality_requirement_definition_id,
                applies_at_activity_code, minimum_test_count, is_mandatory,
                is_active, created_at, updated_at
            )
            SELECT src.tenant_id, src.project_code, src.element_type_id,
                   def.quality_requirement_definition_id, MIN(src.applies_at_activity_code),
                   MAX(src.minimum_test_count), BOOL_OR(src.is_mandatory),
                   BOOL_OR(src.is_active), MIN(src.created_at), MAX(src.updated_at)
            FROM catalog.element_type_quality_requirement AS src
            JOIN catalog.quality_requirement_definition AS def
              ON def.tenant_id IS NOT DISTINCT FROM src.tenant_id
             AND def.project_code IS NOT DISTINCT FROM src.project_code
             AND def.requirement_code = src.requirement_code
             AND def.catalog_version = ''draft''
            WHERE NOT EXISTS (
                SELECT 1
                FROM catalog.element_type_quality_applicability AS dst
                WHERE dst.tenant_id IS NOT DISTINCT FROM src.tenant_id
                  AND dst.project_code IS NOT DISTINCT FROM src.project_code
                  AND dst.element_type_id = src.element_type_id
                  AND dst.quality_requirement_definition_id = def.quality_requirement_definition_id
            )
            GROUP BY src.tenant_id, src.project_code, src.element_type_id,
                     def.quality_requirement_definition_id';
    END IF;

    IF to_regclass('catalog.element_type_document_requirement') IS NOT NULL THEN
        EXECUTE '
            INSERT INTO catalog.document_requirement_definition (
                tenant_id, project_code, requirement_code, requirement_name,
                doc_type, requirement_parameters, is_active, created_at, updated_at
            )
            SELECT tenant_id, project_code, requirement_code, MIN(requirement_name),
                   MIN(doc_type), (MIN(requirement_parameters::text))::jsonb,
                   BOOL_OR(is_active), MIN(created_at), MAX(updated_at)
            FROM catalog.element_type_document_requirement AS src
            WHERE NOT EXISTS (
                SELECT 1
                FROM catalog.document_requirement_definition AS dst
                WHERE dst.tenant_id IS NOT DISTINCT FROM src.tenant_id
                  AND dst.project_code IS NOT DISTINCT FROM src.project_code
                  AND dst.requirement_code = src.requirement_code
                  AND dst.catalog_version = ''draft''
            )
            GROUP BY tenant_id, project_code, requirement_code';

        EXECUTE '
            INSERT INTO catalog.element_type_document_applicability (
                tenant_id, project_code, element_type_id, document_requirement_definition_id,
                applies_at_activity_code, minimum_document_count, is_mandatory,
                is_active, created_at, updated_at
            )
            SELECT src.tenant_id, src.project_code, src.element_type_id,
                   def.document_requirement_definition_id, MIN(src.applies_at_activity_code),
                   MAX(src.minimum_document_count), BOOL_OR(src.is_mandatory),
                   BOOL_OR(src.is_active), MIN(src.created_at), MAX(src.updated_at)
            FROM catalog.element_type_document_requirement AS src
            JOIN catalog.document_requirement_definition AS def
              ON def.tenant_id IS NOT DISTINCT FROM src.tenant_id
             AND def.project_code IS NOT DISTINCT FROM src.project_code
             AND def.requirement_code = src.requirement_code
             AND def.catalog_version = ''draft''
            WHERE NOT EXISTS (
                SELECT 1
                FROM catalog.element_type_document_applicability AS dst
                WHERE dst.tenant_id IS NOT DISTINCT FROM src.tenant_id
                  AND dst.project_code IS NOT DISTINCT FROM src.project_code
                  AND dst.element_type_id = src.element_type_id
                  AND dst.document_requirement_definition_id = def.document_requirement_definition_id
            )
            GROUP BY src.tenant_id, src.project_code, src.element_type_id,
                     def.document_requirement_definition_id';
    END IF;
END $$;

DO $$
DECLARE
    external_dependencies TEXT[];
BEGIN
    -- Diagnostic query for external blockers:
    -- SELECT conrelid::regclass AS referencing_table,
    --        conname AS constraint_name,
    --        confrelid::regclass AS referenced_table,
    --        pg_get_constraintdef(oid) AS constraint_definition
    -- FROM pg_constraint
    -- WHERE contype = 'f'
    --   AND confrelid IN (
    --       'catalog.element_type_property_template'::regclass,
    --       'catalog.element_type_activity_template'::regclass,
    --       'catalog.element_type_quality_requirement'::regclass,
    --       'catalog.element_type_document_requirement'::regclass
    --   )
    --   AND conrelid NOT IN (
    --       'catalog.element_type_property_template'::regclass,
    --       'catalog.element_type_activity_template'::regclass,
    --       'catalog.element_type_quality_requirement'::regclass,
    --       'catalog.element_type_document_requirement'::regclass
    --   );
    SELECT array_agg(
        conrelid::regclass::text || '.' || conname || ' -> ' || confrelid::regclass::text
        ORDER BY conrelid::regclass::text, conname
    )
    INTO external_dependencies
    FROM pg_constraint
    WHERE contype = 'f'
      AND confrelid IN (
          SELECT table_name::regclass
          FROM (
              VALUES
                  ('catalog.element_type_property_template'),
                  ('catalog.element_type_activity_template'),
                  ('catalog.element_type_quality_requirement'),
                  ('catalog.element_type_document_requirement')
          ) AS obsolete(table_name)
          WHERE to_regclass(table_name) IS NOT NULL
      )
      AND conrelid NOT IN (
          SELECT table_name::regclass
          FROM (
              VALUES
                  ('catalog.element_type_property_template'),
                  ('catalog.element_type_activity_template'),
                  ('catalog.element_type_quality_requirement'),
                  ('catalog.element_type_document_requirement')
          ) AS obsolete(table_name)
          WHERE to_regclass(table_name) IS NOT NULL
      );

    IF external_dependencies IS NOT NULL THEN
        RAISE EXCEPTION
            'Refusing to drop obsolete catalog template tables. External FK dependencies still reference them: %',
            external_dependencies;
    END IF;
END $$;

-- Obsolete template tables are removed after backfill. The final catalog schema
-- uses *_definition tables plus element_type_*_applicability matrix tables.
DROP TABLE IF EXISTS catalog.element_type_document_requirement;
DROP TABLE IF EXISTS catalog.element_type_quality_requirement;
DROP TABLE IF EXISTS catalog.element_type_activity_template;
DROP TABLE IF EXISTS catalog.element_type_property_template;

COMMIT;
