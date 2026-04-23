-- =============================================================================
-- migrate_04_external_replace.sql
-- Schema: external — rimuove vecchie tabelle, aggiunge le nuove
--
-- COSA FA:
--   Rimuove: acdat_element, external_sync_log
--   Aggiunge: ext_sync_config, ext_sync_log, ext_entity_map
--
-- PERCHÉ:
--   Le vecchie tabelle avevano nomi generici e struttura incompleta.
--   Le nuove tabelle coprono l'intera architettura MS-11 External Sync:
--     ext_sync_config  → configurazione per ogni sistema esterno (credenziali, endpoint)
--     ext_sync_log     → log di ogni operazione di sync (chi, cosa, quando, esito)
--     ext_entity_map   → mappa bidirezionale ID-BuildTrust ↔ ID-sistema-esterno
--
-- ATTENZIONE:
--   Il DROP su acdat_element rimuove anche i dati (se presenti).
--   Sul nuovo progetto bt-platform-prod queste tabelle sono vuote.
--   Se ci sono dati da conservare, fare backup prima.
-- =============================================================================

BEGIN;

-- ─── Rimuovi vecchie tabelle ─────────────────────────────────────────────────

-- DROP acdat_element (vecchia cache ACDAT — sostituita da document.acdat_sync_log)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'external' AND table_name = 'acdat_element'
    ) THEN
        DROP TABLE external.acdat_element CASCADE;
        RAISE NOTICE 'Rimossa: external.acdat_element';
    ELSE
        RAISE NOTICE 'SKIP: external.acdat_element non trovata';
    END IF;
END $$;

-- DROP external_sync_log (nome generico — sostituita da ext_sync_log)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'external' AND table_name = 'external_sync_log'
    ) THEN
        DROP TABLE external.external_sync_log CASCADE;
        RAISE NOTICE 'Rimossa: external.external_sync_log';
    ELSE
        RAISE NOTICE 'SKIP: external.external_sync_log non trovata';
    END IF;
END $$;

-- ─── ext_sync_config ─────────────────────────────────────────────────────────
-- Configurazione per ogni sistema esterno integrato (MS-11 External Sync).
-- Un record per ogni sistema per tenant. Contiene endpoint, abilitazione, frequenza.
-- Le credenziali NON sono qui: vanno in Secret Manager e referenziate in config_json.
CREATE TABLE IF NOT EXISTS external.ext_sync_config (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID          NOT NULL REFERENCES tenant.tenant(id),
    -- PROCORE, ACC (Autodesk), TEAMSYSTEM, PRIMAVERA, ACDAT, IDA_MAXFONE
    system_name     VARCHAR(50)   NOT NULL,
    -- Se false, il sync non viene eseguito neanche se schedulato
    is_enabled      BOOLEAN       NOT NULL DEFAULT FALSE,
    -- INBOUND=esterno→BT, OUTBOUND=BT→esterno, BIDIRECTIONAL
    sync_direction  VARCHAR(15)   NOT NULL DEFAULT 'INBOUND'
                    CHECK (sync_direction IN ('INBOUND','OUTBOUND','BIDIRECTIONAL')),
    -- MANUAL=solo su richiesta, SCHEDULED=automatico, WEBHOOK=push da esterno
    sync_mode       VARCHAR(15)   NOT NULL DEFAULT 'MANUAL'
                    CHECK (sync_mode IN ('MANUAL','SCHEDULED','WEBHOOK')),
    -- Configurazione JSON: endpoint, riferimenti a segreti, opzioni specifiche
    -- Es: {"api_url": "https://api.procore.com", "secret_ref": "bt-platform-procore-token-prod"}
    config_json     JSONB         NOT NULL DEFAULT '{}',
    last_sync_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    -- Un sistema = una configurazione per tenant
    UNIQUE (tenant_id, system_name)
);
COMMENT ON TABLE external.ext_sync_config IS 'Configurazione integrazioni esterne (Procore, ACC, TeamSystem, Primavera, ACDAT, IDA). Non contiene credenziali (in Secret Manager).';

