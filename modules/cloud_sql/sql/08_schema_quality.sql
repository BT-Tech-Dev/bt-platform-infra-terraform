-- =============================================================================
-- 08_schema_quality.sql
-- Schema: quality
--
-- Gestione qualità: certificati di prova, non conformità (NCR).
-- Il SAL Engine blocca il rilascio del SAL se:
--   - Copertura certificati < 98% (check 4)
--   - Ci sono NCR Major con blocks_sal = true (check 5)
-- =============================================================================

-- ─── quality_test_certificate ────────────────────────────────────────────────
-- Certificato di prova (es. cubetti calcestruzzo, prove di tiro bulloni)
CREATE TABLE IF NOT EXISTS quality.quality_test_certificate (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         UUID         NOT NULL REFERENCES tenant.company(id),
    -- FK all'avanzamento lavori a cui si riferisce questo certificato
    work_progress_id  UUID         NOT NULL REFERENCES progress.work_progress(id),
    -- Ricetta usata per questa produzione (opzionale: non tutti i test hanno ricetta)
    recipe_id         UUID         REFERENCES production.mix_recipe(id),
    -- Tipo di test (es. "Compressione 28gg", "Slump", "Tiro bullone", "Saldatura")
    test_type         VARCHAR(100) NOT NULL,
    -- Data prelievo campione
    sample_date       DATE,
    -- Data effettuazione test (può essere settimane dopo il campionamento)
    test_date         DATE,
    -- Laboratorio che ha eseguito il test
    laboratory_name   VARCHAR(255),
    -- Standard di riferimento (es. "UNI EN 12390-3", "EN 1090-2")
    standard_ref      VARCHAR(100),
    -- Risultato numerico del test
    result_value      NUMERIC(15,4),
    -- Unità di misura del risultato (es. "MPa", "kN", "mm")
    result_unit       VARCHAR(20),
    -- PASS = conforme, FAIL = non conforme, PENDING = risultato atteso
    outcome           VARCHAR(10)  NOT NULL DEFAULT 'PENDING'
                      CHECK (outcome IN ('PASS', 'FAIL', 'PENDING', 'VOID')),
    -- Riferimento GCS al documento PDF del certificato
    document_ref      TEXT,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE quality.quality_test_certificate IS 'Certificati di prova qualità (CLS, acciaio, saldature). Richiesti per sbloccare il SAL.';
COMMENT ON COLUMN quality.quality_test_certificate.outcome IS 'PASS=conforme, FAIL=non conforme (genera NCR), PENDING=risultato atteso, VOID=annullato';

-- ─── non_conformity ──────────────────────────────────────────────────────────
-- Non Conformità (NCR): deviazione da requisiti contrattuali o normativi
CREATE TABLE IF NOT EXISTS quality.non_conformity (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID         NOT NULL REFERENCES tenant.company(id),
    -- FK all'avanzamento lavori dove è stata rilevata la NC
    work_progress_id    UUID         NOT NULL REFERENCES progress.work_progress(id),
    -- Data rilevazione NC
    detected_date       DATE         NOT NULL DEFAULT CURRENT_DATE,
    -- Data scadenza per la risoluzione
    deadline_date       DATE,
    -- Minor = non blocca il SAL, Major = può bloccare il SAL
    severity            VARCHAR(10)  NOT NULL DEFAULT 'Minor'
                        CHECK (severity IN ('Minor', 'Major', 'Critical')),
    description         TEXT         NOT NULL,
    -- Causa radice della NC (analisi dei 5 perché)
    root_cause          TEXT,
    -- Se TRUE e severity = Major, il SAL Engine BLOCCA il rilascio del SAL
    blocks_sal          BOOLEAN      NOT NULL DEFAULT FALSE,
    -- Open = aperta, InProgress = in lavorazione, Closed = risolta, Waived = derogata
    status              VARCHAR(20)  NOT NULL DEFAULT 'Open'
                        CHECK (status IN ('Open', 'InProgress', 'Closed', 'Waived')),
    -- Azione correttiva intrapresa
    corrective_action   TEXT,
    -- Data di chiusura della NC
    closed_date         DATE,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE quality.non_conformity IS 'Non Conformità (NCR). Le NCR Major con blocks_sal=true impediscono il rilascio del SAL.';
COMMENT ON COLUMN quality.non_conformity.blocks_sal IS 'Se TRUE: il SAL Engine blocca il SAL finché questa NCR non è Closed o Waived';

-- =============================================================================
-- prefab_compression_test_result
-- MS-05 normalized/domain table for prefab concrete compression test registers.
-- Raw artifacts remain in object storage and are indexed in raw.import_file.
-- =============================================================================

CREATE TABLE IF NOT EXISTS quality.prefab_compression_test_result (
    prefab_compression_test_result_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                         UUID NOT NULL REFERENCES tenant.company(id),
    project_code                      VARCHAR NOT NULL,
    source_file_id                    UUID NOT NULL REFERENCES raw.import_file(source_file_id),
    ingestion_run_id                  UUID NOT NULL REFERENCES raw.ingestion_run(ingestion_run_id),
    raw_record_id                     UUID,
    source_row_hash                   VARCHAR(64) NOT NULL,
    source_sheet_name                 VARCHAR,
    source_row_number                 INTEGER NOT NULL,
    file_profile                      VARCHAR NOT NULL,
    parser_name                       VARCHAR NOT NULL,
    parser_version                    VARCHAR NOT NULL,

    supplier_name                     VARCHAR,
    register_year                     INTEGER,
    control_type                      VARCHAR,
    specimen_sequence                 INTEGER,
    production_date                   DATE,
    test_date                         DATE,
    curing_days                       INTEGER,
    weight_kg                         NUMERIC,
    dimensions_text                   VARCHAR,
    length_cm                         NUMERIC,
    width_cm                          NUMERIC,
    height_cm                         NUMERIC,
    cement_type                       VARCHAR,
    compressive_strength_n_mm2        NUMERIC,
    average_strength_n_mm2            NUMERIC,
    test_status                       VARCHAR,
    steel_batch_text                  TEXT,
    prefab_types_text                 TEXT,

    dq_status                         VARCHAR NOT NULL DEFAULT 'OK',
    dq_warnings                       JSONB NOT NULL DEFAULT '[]'::jsonb,
    dq_errors                         JSONB NOT NULL DEFAULT '[]'::jsonb,
    extra_fields                      JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at                        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_prefab_compression_test_result_file_row_hash
        UNIQUE (source_file_id, source_row_hash),
    CONSTRAINT uq_prefab_compression_test_result_source_row
        UNIQUE NULLS NOT DISTINCT (source_file_id, source_sheet_name, source_row_number)
);

COMMENT ON TABLE quality.prefab_compression_test_result IS 'MS-05 normalized/domain table for prefab concrete compression test register rows.';
COMMENT ON COLUMN quality.prefab_compression_test_result.source_file_id IS 'Raw artifact index reference in raw.import_file.';
COMMENT ON COLUMN quality.prefab_compression_test_result.ingestion_run_id IS 'Parser execution audit reference in raw.ingestion_run.';

DROP TRIGGER IF EXISTS trg_prefab_compression_test_result_updated_at ON quality.prefab_compression_test_result;
CREATE TRIGGER trg_prefab_compression_test_result_updated_at
    BEFORE UPDATE ON quality.prefab_compression_test_result
    FOR EACH ROW EXECUTE FUNCTION tenant.update_updated_at();

-- Indici
CREATE INDEX IF NOT EXISTS idx_qual_cert_tenant  ON quality.quality_test_certificate(tenant_id);
CREATE INDEX IF NOT EXISTS idx_qual_cert_wp      ON quality.quality_test_certificate(work_progress_id);
CREATE INDEX IF NOT EXISTS idx_qual_cert_outcome ON quality.quality_test_certificate(outcome);
CREATE INDEX IF NOT EXISTS idx_qual_nc_tenant    ON quality.non_conformity(tenant_id);
CREATE INDEX IF NOT EXISTS idx_qual_nc_wp        ON quality.non_conformity(work_progress_id);
CREATE INDEX IF NOT EXISTS idx_qual_nc_status    ON quality.non_conformity(status);
CREATE INDEX IF NOT EXISTS idx_qual_prefab_comp_project_production_date
    ON quality.prefab_compression_test_result(project_code, production_date);
CREATE INDEX IF NOT EXISTS idx_qual_prefab_comp_project_test_date
    ON quality.prefab_compression_test_result(project_code, test_date);
CREATE INDEX IF NOT EXISTS idx_qual_prefab_comp_project_test_status
    ON quality.prefab_compression_test_result(project_code, test_status);
CREATE INDEX IF NOT EXISTS idx_qual_prefab_comp_source_file
    ON quality.prefab_compression_test_result(source_file_id);
CREATE INDEX IF NOT EXISTS idx_qual_prefab_comp_ingestion_run
    ON quality.prefab_compression_test_result(ingestion_run_id);
CREATE INDEX IF NOT EXISTS idx_qual_prefab_comp_steel_batch_text
    ON quality.prefab_compression_test_result(steel_batch_text);
-- Indice specifico per il check SAL Engine: trova rapidamente le NCR bloccanti
CREATE INDEX IF NOT EXISTS idx_qual_nc_blocks_sal ON quality.non_conformity(tenant_id, blocks_sal, status)
    WHERE blocks_sal = TRUE AND status NOT IN ('Closed', 'Waived');
