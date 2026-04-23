-- =============================================================================
-- 09_schema_document.sql
-- Schema: document
--
-- Registro dei documenti della piattaforma e log delle sincronizzazioni ACDAT.
--
-- Tabelle:
--   document_ref  → metadati di ogni file caricato su GCS
--                   (BIM JSON, contratti PDF, computi XLSX, DDT, certificati)
--   acdat_sync_log → log operazioni di sync con ACDAT CDE (MS-08 ACDAT Connector)
--
-- I FILE NON sono in questa tabella — sono su GCS.
-- Qui si trovano solo i metadati: chi, cosa, quando, dove, stato.
-- =============================================================================

-- ─── document_ref ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS document.document_ref (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID          NOT NULL REFERENCES tenant.company(id),
    -- Codice numerico nel sistema documentale del progetto
    -- Es: "0549-IDG-PPDL-L00-A-INF-3D-A" (da norma UNI 11337)
    doc_code        VARCHAR(100),
    -- Tipo documento (determina quale parser MS usare)
    doc_type        VARCHAR(50)   NOT NULL
                    CHECK (doc_type IN ('BIM_JSON','CONTRACT_PDF','BOQ_XLSX',
                                        'DDT_PDF','CERTIFICATE_PDF','GANTT',
                                        'PHOTO','OTHER')),
    -- Titolo leggibile (es. "Modello BIM strutture aprile 2026")
    title           VARCHAR(255),
    -- Nome file originale (es. "0549-IDG-PPDL-L00-A-INF-3D-A.json")
    file_name       VARCHAR(512)  NOT NULL,
    -- Path completo GCS (es. "gs://bt-platform-staging-prod/uploads/file.json")
    gcs_path        TEXT          NOT NULL,
    file_size_bytes BIGINT,
    -- SHA-256 del file: per verifica integrità e deduplicazione
    file_hash       VARCHAR(64),
    mime_type       VARCHAR(100),
    -- Versione numerica del documento (1 = primo caricamento)
    version_num     INTEGER       NOT NULL DEFAULT 1,
    -- Revisione da norma progettuale (A, B, C ...)
    revision        VARCHAR(10),
    -- uploaded → processing → processed | failed | archived
    status          VARCHAR(20)   NOT NULL DEFAULT 'uploaded'
                    CHECK (status IN ('uploaded','processing','processed','failed','archived')),
    -- Tipo entità correlata (es. 'bim_model', 'sal', 'work_progress')
    related_entity_type VARCHAR(50),
    -- UUID dell'entità correlata (no FK: può referenziare tabelle diverse)
    related_entity_id   UUID,
    metadata        JSONB         NOT NULL DEFAULT '{}',
    uploaded_by     VARCHAR(255),
    uploaded_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    processed_at    TIMESTAMPTZ
);
COMMENT ON TABLE document.document_ref IS 'Registro metadati documenti su GCS: BIM JSON, contratti, computi, DDT, certificati.';

-- ─── acdat_sync_log ───────────────────────────────────────────────────────────
-- Log di ogni operazione verso ACDAT (CDE italiano).
-- ACDAT = piattaforma CDE (Common Data Environment) obbligatoria per grandi opere.
-- Gestita da MS-08 ACDAT Connector.
CREATE TABLE IF NOT EXISTS document.acdat_sync_log (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID          NOT NULL REFERENCES tenant.company(id),
    -- ID documento nel sistema ACDAT (assegnato da ACDAT, stabile)
    acdat_document_id   VARCHAR(255),
    -- INBOUND = ACDAT→BuildTrust (download), OUTBOUND = BuildTrust→ACDAT (upload)
    direction           VARCHAR(10)   NOT NULL
                        CHECK (direction IN ('INBOUND','OUTBOUND')),
    -- CREATE=nuovo, UPDATE=revisione, DELETE=rimozione, DOWNLOAD=scarica, STATUS_CHECK=verifica
    operation_type      VARCHAR(20)   NOT NULL
                        CHECK (operation_type IN ('CREATE','UPDATE','DELETE','DOWNLOAD','STATUS_CHECK')),
    status              VARCHAR(10)   NOT NULL DEFAULT 'PENDING'
                        CHECK (status IN ('SUCCESS','FAILED','PENDING')),
    -- FK al documento in document_ref (se il sync riguarda un file specifico)
    document_ref_id     UUID          REFERENCES document.document_ref(id),
    request_payload     JSONB,      -- Payload inviato ad ACDAT
    response_payload    JSONB,      -- Risposta ricevuta da ACDAT
    error_message       TEXT,
    synced_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE document.acdat_sync_log IS 'Log operazioni MS-08 ACDAT Connector. Traccia upload/download verso CDE italiano.';

-- ─── Indici ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_doc_ref_tenant    ON document.document_ref(tenant_id);
CREATE INDEX IF NOT EXISTS idx_doc_ref_type      ON document.document_ref(doc_type);
CREATE INDEX IF NOT EXISTS idx_doc_ref_status    ON document.document_ref(status);
CREATE INDEX IF NOT EXISTS idx_doc_ref_hash      ON document.document_ref(file_hash);
CREATE INDEX IF NOT EXISTS idx_doc_ref_uploaded  ON document.document_ref(uploaded_at);
CREATE INDEX IF NOT EXISTS idx_acdat_log_tenant  ON document.acdat_sync_log(tenant_id);
CREATE INDEX IF NOT EXISTS idx_acdat_log_status  ON document.acdat_sync_log(status);
CREATE INDEX IF NOT EXISTS idx_acdat_log_doc_ref ON document.acdat_sync_log(document_ref_id);
