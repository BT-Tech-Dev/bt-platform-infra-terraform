-- =============================================================================
-- 14_schema_raw.sql
-- Schema: raw
--
-- MS-05 raw ingestion layer.
-- Versioned DDL draft for source-file and source-row persistence before
-- normalized/domain mapping. This file intentionally does not define SAL, WBS,
-- BIM, or normalized MS-05 tables.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS raw;

COMMENT ON SCHEMA raw IS 'MS-05 raw ingestion layer: imported files, imported records, and profile-specific source rows.';

GRANT USAGE ON SCHEMA raw TO bt_app;
GRANT USAGE ON SCHEMA raw TO bt_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA raw GRANT ALL PRIVILEGES ON TABLES TO bt_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA raw GRANT ALL PRIVILEGES ON SEQUENCES TO bt_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA raw GRANT SELECT ON TABLES TO bt_readonly;

-- =============================================================================
-- Shared raw ingestion tables
-- =============================================================================

CREATE TABLE IF NOT EXISTS raw.import_file (
    source_file_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID,
    project_code        VARCHAR(50)  NOT NULL,
    doc_type            VARCHAR(100) NOT NULL,
    file_profile        VARCHAR(100) NOT NULL,
    source_system       VARCHAR(100),
    source_file_name    VARCHAR(255),
    source_file_path    TEXT NOT NULL,
    source_file_hash    VARCHAR(64),
    parser_name         VARCHAR(100),
    parser_version      VARCHAR(50),
    ingestion_run_id    UUID,
    ingestion_status    VARCHAR(30),
    rows_total          INTEGER,
    rows_parsed         INTEGER,
    rows_failed         INTEGER,
    dq_warnings         JSONB DEFAULT '[]'::jsonb,
    dq_errors           JSONB DEFAULT '[]'::jsonb,
    raw_file_reference  TEXT,
    ingested_at         TIMESTAMPTZ DEFAULT NOW(),
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE raw.import_file IS 'Raw ingestion file manifest. One row per source file or source file bundle member.';

CREATE TABLE IF NOT EXISTS raw.import_record (
    raw_record_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id      UUID REFERENCES raw.import_file(source_file_id),
    tenant_id           UUID,
    project_code        VARCHAR(50)  NOT NULL,
    doc_type            VARCHAR(100) NOT NULL,
    file_profile        VARCHAR(100) NOT NULL,
    event_type          VARCHAR(100),
    source_sheet_name   VARCHAR(100),
    source_row_number   INTEGER,
    source_row_hash     VARCHAR(64),
    raw_payload_json    JSONB NOT NULL,
    raw_row_text        TEXT,
    parse_status        VARCHAR(30),
    dq_warnings         JSONB DEFAULT '[]'::jsonb,
    dq_errors           JSONB DEFAULT '[]'::jsonb,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE raw.import_record IS 'Generic raw source record before routing to profile-specific raw tables.';

-- =============================================================================
-- Profile-specific raw tables
-- =============================================================================

CREATE TABLE IF NOT EXISTS raw.notebook_insertion (
    notebook_insertion_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id        UUID REFERENCES raw.import_file(source_file_id),
    tenant_id             UUID,
    project_code          VARCHAR(50)  NOT NULL,
    doc_type              VARCHAR(100) NOT NULL,
    file_profile          VARCHAR(100) NOT NULL,
    event_type            VARCHAR(100),
    source_sheet_name     VARCHAR(100),
    source_row_number     INTEGER,
    source_row_hash       VARCHAR(64),
    raw_payload_json      JSONB NOT NULL DEFAULT '{}'::jsonb,
    raw_row_text          TEXT,
    parse_status          VARCHAR(30),
    dq_warnings           JSONB DEFAULT '[]'::jsonb,
    dq_errors             JSONB DEFAULT '[]'::jsonb,
    created_at            TIMESTAMPTZ DEFAULT NOW(),
    ingested_at           TIMESTAMPTZ DEFAULT NOW(),
    elaboration_ref       VARCHAR(50),
    revision              VARCHAR(20),
    work_date             DATE,
    pile_number           INTEGER,
    pile_type             VARCHAR(20),
    producer_name         VARCHAR(100),
    prod_date             DATE,
    hammer_type           VARCHAR(100),
    hammer_mass_type      VARCHAR(20),
    blows_per_min         NUMERIC,
    refusal_cm_blow       NUMERIC
);

CREATE TABLE IF NOT EXISTS raw.prefabricated_register_abc (
    prefabricated_register_abc_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id                UUID REFERENCES raw.import_file(source_file_id),
    tenant_id                     UUID,
    project_code                  VARCHAR(50)  NOT NULL,
    doc_type                      VARCHAR(100) NOT NULL,
    file_profile                  VARCHAR(100) NOT NULL,
    event_type                    VARCHAR(100),
    source_sheet_name             VARCHAR(100),
    source_row_number             INTEGER,
    source_row_hash               VARCHAR(64),
    raw_payload_json              JSONB NOT NULL DEFAULT '{}'::jsonb,
    raw_row_text                  TEXT,
    parse_status                  VARCHAR(30),
    dq_warnings                   JSONB DEFAULT '[]'::jsonb,
    dq_errors                     JSONB DEFAULT '[]'::jsonb,
    created_at                    TIMESTAMPTZ DEFAULT NOW(),
    ingested_at                   TIMESTAMPTZ DEFAULT NOW(),
    producer_name                 VARCHAR(200),
    procedure_name                VARCHAR(200),
    procedure_type                VARCHAR(200),
    procedure_edition             VARCHAR(200),
    page_ref                      VARCHAR(20),
    prod_date                     DATE,
    test_date_b                   DATE,
    curing_days_b                 INTEGER,
    weight_kg_b                   NUMERIC,
    dimensions_b                  VARCHAR(50),
    resist_portland_b             NUMERIC,
    resist_avg_portland_b         NUMERIC,
    resist_pozzolanic_b           NUMERIC,
    resist_avg_pozzol_b           NUMERIC,
    test_date_a                   DATE,
    curing_days_a                 INTEGER,
    weight_kg_a                   NUMERIC,
    dimensions_a                  VARCHAR(50),
    resist_a                      NUMERIC,
    resist_avg_a                  NUMERIC,
    steel_partite                 TEXT,
    element_types                 TEXT,
    compiler                      VARCHAR(200),
    prod_director_name            VARCHAR(200)
);

CREATE TABLE IF NOT EXISTS raw.prefabricated_register_veneta_pali (
    prefabricated_register_veneta_pali_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id                        UUID REFERENCES raw.import_file(source_file_id),
    tenant_id                             UUID,
    project_code                          VARCHAR(50)  NOT NULL,
    doc_type                              VARCHAR(100) NOT NULL,
    file_profile                          VARCHAR(100) NOT NULL,
    event_type                            VARCHAR(100),
    source_sheet_name                     VARCHAR(100),
    source_row_number                     INTEGER,
    source_row_hash                       VARCHAR(64),
    raw_payload_json                      JSONB NOT NULL DEFAULT '{}'::jsonb,
    raw_row_text                          TEXT,
    parse_status                          VARCHAR(30),
    dq_warnings                           JSONB DEFAULT '[]'::jsonb,
    dq_errors                             JSONB DEFAULT '[]'::jsonb,
    created_at                            TIMESTAMPTZ DEFAULT NOW(),
    ingested_at                           TIMESTAMPTZ DEFAULT NOW(),
    producer_name                         VARCHAR(200),
    procedure_name                        VARCHAR(200),
    procedure_type                        VARCHAR(200),
    procedure_edition                     VARCHAR(200),
    lab_cert_ref                          VARCHAR(200),
    b_prod_date                           DATE,
    b_test_date                           DATE,
    b_curing_days                         INTEGER,
    b_weight_kg                           NUMERIC,
    b_resist_compr_mpa                    NUMERIC,
    b_resist_avg_mpa                      NUMERIC,
    a_test_date                           DATE,
    a_curing_days                         INTEGER,
    a_weight_kg                           NUMERIC,
    a_resist_compr_mpa                    NUMERIC,
    a_resist_avg_mpa                      NUMERIC,
    steel_partite                         TEXT,
    element_types                         TEXT
);

CREATE TABLE IF NOT EXISTS raw.concrete_pouring_report (
    concrete_pouring_report_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id             UUID REFERENCES raw.import_file(source_file_id),
    tenant_id                  UUID,
    project_code               VARCHAR(50)  NOT NULL,
    doc_type                   VARCHAR(100) NOT NULL,
    file_profile               VARCHAR(100) NOT NULL,
    event_type                 VARCHAR(100),
    source_sheet_name          VARCHAR(100),
    source_row_number          INTEGER,
    source_row_hash            VARCHAR(64),
    raw_payload_json           JSONB NOT NULL DEFAULT '{}'::jsonb,
    raw_row_text               TEXT,
    parse_status               VARCHAR(30),
    dq_warnings                JSONB DEFAULT '[]'::jsonb,
    dq_errors                  JSONB DEFAULT '[]'::jsonb,
    created_at                 TIMESTAMPTZ DEFAULT NOW(),
    ingested_at                TIMESTAMPTZ DEFAULT NOW(),
    report_date                DATE,
    client                     VARCHAR(200),
    personnel                  TEXT,
    element_type               VARCHAR(100),
    panel_number               VARCHAR(50),
    thickness_cm               NUMERIC,
    length_m                   NUMERIC,
    depth_m                    NUMERIC,
    surface_m2                 NUMERIC,
    guide_wall_quota           NUMERIC,
    excavation_start           TIMESTAMPTZ,
    excavation_end             TIMESTAMPTZ,
    rebar_start                TIMESTAMPTZ,
    rebar_end                  TIMESTAMPTZ,
    pour_start                 TIMESTAMPTZ,
    pour_end                   TIMESTAMPTZ,
    slurry_dosage_kg_theor     NUMERIC,
    slurry_dosage_kg_actual    NUMERIC,
    marsh_viscosity_theor      NUMERIC,
    marsh_viscosity_actual     NUMERIC,
    concrete_vol_theor_m3      NUMERIC,
    concrete_vol_actual_m3     NUMERIC,
    concrete_formula           VARCHAR(200),
    notes                      TEXT,
    ref_ddt_number             VARCHAR(50),
    slump_cm                   NUMERIC
);

CREATE TABLE IF NOT EXISTS raw.bolla_calcestruzzo (
    bolla_calcestruzzo_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id        UUID REFERENCES raw.import_file(source_file_id),
    tenant_id             UUID,
    project_code          VARCHAR(50)  NOT NULL,
    doc_type              VARCHAR(100) NOT NULL,
    file_profile          VARCHAR(100) NOT NULL,
    event_type            VARCHAR(100),
    source_sheet_name     VARCHAR(100),
    source_row_number     INTEGER,
    source_row_hash       VARCHAR(64),
    raw_payload_json      JSONB NOT NULL DEFAULT '{}'::jsonb,
    raw_row_text          TEXT,
    parse_status          VARCHAR(30),
    dq_warnings           JSONB DEFAULT '[]'::jsonb,
    dq_errors             JSONB DEFAULT '[]'::jsonb,
    created_at            TIMESTAMPTZ DEFAULT NOW(),
    ingested_at           TIMESTAMPTZ DEFAULT NOW(),
    nr_bolla              VARCHAR(200),
    data                  DATE,
    h_bolla               TIME,
    nr_ciclo              VARCHAR(200),
    cod_frm               VARCHAR(200),
    nome_frm              TEXT,
    desc_frm              TEXT,
    id_imp                VARCHAR(200),
    m3                    NUMERIC,
    cod_cli               VARCHAR(200),
    nome_cli              TEXT,
    d_ritiro              DATE,
    h_ritiro              TIME,
    cod_bet               VARCHAR(200),
    tar_bet               VARCHAR(200),
    nome_bet              TEXT,
    cod_vet               VARCHAR(200),
    nome_vet              TEXT,
    cls_res               VARCHAR(200),
    cls_esp               VARCHAR(200),
    consist               VARCHAR(200),
    mas_vol               NUMERIC,
    diam_ine              NUMERIC,
    cls_cem               VARCHAR(200),
    tipo_cem              VARCHAR(200),
    dos_cem               NUMERIC,
    rapp_hc               NUMERIC,
    slump                 VARCHAR(200),
    cod_ord               VARCHAR(200),
    m3o_ord               NUMERIC,
    m3o_cons              NUMERIC
);

CREATE TABLE IF NOT EXISTS raw.concrete_plant_daily_bundle (
    concrete_plant_daily_bundle_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id                 UUID REFERENCES raw.import_file(source_file_id),
    tenant_id                      UUID,
    project_code                   VARCHAR(50)  NOT NULL,
    doc_type                       VARCHAR(100) NOT NULL,
    file_profile                   VARCHAR(100) NOT NULL,
    event_type                     VARCHAR(100),
    source_sheet_name              VARCHAR(100),
    source_row_number              INTEGER,
    source_row_hash                VARCHAR(64),
    raw_payload_json               JSONB NOT NULL DEFAULT '{}'::jsonb,
    raw_row_text                   TEXT,
    parse_status                   VARCHAR(30),
    dq_warnings                    JSONB DEFAULT '[]'::jsonb,
    dq_errors                      JSONB DEFAULT '[]'::jsonb,
    created_at                     TIMESTAMPTZ DEFAULT NOW(),
    ingested_at                    TIMESTAMPTZ DEFAULT NOW(),
    production_date                DATE,
    plant_id                       VARCHAR(20),
    cdos_file_path                 VARCHAR(500),
    cstp_file_path                 VARCHAR(500),
    chdr_file_path                 VARCHAR(500),
    files_expected                 INTEGER,
    files_received                 INTEGER,
    bundle_status                  VARCHAR(30)
);

CREATE TABLE IF NOT EXISTS raw.concrete_plant_cycle_cdos (
    concrete_plant_cycle_cdos_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id               UUID REFERENCES raw.import_file(source_file_id),
    tenant_id                    UUID,
    project_code                 VARCHAR(50)  NOT NULL,
    doc_type                     VARCHAR(100) NOT NULL,
    file_profile                 VARCHAR(100) NOT NULL,
    event_type                   VARCHAR(100),
    source_sheet_name            VARCHAR(100),
    source_row_number            INTEGER,
    source_row_hash              VARCHAR(64),
    raw_payload_json             JSONB NOT NULL DEFAULT '{}'::jsonb,
    raw_row_text                 TEXT,
    parse_status                 VARCHAR(30),
    dq_warnings                  JSONB DEFAULT '[]'::jsonb,
    dq_errors                    JSONB DEFAULT '[]'::jsonb,
    created_at                   TIMESTAMPTZ DEFAULT NOW(),
    ingested_at                  TIMESTAMPTZ DEFAULT NOW(),
    production_date              DATE,
    plant_id                     VARCHAR(20),
    id                           INTEGER,
    id_imp                       TEXT,
    id_hdr                       INTEGER,
    date_id                      TEXT,
    cod_frm                      TEXT,
    cod_mix                      TEXT,
    nome_frm                     TEXT,
    desc_frm                     TEXT,
    m3                           NUMERIC,
    sottocic                     INTEGER,
    pt_carico                    INTEGER,
    h2o                          NUMERIC,
    h2o_betc                     NUMERIC,
    h2o_ric                      NUMERIC,
    tot                          NUMERIC,
    t_ciclo                      INTEGER
);

CREATE TABLE IF NOT EXISTS raw.concrete_plant_dosage_cstp (
    concrete_plant_dosage_cstp_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id                UUID REFERENCES raw.import_file(source_file_id),
    tenant_id                     UUID,
    project_code                  VARCHAR(50)  NOT NULL,
    doc_type                      VARCHAR(100) NOT NULL,
    file_profile                  VARCHAR(100) NOT NULL,
    event_type                    VARCHAR(100),
    source_sheet_name             VARCHAR(100),
    source_row_number             INTEGER,
    source_row_hash               VARCHAR(64),
    raw_payload_json              JSONB NOT NULL DEFAULT '{}'::jsonb,
    raw_row_text                  TEXT,
    parse_status                  VARCHAR(30),
    dq_warnings                   JSONB DEFAULT '[]'::jsonb,
    dq_errors                     JSONB DEFAULT '[]'::jsonb,
    created_at                    TIMESTAMPTZ DEFAULT NOW(),
    ingested_at                   TIMESTAMPTZ DEFAULT NOW(),
    production_date               DATE,
    plant_id                      VARCHAR(20),
    id_dos                        INTEGER,
    silo                          TEXT,
    code                          TEXT,
    nome                          TEXT,
    tipo                          INTEGER,
    um                            INTEGER,
    chg                           NUMERIC,
    set1m                         NUMERIC,
    teor                          NUMERIC,
    last                          NUMERIC,
    corr                          NUMERIC,
    ril                           NUMERIC,
    wflg                          INTEGER,
    ps_spec                       NUMERIC,
    ok_umi                        INTEGER,
    umi_p                         NUMERIC,
    ass_p                         NUMERIC,
    umi_h                         NUMERIC,
    ass_h                         NUMERIC
);

CREATE TABLE IF NOT EXISTS raw.concrete_plant_header_chdr (
    concrete_plant_header_chdr_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id                UUID REFERENCES raw.import_file(source_file_id),
    tenant_id                     UUID,
    project_code                  VARCHAR(50)  NOT NULL,
    doc_type                      VARCHAR(100) NOT NULL,
    file_profile                  VARCHAR(100) NOT NULL,
    event_type                    VARCHAR(100),
    source_sheet_name             VARCHAR(100),
    source_row_number             INTEGER,
    source_row_hash               VARCHAR(64),
    raw_payload_json              JSONB NOT NULL DEFAULT '{}'::jsonb,
    raw_row_text                  TEXT,
    parse_status                  VARCHAR(30),
    dq_warnings                   JSONB DEFAULT '[]'::jsonb,
    dq_errors                     JSONB DEFAULT '[]'::jsonb,
    created_at                    TIMESTAMPTZ DEFAULT NOW(),
    ingested_at                   TIMESTAMPTZ DEFAULT NOW(),
    production_date               DATE,
    plant_id                      VARCHAR(20),
    id                            INTEGER,
    tipo_cem                      TEXT
);

CREATE TABLE IF NOT EXISTS raw.ddt_acciaio (
    ddt_id                              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id                      UUID REFERENCES raw.import_file(source_file_id),
    tenant_id                           UUID,
    project_code                        VARCHAR(50)  NOT NULL,
    doc_type                            VARCHAR(100) NOT NULL,
    file_profile                        VARCHAR(100) NOT NULL,
    event_type                          VARCHAR(100),
    source_sheet_name                   VARCHAR(100),
    source_row_number                   INTEGER,
    source_row_hash                     VARCHAR(64),
    raw_payload_json                    JSONB NOT NULL DEFAULT '{}'::jsonb,
    raw_row_text                        TEXT,
    parse_status                        VARCHAR(30),
    dq_warnings                         JSONB DEFAULT '[]'::jsonb,
    dq_errors                           JSONB DEFAULT '[]'::jsonb,
    created_at                          TIMESTAMPTZ DEFAULT NOW(),
    ingested_at                         TIMESTAMPTZ DEFAULT NOW(),
    source_file_hash                    VARCHAR(64),
    document_link                       TEXT,
    ddt_number                          VARCHAR(50),
    ddt_date                            DATE,
    supplier_name                       VARCHAR(200),
    supplier_address                    TEXT,
    supplier_phone                      VARCHAR(50),
    supplier_tax_vat                    VARCHAR(50),
    transformation_center_cert_no       VARCHAR(100),
    transformation_center_cert_date     DATE,
    departure_place                     TEXT,
    recipient_name                      VARCHAR(200),
    recipient_address                   TEXT,
    job_site                            TEXT,
    site_contact                        VARCHAR(200),
    transport_reason                    VARCHAR(100),
    carrier_name                        VARCHAR(200),
    transport_date                      DATE,
    vehicle_plate                       VARCHAR(50),
    gross_weight_kg                     NUMERIC,
    net_weight_kg                       NUMERIC,
    has_traceability_list               BOOLEAN DEFAULT FALSE,
    has_certificates                    BOOLEAN DEFAULT FALSE,
    attachment_links_json               JSONB
);

CREATE TABLE IF NOT EXISTS raw.ddt_acciaio_riga (
    ddt_riga_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id     UUID REFERENCES raw.import_file(source_file_id),
    tenant_id          UUID,
    project_code       VARCHAR(50)  NOT NULL,
    doc_type           VARCHAR(100) NOT NULL,
    file_profile       VARCHAR(100) NOT NULL,
    event_type         VARCHAR(100),
    source_sheet_name  VARCHAR(100),
    source_row_number  INTEGER,
    source_row_hash    VARCHAR(64),
    raw_payload_json   JSONB NOT NULL DEFAULT '{}'::jsonb,
    raw_row_text       TEXT,
    parse_status       VARCHAR(30),
    dq_warnings        JSONB DEFAULT '[]'::jsonb,
    dq_errors          JSONB DEFAULT '[]'::jsonb,
    created_at         TIMESTAMPTZ DEFAULT NOW(),
    ingested_at        TIMESTAMPTZ DEFAULT NOW(),
    ddt_id             UUID REFERENCES raw.ddt_acciaio(ddt_id),
    line_number        INTEGER,
    article_code       VARCHAR(50),
    description        TEXT,
    order_reference    VARCHAR(100),
    unit_of_measure    VARCHAR(20),
    quantity           NUMERIC,
    source_page_number INTEGER,
    raw_line_text      TEXT
);

CREATE TABLE IF NOT EXISTS raw.moretti_prefab_manufatti (
    moretti_prefab_manufatti_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_file_id              UUID REFERENCES raw.import_file(source_file_id),
    tenant_id                   UUID,
    project_code                VARCHAR(50)  NOT NULL,
    doc_type                    VARCHAR(100) NOT NULL,
    file_profile                VARCHAR(100) NOT NULL,
    event_type                  VARCHAR(100),
    source_sheet_name           VARCHAR(100),
    source_row_number           INTEGER,
    source_row_hash             VARCHAR(64),
    raw_payload_json            JSONB NOT NULL DEFAULT '{}'::jsonb,
    raw_row_text                TEXT,
    parse_status                VARCHAR(30),
    dq_warnings                 JSONB DEFAULT '[]'::jsonb,
    dq_errors                   JSONB DEFAULT '[]'::jsonb,
    created_at                  TIMESTAMPTZ DEFAULT NOW(),
    ingested_at                 TIMESTAMPTZ DEFAULT NOW(),
    article_code                VARCHAR(100),
    customer_name               TEXT,
    quantity                    NUMERIC(12,3),
    quantity_uom                VARCHAR(20),
    length_m                    NUMERIC(12,3),
    width_m                     NUMERIC(12,3),
    height_m                    NUMERIC(12,3),
    volume_m3                   NUMERIC(12,3),
    weight_kg                   NUMERIC(12,3),
    formwork_description        VARCHAR(200),
    series_number               VARCHAR(100),
    imported_at_source          TIMESTAMP,
    produced_at                 TIMESTAMP,
    stored_at                   TIMESTAMP,
    order_number                VARCHAR(100),
    deposit_code                VARCHAR(100),
    order_end_date              DATE,
    planned_transport_date      DATE,
    completed_quantity          NUMERIC(12,3),
    formwork_id                 VARCHAR(100),
    rck                         NUMERIC(10,2),
    exposure_class              VARCHAR(100),
    fire_resistance_min         NUMERIC(10,2),
    recipe_id                   VARCHAR(100),
    assembly_time_h             NUMERIC(12,3),
    trip_number                 INTEGER,
    delivery_shipment_date      DATE,
    manufactured_type           VARCHAR(50),
    order_series_key            VARCHAR(150),
    total_height_m              NUMERIC(12,3),
    total_width_m               NUMERIC(12,3),
    total_length_m              NUMERIC(12,3),
    planned_date                DATE
);

-- =============================================================================
-- Indexes
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_raw_import_file_project_doc_profile
    ON raw.import_file(project_code, doc_type, file_profile);
CREATE INDEX IF NOT EXISTS idx_raw_import_file_source_hash
    ON raw.import_file(source_file_hash);
CREATE INDEX IF NOT EXISTS idx_raw_import_file_ingestion_run
    ON raw.import_file(ingestion_run_id);
CREATE INDEX IF NOT EXISTS idx_raw_import_file_status
    ON raw.import_file(ingestion_status);

CREATE INDEX IF NOT EXISTS idx_raw_import_record_project_doc_profile
    ON raw.import_record(project_code, doc_type, file_profile);
CREATE INDEX IF NOT EXISTS idx_raw_import_record_source_file
    ON raw.import_record(source_file_id);
CREATE INDEX IF NOT EXISTS idx_raw_import_record_row_hash
    ON raw.import_record(source_row_hash);

CREATE INDEX IF NOT EXISTS idx_raw_notebook_insertion_project_doc_profile
    ON raw.notebook_insertion(project_code, doc_type, file_profile);
CREATE INDEX IF NOT EXISTS idx_raw_notebook_insertion_source_file
    ON raw.notebook_insertion(source_file_id);
CREATE INDEX IF NOT EXISTS idx_raw_notebook_insertion_row_hash
    ON raw.notebook_insertion(source_row_hash);
CREATE INDEX IF NOT EXISTS idx_raw_notebook_insertion_pile
    ON raw.notebook_insertion(project_code, pile_number, work_date);

CREATE INDEX IF NOT EXISTS idx_raw_prefab_abc_project_doc_profile
    ON raw.prefabricated_register_abc(project_code, doc_type, file_profile);
CREATE INDEX IF NOT EXISTS idx_raw_prefab_abc_source_file
    ON raw.prefabricated_register_abc(source_file_id);
CREATE INDEX IF NOT EXISTS idx_raw_prefab_abc_row_hash
    ON raw.prefabricated_register_abc(source_row_hash);
CREATE INDEX IF NOT EXISTS idx_raw_prefab_abc_prod_date
    ON raw.prefabricated_register_abc(project_code, prod_date);

CREATE INDEX IF NOT EXISTS idx_raw_prefab_veneta_project_doc_profile
    ON raw.prefabricated_register_veneta_pali(project_code, doc_type, file_profile);
CREATE INDEX IF NOT EXISTS idx_raw_prefab_veneta_source_file
    ON raw.prefabricated_register_veneta_pali(source_file_id);
CREATE INDEX IF NOT EXISTS idx_raw_prefab_veneta_row_hash
    ON raw.prefabricated_register_veneta_pali(source_row_hash);
CREATE INDEX IF NOT EXISTS idx_raw_prefab_veneta_b_prod_date
    ON raw.prefabricated_register_veneta_pali(project_code, b_prod_date);

CREATE INDEX IF NOT EXISTS idx_raw_pouring_report_project_doc_profile
    ON raw.concrete_pouring_report(project_code, doc_type, file_profile);
CREATE INDEX IF NOT EXISTS idx_raw_pouring_report_source_file
    ON raw.concrete_pouring_report(source_file_id);
CREATE INDEX IF NOT EXISTS idx_raw_pouring_report_row_hash
    ON raw.concrete_pouring_report(source_row_hash);
CREATE INDEX IF NOT EXISTS idx_raw_pouring_report_panel
    ON raw.concrete_pouring_report(project_code, panel_number, report_date);
CREATE INDEX IF NOT EXISTS idx_raw_pouring_report_ref_ddt
    ON raw.concrete_pouring_report(ref_ddt_number);

CREATE INDEX IF NOT EXISTS idx_raw_bolla_project_doc_profile
    ON raw.bolla_calcestruzzo(project_code, doc_type, file_profile);
CREATE INDEX IF NOT EXISTS idx_raw_bolla_source_file
    ON raw.bolla_calcestruzzo(source_file_id);
CREATE INDEX IF NOT EXISTS idx_raw_bolla_row_hash
    ON raw.bolla_calcestruzzo(source_row_hash);
CREATE INDEX IF NOT EXISTS idx_raw_bolla_nr_bolla
    ON raw.bolla_calcestruzzo(nr_bolla);
CREATE INDEX IF NOT EXISTS idx_raw_bolla_nr_ciclo
    ON raw.bolla_calcestruzzo(nr_ciclo);

CREATE INDEX IF NOT EXISTS idx_raw_bundle_project_doc_profile
    ON raw.concrete_plant_daily_bundle(project_code, doc_type, file_profile);
CREATE INDEX IF NOT EXISTS idx_raw_bundle_source_file
    ON raw.concrete_plant_daily_bundle(source_file_id);
CREATE INDEX IF NOT EXISTS idx_raw_bundle_row_hash
    ON raw.concrete_plant_daily_bundle(source_row_hash);
CREATE INDEX IF NOT EXISTS idx_raw_bundle_plant_date
    ON raw.concrete_plant_daily_bundle(plant_id, production_date);

CREATE INDEX IF NOT EXISTS idx_raw_cdos_project_doc_profile
    ON raw.concrete_plant_cycle_cdos(project_code, doc_type, file_profile);
CREATE INDEX IF NOT EXISTS idx_raw_cdos_source_file
    ON raw.concrete_plant_cycle_cdos(source_file_id);
CREATE INDEX IF NOT EXISTS idx_raw_cdos_row_hash
    ON raw.concrete_plant_cycle_cdos(source_row_hash);
CREATE INDEX IF NOT EXISTS idx_raw_cdos_plant_date
    ON raw.concrete_plant_cycle_cdos(plant_id, production_date);
CREATE INDEX IF NOT EXISTS idx_raw_cdos_id_hdr
    ON raw.concrete_plant_cycle_cdos(id_hdr);

CREATE INDEX IF NOT EXISTS idx_raw_cstp_project_doc_profile
    ON raw.concrete_plant_dosage_cstp(project_code, doc_type, file_profile);
CREATE INDEX IF NOT EXISTS idx_raw_cstp_source_file
    ON raw.concrete_plant_dosage_cstp(source_file_id);
CREATE INDEX IF NOT EXISTS idx_raw_cstp_row_hash
    ON raw.concrete_plant_dosage_cstp(source_row_hash);
CREATE INDEX IF NOT EXISTS idx_raw_cstp_plant_date
    ON raw.concrete_plant_dosage_cstp(plant_id, production_date);
CREATE INDEX IF NOT EXISTS idx_raw_cstp_id_dos
    ON raw.concrete_plant_dosage_cstp(id_dos);

CREATE INDEX IF NOT EXISTS idx_raw_chdr_project_doc_profile
    ON raw.concrete_plant_header_chdr(project_code, doc_type, file_profile);
CREATE INDEX IF NOT EXISTS idx_raw_chdr_source_file
    ON raw.concrete_plant_header_chdr(source_file_id);
CREATE INDEX IF NOT EXISTS idx_raw_chdr_row_hash
    ON raw.concrete_plant_header_chdr(source_row_hash);
CREATE INDEX IF NOT EXISTS idx_raw_chdr_plant_date
    ON raw.concrete_plant_header_chdr(plant_id, production_date);
CREATE INDEX IF NOT EXISTS idx_raw_chdr_id
    ON raw.concrete_plant_header_chdr(id);

CREATE INDEX IF NOT EXISTS idx_raw_ddt_acciaio_project_doc_profile
    ON raw.ddt_acciaio(project_code, doc_type, file_profile);
CREATE INDEX IF NOT EXISTS idx_raw_ddt_acciaio_source_file
    ON raw.ddt_acciaio(source_file_id);
CREATE INDEX IF NOT EXISTS idx_raw_ddt_acciaio_row_hash
    ON raw.ddt_acciaio(source_row_hash);
CREATE INDEX IF NOT EXISTS idx_raw_ddt_acciaio_file_hash
    ON raw.ddt_acciaio(source_file_hash);
CREATE INDEX IF NOT EXISTS idx_raw_ddt_acciaio_number
    ON raw.ddt_acciaio(ddt_number);
CREATE INDEX IF NOT EXISTS idx_raw_ddt_acciaio_supplier
    ON raw.ddt_acciaio(supplier_name);

CREATE INDEX IF NOT EXISTS idx_raw_ddt_acciaio_riga_project_doc_profile
    ON raw.ddt_acciaio_riga(project_code, doc_type, file_profile);
CREATE INDEX IF NOT EXISTS idx_raw_ddt_acciaio_riga_source_file
    ON raw.ddt_acciaio_riga(source_file_id);
CREATE INDEX IF NOT EXISTS idx_raw_ddt_acciaio_riga_row_hash
    ON raw.ddt_acciaio_riga(source_row_hash);
CREATE INDEX IF NOT EXISTS idx_raw_ddt_acciaio_riga_ddt
    ON raw.ddt_acciaio_riga(ddt_id);
CREATE INDEX IF NOT EXISTS idx_raw_ddt_acciaio_riga_article
    ON raw.ddt_acciaio_riga(article_code);

CREATE INDEX IF NOT EXISTS idx_raw_moretti_project_doc_profile
    ON raw.moretti_prefab_manufatti(project_code, doc_type, file_profile);
CREATE INDEX IF NOT EXISTS idx_raw_moretti_source_file
    ON raw.moretti_prefab_manufatti(source_file_id);
CREATE INDEX IF NOT EXISTS idx_raw_moretti_row_hash
    ON raw.moretti_prefab_manufatti(source_row_hash);
CREATE INDEX IF NOT EXISTS idx_raw_moretti_article
    ON raw.moretti_prefab_manufatti(article_code);
CREATE INDEX IF NOT EXISTS idx_raw_moretti_series
    ON raw.moretti_prefab_manufatti(series_number);
CREATE INDEX IF NOT EXISTS idx_raw_moretti_order_series
    ON raw.moretti_prefab_manufatti(order_series_key);

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA raw TO bt_app;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA raw TO bt_app;
GRANT SELECT ON ALL TABLES IN SCHEMA raw TO bt_readonly;