-- ─── ext_sync_log ────────────────────────────────────────────────────────────
-- Log di ogni operazione di sync con sistemi esterni.
-- Struttura più pulita della vecchia "external_sync_log": aggiunge FK a config.
CREATE TABLE IF NOT EXISTS external.ext_sync_log (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         UUID          NOT NULL REFERENCES tenant.tenant(id),
    -- FK alla configurazione del sistema (nullable: log storici prima della config)
    config_id         UUID          REFERENCES external.ext_sync_config(id),
    -- Nome sistema (denormalizzato per leggibilità dei log anche senza JOIN)
    system_name       VARCHAR(50)   NOT NULL,
    direction         VARCHAR(15)   NOT NULL CHECK (direction IN ('INBOUND','OUTBOUND')),
    -- FULL_SYNC=tutto, INCREMENTAL=solo modifiche, WEBHOOK=evento push, MANUAL=manuale
    operation_type    VARCHAR(20)   NOT NULL,
    -- RUNNING=in corso, SUCCESS=ok, PARTIAL=parziale, FAILED=errore
    status            VARCHAR(10)   NOT NULL DEFAULT 'RUNNING'
                      CHECK (status IN ('RUNNING','SUCCESS','PARTIAL','FAILED')),
    records_processed INTEGER       NOT NULL DEFAULT 0,
    records_failed    INTEGER       NOT NULL DEFAULT 0,
    error_message     TEXT,
    -- Riassunto del payload (per debug, non il payload completo)
    payload_summary   JSONB,
    started_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    completed_at      TIMESTAMPTZ
);
COMMENT ON TABLE external.ext_sync_log IS 'Log audit operazioni di sync con sistemi esterni. Un record per ogni esecuzione di sync.';

-- ─── ext_entity_map ──────────────────────────────────────────────────────────
-- Mappa bidirezionale tra entità BuildTrust e entità nei sistemi esterni.
-- Esempio: elemento BIM uuid-123 in BuildTrust ↔ "element-456" in Procore
-- Questo permette di sincronizzare senza duplicati e di fare lookup in entrambe le direzioni.
CREATE TABLE IF NOT EXISTS external.ext_entity_map (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID          NOT NULL REFERENCES tenant.tenant(id),
    -- Nome sistema esterno (stesso valore di ext_sync_config.system_name)
    system_name     VARCHAR(50)   NOT NULL,
    -- ID dell'entità nel sistema esterno (stringa: può essere numerico, UUID, path)
    external_id     VARCHAR(500)  NOT NULL,
    -- Tipo entità nel sistema esterno (es. "Document", "RFI", "Task", "Element")
    external_type   VARCHAR(100)  NOT NULL,
    -- UUID dell'entità in BuildTrust (es. bim_element.id, document_ref.id)
    internal_id     UUID          NOT NULL,
    -- Nome tabella BuildTrust dell'entità (es. "bim.bim_element", "document.document_ref")
    internal_type   VARCHAR(100)  NOT NULL,
    last_synced_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    -- active=mappatura attiva, deleted=entità rimossa, stale=da risincronizzare
    sync_status     VARCHAR(20)   NOT NULL DEFAULT 'active'
                    CHECK (sync_status IN ('active','deleted','stale')),
    -- Dati extra (es. hash dell'ultimo stato sincronizzato per rilevare modifiche)
    metadata        JSONB         NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    -- Stessa entità esterna non può essere mappata due volte per stesso tenant+sistema
    UNIQUE (tenant_id, system_name, external_id, external_type)
);
COMMENT ON TABLE external.ext_entity_map IS 'Mappa bidirezionale BuildTrust ↔ sistemi esterni. Usata da MS-11 per evitare duplicati nel sync.';

-- ─── Indici ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_ext_cfg_tenant     ON external.ext_sync_config(tenant_id);
CREATE INDEX IF NOT EXISTS idx_ext_cfg_system     ON external.ext_sync_config(system_name);
CREATE INDEX IF NOT EXISTS idx_ext_log_tenant     ON external.ext_sync_log(tenant_id);
CREATE INDEX IF NOT EXISTS idx_ext_log_system     ON external.ext_sync_log(system_name);
CREATE INDEX IF NOT EXISTS idx_ext_log_status     ON external.ext_sync_log(status);
CREATE INDEX IF NOT EXISTS idx_ext_log_started    ON external.ext_sync_log(started_at);
CREATE INDEX IF NOT EXISTS idx_ext_map_tenant     ON external.ext_entity_map(tenant_id);
CREATE INDEX IF NOT EXISTS idx_ext_map_system     ON external.ext_entity_map(system_name);
CREATE INDEX IF NOT EXISTS idx_ext_map_internal   ON external.ext_entity_map(internal_id, internal_type);
CREATE INDEX IF NOT EXISTS idx_ext_map_external   ON external.ext_entity_map(external_id, external_type);

COMMIT;
