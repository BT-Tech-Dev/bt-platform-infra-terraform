-- =============================================================================
-- migrate_07_bim_ms01_schema_alignment.sql
-- Schema: bim - aligns Cloud SQL DDL with the deployed MS-01 BIM parser
--
-- COSA FA:
--   1. Adds bim.bim_element.bim_authoring_id.
--   2. Adds bim.bim_quantity.phase and replaces the quantity uniqueness key.
--   3. Aligns bim.bim_element_attribute with the MS-01 attribute shape.
-- =============================================================================

BEGIN;

-- bim_element: Revit/authoring element id (DE_IdElement).
ALTER TABLE bim.bim_element
    ADD COLUMN IF NOT EXISTS bim_authoring_id VARCHAR(50);

COMMENT ON COLUMN bim.bim_element.bim_authoring_id
    IS 'ID dell''elemento nel sistema di authoring BIM (parametro DE_IdElement del JSON Revit)';

-- bim_quantity: phase-aware geometric quantities.
ALTER TABLE bim.bim_quantity
    ADD COLUMN IF NOT EXISTS phase VARCHAR(2) NOT NULL DEFAULT 'DE';

UPDATE bim.bim_quantity
SET phase = 'DE'
WHERE phase IS NULL;

ALTER TABLE bim.bim_quantity
    ALTER COLUMN phase SET DEFAULT 'DE',
    ALTER COLUMN phase SET NOT NULL;

ALTER TABLE bim.bim_quantity
    DROP CONSTRAINT IF EXISTS uq_bim_quantity_element_type;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'bim.bim_quantity'::regclass
          AND conname = 'uq_bim_quantity_element_type_phase'
    ) THEN
        ALTER TABLE bim.bim_quantity
            ADD CONSTRAINT uq_bim_quantity_element_type_phase
            UNIQUE (element_id, quantity_type, phase);
    END IF;
END$$;

COMMENT ON COLUMN bim.bim_quantity.phase
    IS 'Fase costruttiva del dato: DE=Design, AB=As-Built. Default DE per quantita geometriche BIM.';

-- bim_element_attribute: normalized MS-01 element attributes.
CREATE TABLE IF NOT EXISTS bim.bim_element_attribute (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    element_id            UUID NOT NULL REFERENCES bim.bim_element(id) ON DELETE CASCADE,
    phase                 VARCHAR(2) CHECK (phase IS NULL OR phase IN ('DE','AB')),
    attribute_group       VARCHAR(50),
    attribute_name        VARCHAR(200) NOT NULL,
    source_attribute_name VARCHAR(255),
    unit_of_measure       VARCHAR(50),
    value_numeric         NUMERIC(20,6),
    value_text            VARCHAR(500),
    value_date            DATE,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_bim_element_attribute_key UNIQUE NULLS NOT DISTINCT
        (element_id, phase, attribute_group, attribute_name, source_attribute_name)
);

ALTER TABLE bim.bim_element_attribute
    ADD COLUMN IF NOT EXISTS attribute_group VARCHAR(50),
    ADD COLUMN IF NOT EXISTS source_attribute_name VARCHAR(255),
    ADD COLUMN IF NOT EXISTS unit_of_measure VARCHAR(50);

ALTER TABLE bim.bim_element_attribute
    ALTER COLUMN phase DROP NOT NULL;

UPDATE bim.bim_element_attribute
SET phase = NULL
WHERE phase IS NOT NULL
  AND phase NOT IN ('DE','AB');

ALTER TABLE bim.bim_element_attribute
    ALTER COLUMN phase TYPE VARCHAR(2);

DO $$
DECLARE
    constraint_name TEXT;
BEGIN
    FOR constraint_name IN
        SELECT con.conname
        FROM pg_constraint con
        WHERE con.conrelid = 'bim.bim_element_attribute'::regclass
          AND con.contype = 'c'
          AND pg_get_constraintdef(con.oid) ILIKE '%phase%'
    LOOP
        EXECUTE format(
            'ALTER TABLE bim.bim_element_attribute DROP CONSTRAINT IF EXISTS %I',
            constraint_name
        );
    END LOOP;
END$$;

ALTER TABLE bim.bim_element_attribute
    ADD CONSTRAINT ck_bim_element_attribute_phase
    CHECK (phase IS NULL OR phase IN ('DE','AB'));

ALTER TABLE bim.bim_element_attribute
    DROP CONSTRAINT IF EXISTS uq_bim_attr_element_phase_name,
    DROP CONSTRAINT IF EXISTS uq_element_attribute,
    DROP CONSTRAINT IF EXISTS uq_bim_element_attribute_key;

ALTER TABLE bim.bim_element_attribute
    ADD CONSTRAINT uq_bim_element_attribute_key
    UNIQUE NULLS NOT DISTINCT
        (element_id, phase, attribute_group, attribute_name, source_attribute_name);

COMMENT ON TABLE bim.bim_element_attribute
    IS 'Attributi parametrici Revit normalizzati per elemento e fase costruttiva.';
COMMENT ON COLUMN bim.bim_element_attribute.phase
    IS 'Fase costruttiva del dato: DE=Design, AB=As-Built, NULL=non applicabile';
COMMENT ON COLUMN bim.bim_element_attribute.attribute_group
    IS 'Gruppo logico del parametro Revit, quando disponibile';
COMMENT ON COLUMN bim.bim_element_attribute.attribute_name
    IS 'Nome parametro normalizzato senza prefisso di fase';
COMMENT ON COLUMN bim.bim_element_attribute.source_attribute_name
    IS 'Nome parametro sorgente completo come letto dal JSON Revit';
COMMENT ON COLUMN bim.bim_element_attribute.unit_of_measure
    IS 'Unita di misura del parametro, quando presente';

CREATE INDEX IF NOT EXISTS idx_bim_attr_element ON bim.bim_element_attribute(element_id);
CREATE INDEX IF NOT EXISTS idx_bim_attr_phase   ON bim.bim_element_attribute(phase);
CREATE INDEX IF NOT EXISTS idx_bim_attr_name    ON bim.bim_element_attribute(attribute_name);

COMMIT;
