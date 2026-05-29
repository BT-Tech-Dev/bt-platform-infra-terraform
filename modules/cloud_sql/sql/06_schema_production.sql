-- =============================================================================
-- 06_schema_production.sql
-- Schema: production
--
-- Dati di produzione industriale: cosa viene prodotto negli impianti
-- (calcestruzzo, prefabbricati, acciaio) e come.
--
-- Fonti dati:
--   - OPC UA (Superbeton/Grigolin): dati in tempo reale dall'impianto CLS
--   - FTP Grigolin: file CSV giornalieri {cdos_k|chdr_k|cstp_k}_M4_{YYYYMMDD}.csv
--   - IDA/Maxfone: telemetria energetica (6 impianti: Cernusco, Fiorenzuola, ecc.)
--   - Manuale: dichiarazioni operatore
-- =============================================================================

-- ─── mix_recipe ──────────────────────────────────────────────────────────────
-- Ricetta di produzione (es. CLS C25/30, CLS C30/37)
-- Deve essere approvata prima di poter essere usata in produzione
CREATE TABLE IF NOT EXISTS production.mix_recipe (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         UUID         NOT NULL REFERENCES tenant.company(id),
    -- Codice ricetta (es. "CLS-C25-V1", "CLS-C30-V2")
    recipe_code       VARCHAR(50)  NOT NULL,
    -- Classe di resistenza (es. "C25/30", "C30/37") secondo UNI EN 206
    material_class    VARCHAR(50),
    -- Standard di riferimento (es. "UNI EN 206:2016")
    standard_ref      VARCHAR(100),
    -- Resistenza caratteristica a compressione (MPa)
    design_strength   NUMERIC(8,2),
    version           VARCHAR(20)  NOT NULL DEFAULT 'v1',
    -- Resa volumetrica (m³ prodotti per ora)
    yield_per_hour    NUMERIC(8,3),
    -- Draft = in preparazione, Approved = approvata e usabile, Retired = ritirata
    status            VARCHAR(20)  NOT NULL DEFAULT 'Draft'
                      CHECK (status IN ('Draft', 'Approved', 'Retired')),
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, recipe_code, version)
);

COMMENT ON TABLE production.mix_recipe IS 'Ricette di produzione (calcestruzzo, malte). Devono essere approvate prima dell''uso.';

-- ─── mix_recipe_component ────────────────────────────────────────────────────
-- Componenti di ogni ricetta (materie prime)
CREATE TABLE IF NOT EXISTS production.mix_recipe_component (
    id               UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID          NOT NULL REFERENCES tenant.company(id),
    recipe_id        UUID          NOT NULL REFERENCES production.mix_recipe(id) ON DELETE CASCADE,
    -- Tipo materiale (Cement, Aggregate, Water, Additive, Filler)
    material_type    VARCHAR(50)   NOT NULL
                     CHECK (material_type IN ('Cement', 'Aggregate', 'Water', 'Additive', 'Filler', 'Other')),
    -- Codice interno materiale (es. "CEM-42.5R", "SABBIA-0/4")
    material_code    VARCHAR(100),
    -- Quantità per unità di prodotto (es. 320 kg per m³ di CLS)
    quantity_per_unit NUMERIC(12,4) NOT NULL,
    unit_of_measure  VARCHAR(20)   NOT NULL,
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE production.mix_recipe_component IS 'Componenti della ricetta di produzione (cemento, aggregati, acqua, additivi)';

-- ─── produced_item ───────────────────────────────────────────────────────────
-- Oggetti fisici prodotti (prefabbricati, casseri, lotti di materiale)
CREATE TABLE IF NOT EXISTS production.produced_item (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID         NOT NULL REFERENCES tenant.company(id),
    item_code   VARCHAR(100) NOT NULL,
    description TEXT,
    -- Component = elemento riutilizzabile (cassero, attrezzatura)
    -- MaterialLot = lotto di materiale monouso (CLS, acciaio)
    item_type   VARCHAR(50)  NOT NULL
                CHECK (item_type IN ('Component', 'MaterialLot', 'Prefab', 'Other')),
    -- Se true, l'oggetto può essere riutilizzato più volte (casseri, attrezzature)
    reusable    BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, item_code)
);

