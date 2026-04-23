-- =============================================================================
-- 11_schema_external.sql
-- Schema: external
--
-- Gestione integrazioni con sistemi esterni (MS-11 External Sync Service).
-- Sistemi supportati: Procore, ACC (Autodesk), TeamSystem, Oracle Primavera P6,
-- ACDAT (CDE italiano via MS-08), IDA/Maxfone (telemetria energetica).
--
-- Tabelle:
--   ext_sync_config  → configurazione per sistema (endpoint, abilitazione, modo)
--   ext_sync_log     → log di ogni operazione di sync (audit trail)
--   ext_entity_map   → mappa bidirezionale ID-BuildTrust ↔ ID-sistema-esterno
-- =============================================================================

-- ─── ext_sync_config ─────────────────────────────────────────────────────────
-- Una riga per ogni sistema esterno integrato, per tenant.
-- Contiene la configurazione operativa ma NON le credenziali (in Secret Manager).
CREATE TABLE IF NOT EXISTS external.ext_sync_config (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID          NOT NULL REFERENCES tenant.company(id),
    -- Sistema esterno: PROCORE, ACC, TEAMSYSTEM, PRIMAVERA, ACDAT, IDA_MAXFONE
    system_name     VARCHAR(50)   NOT NULL,
    -- Se false, nessun sync automatico viene eseguito
    is_enabled      BOOLEAN       NOT NULL DEFAULT FALSE,
    sync_direction  VARCHAR(15)   NOT NULL DEFAULT 'INBOUND'
                    CHECK (sync_direction IN ('INBOUND','OUTBOUND','BIDIRECTIONAL')),
    -- MANUAL=su richiesta, SCHEDULED=automatico cron, WEBHOOK=push dal sistema esterno
    sync_mode       VARCHAR(15)   NOT NULL DEFAULT 'MANUAL'
                    CHECK (sync_mode IN ('MANUAL','SCHEDULED','WEBHOOK')),
    -- JSON con configurazione specifica (endpoint, riferimenti segreti, opzioni)
    -- Es: {"api_url": "https://api.procore.com/v1", "project_id": "12345",
    --       "secret_ref": "bt-platform-procore-token-prod"}
    config_json     JSONB         NOT NULL DEFAULT '{}',
    last_sync_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, system_name)
);
COMMENT ON TABLE external.ext_sync_config IS 'Configurazione per sistema esterno (Procore, ACC, TeamSystem, ACDAT, IDA). Le credenziali sono in Secret Manager.';

-- ─── ext_sync_log ────────────────────────────────────────────────────────────
-- Log di ogni operazione di sync: chi, cosa, quando, esito.
CREATE TABLE IF NOT EXISTS external.ext_sync_log (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         UUID          NOT NULL REFERENCES tenant.company(id),
    -- FK alla configurazione (nullable: per log storici senza config associata)
    config_id         UUID          REFERENCES external.ext_sync_config(id),
    -- Denormalizzato: il nome del sistema non richiede JOIN per leggere i log
    system_name       VARCHAR(50)   NOT NULL,
    direction         VARCHAR(15)   NOT NULL CHECK (direction IN ('INBOUND','OUTBOUND')),
    -- FULL_SYNC=sincronizzazione completa, INCREMENTAL=solo delta, WEBHOOK=evento push
    operation_type    VARCHAR(20)   NOT NULL,
    -- RUNNING=in esecuzione, SUCCESS=completato ok, PARTIAL=parziale, FAILED=errore
    status            VARCHAR(10)   NOT NULL DEFAULT 'RUNNING'
                      CHECK (status IN ('RUNNING','SUCCESS','PARTIAL','FAILED')),
    records_processed INTEGER       NOT NULL DEFAULT 0,
    records_failed    INTEGER       NOT NULL DEFAULT 0,
    error_message     TEXT,
    payload_summary   JSONB,  -- Riassunto (non il payload completo, per risparmiare spazio)
    started_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    completed_at      TIMESTAMPTZ
);
COMMENT ON TABLE external.ext_sync_log IS 'Audit log sync con sistemi esterni. Un record per ogni esecuzione (successo o fallimento).';

-- ─── ext_entity_map ──────────────────────────────────────────────────────────
-- Mappa bidirezionale: entità in BuildTrust ↔ entità nel sistema esterno.
-- Necessaria per: evitare duplicati, fare update invece di insert, tracciare cancellazioni.
-- Es: bim.bim_element uuid-abc → Procore "observation-12345"
--     document.document_ref uuid-xyz → ACC "urn:adsk.wip:dm.lineage:XXXX"
CREATE TABLE IF NOT EXISTS external.ext_entity_map (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID          NOT NULL REFERENCES tenant.company(id),
    system_name     VARCHAR(50)   NOT NULL,
    -- ID dell'entità nel sistema esterno (stringa: può essere numerico, UUID, URN, path)
    external_id     VARCHAR(500)  NOT NULL,
    -- Tipo entità nel sistema esterno (es. "Document", "RFI", "Task", "Observation")
    external_type   VARCHAR(100)  NOT NULL,
    -- UUID dell'entità in BuildTrust
    internal_id     UUID          NOT NULL,
    -- Nome tabella BuildTrust (es. "bim.bim_element", "document.document_ref")
    internal_type   VARCHAR(100)  NOT NULL,
    last_synced_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    -- active=mappatura valida, deleted=entità cancellata, stale=da risincronizzare
    sync_status     VARCHAR(20)   NOT NULL DEFAULT 'active'
                    CHECK (sync_status IN ('active','deleted','stale')),
    -- Es: {"last_hash": "sha256...", "external_version": "v2"} per rilevare modifiche
    metadata        JSONB         NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    -- La stessa entità esterna non può essere mappata due volte per stesso tenant+sistema
    UNIQUE (tenant_id, system_name, external_id, external_type)
);
COMMENT ON TABLE external.ext_entity_map IS 'Mappa bidirezionale BuildTrust ↔ sistemi esterni. Usata da MS-11 per sync idempotente.';

-- ─── Indici ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_ext_cfg_tenant    ON external.ext_sync_config(tenant_id);
CREATE INDEX IF NOT EXISTS idx_ext_cfg_system    ON external.ext_sync_config(system_name);
CREATE INDEX IF NOT EXISTS idx_ext_log_tenant    ON external.ext_sync_log(tenant_id);
CREATE INDEX IF NOT EXISTS idx_ext_log_system    ON external.ext_sync_log(system_name);
CREATE INDEX IF NOT EXISTS idx_ext_log_status    ON external.ext_sync_log(status);
CREATE INDEX IF NOT EXISTS idx_ext_log_started   ON external.ext_sync_log(started_at);
CREATE INDEX IF NOT EXISTS idx_ext_map_tenant    ON external.ext_entity_map(tenant_id);
CREATE INDEX IF NOT EXISTS idx_ext_map_system    ON external.ext_entity_map(system_name);
CREATE INDEX IF NOT EXISTS idx_ext_map_internal  ON external.ext_entity_map(internal_id, internal_type);
CREATE INDEX IF NOT EXISTS idx_ext_map_external  ON external.ext_entity_map(external_id, external_type);
