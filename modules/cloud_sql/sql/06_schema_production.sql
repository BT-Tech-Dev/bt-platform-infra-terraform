-- =============================================================================
-- 06_schema_production.sql
-- Schema: production
--
-- Canonical Layer 3 production evidence. MS-05 writes Layer 3 canonical
-- evidence. Reconciliation writes Layer 4 evidence links in progress.
-- The SAL Engine reads Layer 4/progress, not raw parser output.
-- =============================================================================

CREATE TABLE IF NOT EXISTS production.mix_recipe (
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

CREATE TABLE IF NOT EXISTS production.mix_recipe_component (
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

-- Existing planning/reference entities remain outside the canonical evidence
-- discriminator model.
CREATE TABLE IF NOT EXISTS production.produced_item (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant.company(id),
    item_code VARCHAR(100) NOT NULL,
    description TEXT,
    item_type VARCHAR(50) NOT NULL
        CHECK (item_type IN ('Component', 'MaterialLot', 'Prefab', 'Other')),
    reusable BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, item_code)
);

CREATE TABLE IF NOT EXISTS production.production_order (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant.company(id),
    produced_item_id UUID NOT NULL REFERENCES production.produced_item(id),
    order_code VARCHAR(100) NOT NULL,
    planned_start DATE,
    planned_end DATE,
    status VARCHAR(30) NOT NULL DEFAULT 'Planned'
        CHECK (status IN ('Planned', 'Released', 'InProduction', 'Closed', 'Cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, order_code)
);

CREATE TABLE IF NOT EXISTS production.production_record (
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

COMMENT ON TABLE production.production_record IS
    'Canonical Layer 3 production evidence written by MS-05. Reconciliation writes Layer 4 evidence links; the SAL Engine reads progress, not this raw parser output directly.';
COMMENT ON COLUMN production.production_record.project_element_id IS
    'Nullable until Layer 4 reconciliation confirms a canonical project element match.';
COMMENT ON COLUMN production.production_record.raw_record_id IS
    'Nullable source record identifier. TODO: add an FK when a canonical raw-record table exists.';

CREATE INDEX IF NOT EXISTS idx_mix_recipe_project_code
    ON production.mix_recipe(tenant_id, project_code, recipe_code);
CREATE INDEX IF NOT EXISTS idx_mix_recipe_component_recipe
    ON production.mix_recipe_component(mix_recipe_id);
CREATE INDEX IF NOT EXISTS idx_produced_item_tenant
    ON production.produced_item(tenant_id);
CREATE INDEX IF NOT EXISTS idx_production_order_tenant
    ON production.production_order(tenant_id);
CREATE INDEX IF NOT EXISTS idx_production_record_type_date
    ON production.production_record(tenant_id, project_code, event_type, event_date);
CREATE INDEX IF NOT EXISTS idx_production_record_element
    ON production.production_record(project_element_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_production_record_source_row
    ON production.production_record(source_file_id, source_row_hash)
    WHERE source_file_id IS NOT NULL AND source_row_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_production_record_match_candidates
    ON production.production_record(
        tenant_id,
        project_code,
        pile_number,
        panel_number,
        element_serial_number,
        element_code
    );

CREATE OR REPLACE VIEW production.pile_installations AS
SELECT
    production_record_id AS pile_installation_id,
    tenant_id,
    project_code,
    project_element_id,
    event_status AS installation_status,
    source_authority,
    event_date AS installation_date,
    event_at AS installed_at,
    pile_number,
    element_type AS pile_type,
    quantity,
    unit_of_measure,
    supplier_name,
    document_ref_id,
    dq_status,
    extra_fields
FROM production.production_record
WHERE event_type = 'pile_installed';

CREATE OR REPLACE VIEW production.prefab_manufactured AS
SELECT
    production_record_id AS prefab_manufactured_id,
    tenant_id,
    project_code,
    project_element_id,
    event_status AS manufacturing_status,
    source_authority,
    event_date AS production_date,
    element_type,
    element_code,
    element_serial_number,
    order_number,
    lot_number,
    quantity,
    unit_of_measure,
    supplier_name,
    mix_recipe_id,
    dq_status,
    extra_fields
FROM production.production_record
WHERE event_type = 'prefab_manufactured';

CREATE OR REPLACE VIEW production.concrete_deliveries AS
SELECT
    production_record_id AS concrete_delivery_id,
    tenant_id,
    project_code,
    project_element_id,
    event_status AS delivery_status,
    source_authority,
    event_date AS delivery_date,
    event_at AS delivered_at,
    delivery_note_number,
    supplier_name,
    plant_id,
    source_recipe_code,
    concrete_volume_actual_m3,
    mix_recipe_id,
    document_ref_id,
    dq_status,
    extra_fields
FROM production.production_record
WHERE event_type = 'concrete_delivery';
