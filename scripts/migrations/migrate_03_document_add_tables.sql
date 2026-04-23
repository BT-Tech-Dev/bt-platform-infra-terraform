-- =============================================================================
-- migrate_03_document_add_tables.sql
-- Schema: document — aggiunge document_ref e acdat_sync_log
--
-- COSA FA:
--   Se esiste la vecchia tabella "document.document", la rinomina in "document_ref".
--   Se non esiste, crea "document_ref" da zero.
--   In entrambi i casi aggiunge "acdat_sync_log".
--
-- PERCHÉ:
--   "document_ref" è il registro dei file caricati su GCS (BIM JSON, contratti,
--   computi metrici, DDT, certificati). La vecchia tabella "document" aveva lo
--   stesso scopo ma nome ambiguo (document.document è ridondante).
--   "acdat_sync_log" traccia tutte le operazioni di sync con ACDAT CDE (MS-08).
-- =============================================================================

BEGIN;

-- ─── Gestione tabella document_ref ──────────────────────────────────────────
DO $$
BEGIN
    -- CASO 1: esiste già "document.document" → rinominala
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'document' AND table_name = 'document'
    ) THEN
        -- Rinomina la tabella esistente
        ALTER TABLE document.document RENAME TO document_ref;
        -- Aggiungi le colonne mancanti rispetto al nuovo schema
        -- (IF NOT EXISTS per sicurezza nel caso lo script venga rieseguito)
        ALTER TABLE document.document_ref
            ADD COLUMN IF NOT EXISTS doc_code      VARCHAR(100),
            ADD COLUMN IF NOT EXISTS title         VARCHAR(255),
            ADD COLUMN IF NOT EXISTS version_num   INTEGER NOT NULL DEFAULT 1,
            ADD COLUMN IF NOT EXISTS revision      VARCHAR(10),
            ADD COLUMN IF NOT EXISTS related_entity_type VARCHAR(50),
            ADD COLUMN IF NOT EXISTS related_entity_id   UUID;
        -- Rinomina "status" → riusa lo stesso, ma aggiungi CHECK aggiornato se non c'è
        RAISE NOTICE 'OK: document.document rinominata in document.document_ref + colonne aggiunte';

    -- CASO 2: lo schema è vuoto → crea document_ref da zero
    ELSIF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'document' AND table_name = 'document_ref'
    ) THEN
        CREATE TABLE document.document_ref (
            id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            tenant_id       UUID          NOT NULL REFERENCES tenant.tenant(id),
            -- Codice numerico del documento nel sistema documentale del progetto
            -- Es: "0549-IDG-PPDL-L00-A-INF-3D-A" per il BIM JSON
            doc_code        VARCHAR(100),
            -- Tipo documento: determina il parser da usare (MS-01, MS-02, MS-03, MS-04)
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
            -- Revisione alfabetica (A, B, C → da specifiche progettuali)
            revision        VARCHAR(10),
            -- uploaded = caricato, processing = in elaborazione dal parser,
            -- processed = elaborato con successo, failed = errore parser, archived = archiviato
            status          VARCHAR(20)   NOT NULL DEFAULT 'uploaded'
                            CHECK (status IN ('uploaded','processing','processed','failed','archived')),
            -- Tipo entità a cui si riferisce questo documento (es. 'bim_model', 'sal', 'work_progress')
            related_entity_type VARCHAR(50),
            -- UUID dell'entità correlata (nessun FK perché può referenziare più tabelle diverse)
            related_entity_id   UUID,
            -- Metadati extra (es. versione Revit, numero SAL associato)
            metadata        JSONB         NOT NULL DEFAULT '{}',
            uploaded_by     VARCHAR(255),
            uploaded_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
            processed_at    TIMESTAMPTZ
        );
        COMMENT ON TABLE document.document_ref IS 'Registro documenti su GCS: BIM JSON, contratti PDF, computi XLSX, DDT, certificati.';
        RAISE NOTICE 'OK: creata document.document_ref da zero';
    ELSE
        RAISE NOTICE 'SKIP: document.document_ref esiste già';
    END IF;
END $$;

-- ─── acdat_sync_log ───────────────────────────────────────────────────────────
-- Log di ogni operazione di sync con ACDAT (CDE italiano — MS-08 ACDAT Connector).
-- ACDAT è il Common Data Environment italiano obbligatorio per grandi opere pubbliche.
CREATE TABLE IF NOT EXISTS document.acdat_sync_log (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID          NOT NULL REFERENCES tenant.tenant(id),
    -- ID del documento nel sistema ACDAT (assegnato da ACDAT, stabile)
    acdat_document_id   VARCHAR(255),
    -- INBOUND = ACDAT → BuildTrust (download), OUTBOUND = BuildTrust → ACDAT (upload)
    direction           VARCHAR(10)   NOT NULL
                        CHECK (direction IN ('INBOUND','OUTBOUND')),
    -- Tipo operazione: CREATE=nuovo doc, UPDATE=revisione, DELETE=rimozione, DOWNLOAD=scarica
    operation_type      VARCHAR(20)   NOT NULL
                        CHECK (operation_type IN ('CREATE','UPDATE','DELETE','DOWNLOAD','STATUS_CHECK')),
    -- Esito: SUCCESS, FAILED, PENDING (in attesa risposta ACDAT)
    status              VARCHAR(10)   NOT NULL DEFAULT 'PENDING'
                        CHECK (status IN ('SUCCESS','FAILED','PENDING')),
    -- FK al record in document_ref (se il sync riguarda un documento specifico)
    document_ref_id     UUID          REFERENCES document.document_ref(id),
    -- Payload inviato ad ACDAT (per debug e replay)
    request_payload     JSONB,
    -- Risposta ricevuta da ACDAT
    response_payload    JSONB,
    -- Messaggio di errore (compilato solo se status = 'FAILED')
    error_message       TEXT,
    synced_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE document.acdat_sync_log IS 'Log operazioni ACDAT (CDE italiano). Alimentato da MS-08 ACDAT Connector.';

-- ─── Indici ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_doc_ref_tenant     ON document.document_ref(tenant_id);
CREATE INDEX IF NOT EXISTS idx_doc_ref_type       ON document.document_ref(doc_type);
CREATE INDEX IF NOT EXISTS idx_doc_ref_status     ON document.document_ref(status);
CREATE INDEX IF NOT EXISTS idx_doc_ref_hash       ON document.document_ref(file_hash);
CREATE INDEX IF NOT EXISTS idx_doc_ref_uploaded   ON document.document_ref(uploaded_at);
CREATE INDEX IF NOT EXISTS idx_acdat_log_tenant   ON document.acdat_sync_log(tenant_id);
CREATE INDEX IF NOT EXISTS idx_acdat_log_status   ON document.acdat_sync_log(status);
CREATE INDEX IF NOT EXISTS idx_acdat_log_doc_ref  ON document.acdat_sync_log(document_ref_id);

COMMIT;