COMMENT ON TABLE production.produced_item IS 'Oggetti prodotti (prefabbricati, casseri, lotti CLS). Possono essere riutilizzabili o monouso.';

-- ─── production_order ────────────────────────────────────────────────────────
-- Ordine di produzione: pianificazione di cosa produrre e quando
CREATE TABLE IF NOT EXISTS production.production_order (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID         NOT NULL REFERENCES tenant.company(id),
    produced_item_id UUID         NOT NULL REFERENCES production.produced_item(id),
    order_code       VARCHAR(100) NOT NULL,
    planned_start    DATE,
    planned_end      DATE,
    status           VARCHAR(30)  NOT NULL DEFAULT 'Planned'
                     CHECK (status IN ('Planned', 'Released', 'InProduction', 'Closed', 'Cancelled')),
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, order_code)
);

COMMENT ON TABLE production.production_order IS 'Ordini di produzione: pianificazione temporale della produzione industriale';

-- ─── production_record ───────────────────────────────────────────────────────
-- Record di produzione effettiva (da OPC UA o dichiarazione manuale)
-- È il dato "grezzo" di ciò che l'impianto ha prodotto
CREATE TABLE IF NOT EXISTS production.production_record (
    id                   UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id            UUID          NOT NULL REFERENCES tenant.company(id),
    -- FK all'avanzamento lavori (element_progress) che questa produzione supporta
    -- Nullable: un record può arrivare prima che l'avanzamento sia registrato
    -- NOTA: il FK viene aggiunto in 07_schema_progress.sql (dopo che progress.element_progress esiste)
    element_progress_id  UUID,
    recipe_id            UUID          REFERENCES production.mix_recipe(id),
    start_time           TIMESTAMPTZ,
    end_time             TIMESTAMPTZ,
    produced_quantity    NUMERIC(15,4) NOT NULL,
    unit_of_measure      VARCHAR(20)   NOT NULL,
    -- Sorgente del dato: OPCUA (automatico), CSV (FTP Grigolin), Manual (operatore)
    source_type          VARCHAR(30)   NOT NULL DEFAULT 'Manual'
                         CHECK (source_type IN ('OPCUA', 'CSV', 'Manual', 'API')),
    -- Numero di elementi prodotti in questo record (per prefabbricati)
    produced_elements    INTEGER       DEFAULT 1,
    -- Esito controllo qualità: OK, WARN, FAIL
    quality_status       VARCHAR(10)   NOT NULL DEFAULT 'OK'
                         CHECK (quality_status IN ('OK', 'WARN', 'FAIL', 'PENDING')),
    -- Payload grezzo originale (JSON da OPC UA o CSV row) per tracciabilità
    raw_data_payload     JSONB,
    created_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE production.production_record IS 'Record di produzione effettiva (OPC UA, CSV Grigolin, manuale). Dati grezzi con tracciabilità completa.';
COMMENT ON COLUMN production.production_record.raw_data_payload IS 'Payload originale non trasformato: {"cdos_k": "...", "h2oRicp": "...", ...}';

-- =============================================================================
-- prefab_manufactured_element
-- MS-05 normalized/domain table for Moretti prefabricated manufactured elements.
-- Raw artifacts remain in object storage and are indexed in raw.import_file.
-- =============================================================================

CREATE TABLE IF NOT EXISTS production.prefab_manufactured_element (
    prefab_manufactured_element_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                      UUID NOT NULL,
    project_code                   VARCHAR NOT NULL,
    source_file_id                 UUID NOT NULL REFERENCES raw.import_file(source_file_id),
    ingestion_run_id               UUID NOT NULL REFERENCES raw.ingestion_run(ingestion_run_id),
    raw_record_id                  UUID,
    source_row_hash                VARCHAR(64) NOT NULL,
    source_sheet_name              VARCHAR,
    source_row_number              INTEGER NOT NULL,
    file_profile                   VARCHAR NOT NULL,
    parser_name                    VARCHAR NOT NULL,
    parser_version                 VARCHAR NOT NULL,

    element_code                   VARCHAR NOT NULL,
    element_serial_number          VARCHAR,
    order_number                   VARCHAR,
    order_status_code              VARCHAR,
    department_code                VARCHAR,
    customer_name                  VARCHAR,
    quantity                       NUMERIC,
    unit_of_measure                VARCHAR,
    length_m                       NUMERIC,
    width_m                        NUMERIC,
    height_m                       NUMERIC,
    volume_m3                      NUMERIC,
    weight_kg                      NUMERIC,
    mould_id                       VARCHAR,
    mould_description              VARCHAR,
    rck                            VARCHAR,
    exposure_class                 VARCHAR,
    fire_resistance                VARCHAR,
    recipe_id                      VARCHAR,
    element_type                   VARCHAR,
    production_date                DATE,
    storage_date                   DATE,
    planned_date                   DATE,
    completed_quantity             NUMERIC,

    dq_status                      VARCHAR NOT NULL DEFAULT 'OK',
    dq_warnings                    JSONB NOT NULL DEFAULT '[]'::jsonb,
    dq_errors                      JSONB NOT NULL DEFAULT '[]'::jsonb,
    extra_fields                   JSONB NOT NULL DEFAULT '{}'::jsonb,
    raw_payload_json               JSONB,
    created_at                     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_prefab_manufactured_element_file_row_hash
        UNIQUE (source_file_id, source_row_hash),
    CONSTRAINT uq_prefab_manufactured_element_source_row
        UNIQUE NULLS NOT DISTINCT (source_file_id, source_sheet_name, source_row_number)
);

COMMENT ON TABLE production.prefab_manufactured_element IS 'MS-05 normalized/domain table for Moretti prefabricated manufactured elements.';
COMMENT ON COLUMN production.prefab_manufactured_element.source_file_id IS 'Raw artifact index reference in raw.import_file.';
COMMENT ON COLUMN production.prefab_manufactured_element.ingestion_run_id IS 'Parser execution audit reference in raw.ingestion_run.';

DROP TRIGGER IF EXISTS trg_prefab_manufactured_element_updated_at ON production.prefab_manufactured_element;
CREATE TRIGGER trg_prefab_manufactured_element_updated_at
    BEFORE UPDATE ON production.prefab_manufactured_element
    FOR EACH ROW EXECUTE FUNCTION tenant.update_updated_at();

-- Indici
CREATE INDEX IF NOT EXISTS idx_prod_recipe_tenant     ON production.mix_recipe(tenant_id);
CREATE INDEX IF NOT EXISTS idx_prod_item_tenant       ON production.produced_item(tenant_id);
CREATE INDEX IF NOT EXISTS idx_prod_order_tenant      ON production.production_order(tenant_id);
CREATE INDEX IF NOT EXISTS idx_prod_record_tenant     ON production.production_record(tenant_id);
CREATE INDEX IF NOT EXISTS idx_prod_record_ep         ON production.production_record(element_progress_id);
CREATE INDEX IF NOT EXISTS idx_prod_record_time       ON production.production_record(start_time);
CREATE INDEX IF NOT EXISTS idx_prod_record_source     ON production.production_record(source_type);
CREATE INDEX IF NOT EXISTS idx_prod_prefab_project_element
    ON production.prefab_manufactured_element(project_code, element_code);
CREATE INDEX IF NOT EXISTS idx_prod_prefab_project_serial
    ON production.prefab_manufactured_element(project_code, element_serial_number);
CREATE INDEX IF NOT EXISTS idx_prod_prefab_project_planned
    ON production.prefab_manufactured_element(project_code, planned_date);
CREATE INDEX IF NOT EXISTS idx_prod_prefab_source_file
    ON production.prefab_manufactured_element(source_file_id);
CREATE INDEX IF NOT EXISTS idx_prod_prefab_ingestion_run
    ON production.prefab_manufactured_element(ingestion_run_id);
