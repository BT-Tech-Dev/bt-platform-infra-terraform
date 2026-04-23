-- =============================================================================
-- migrate_06_tenant_rename.sql
-- Schema: tenant — rinomina tabelle, aggiunge user_profile
--
-- ESEGUIRE PER ULTIMO (dipende da tutte le altre migrazioni).
--
-- COSA FA:
--   1. Rinomina tenant.tenant → tenant.company
--   2. Rinomina tenant.tenant_project → tenant.project
--   3. Crea tenant.user_profile
--
-- NOTA CRITICA SUI FK:
--   Tutte le tabelle negli altri schemi hanno:
--     tenant_id UUID NOT NULL REFERENCES tenant.tenant(id)
--   Dopo la rinomina, PostgreSQL aggiorna AUTOMATICAMENTE questi FK per puntare
--   a tenant.company(id). I valori UUID non cambiano — cambia solo il nome della tabella
--   di riferimento. NON è necessario ALTER TABLE sulle altre tabelle.
--   (PostgreSQL traccia i FK per OID della tabella, non per nome)
--
-- PERCHÉ rinominare:
--   "tenant.tenant" è ridondante (schema.nome_uguale_allo_schema).
--   "company" comunica meglio il significato: l'entità cliente/azienda.
--   "project" è più chiaro di "tenant_project" per un sotto-progetto.
-- =============================================================================

BEGIN;

-- ─── Rinomina tenant → company ───────────────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'tenant' AND table_name = 'tenant'
    ) THEN
        ALTER TABLE tenant.tenant RENAME TO company;
        -- Rinomina anche indice e trigger se hanno nomi legati alla vecchia tabella
        -- (PostgreSQL non rinomina indici e trigger automaticamente con RENAME TABLE)
        IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'tenant' AND indexname = 'idx_tenant_code') THEN
            ALTER INDEX tenant.idx_tenant_code RENAME TO idx_company_code;
        END IF;
        DROP TRIGGER IF EXISTS trg_tenant_updated_at ON tenant.company;
        -- Ricrea il trigger con nome aggiornato (la funzione update_updated_at rimane)
        CREATE TRIGGER trg_company_updated_at
            BEFORE UPDATE ON tenant.company
            FOR EACH ROW EXECUTE FUNCTION tenant.update_updated_at();
        RAISE NOTICE 'OK: tenant.tenant rinominata in tenant.company';
    ELSE
        RAISE NOTICE 'SKIP: tenant.tenant non trovata (già rinominata o non esiste)';
    END IF;
END $$;

-- ─── Rinomina tenant_project → project ──────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'tenant' AND table_name = 'tenant_project'
    ) THEN
        ALTER TABLE tenant.tenant_project RENAME TO project;
        IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'tenant' AND indexname = 'idx_tenant_project_tenant_id') THEN
            ALTER INDEX tenant.idx_tenant_project_tenant_id RENAME TO idx_project_tenant_id;
        END IF;
        RAISE NOTICE 'OK: tenant.tenant_project rinominata in tenant.project';
    ELSE
        RAISE NOTICE 'SKIP: tenant.tenant_project non trovata (già rinominata o non esiste)';
    END IF;
END $$;

-- ─── user_profile ─────────────────────────────────────────────────────────────
-- Profilo utente della piattaforma BuildTrust.
-- Ogni utente appartiene a una company (tenant). In futuro sarà gestito da Keycloak,
-- ma qui manteniamo i metadati applicativi (ruolo, preferenze, ultima sessione).
CREATE TABLE IF NOT EXISTS tenant.user_profile (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Company (tenant) a cui appartiene questo utente
    tenant_id UUID NOT NULL REFERENCES tenant.company(id) ON DELETE CASCADE,
    -- Email univoca sulla piattaforma (anche chiave di lookup da Keycloak JWT)
    email           VARCHAR(255)  NOT NULL UNIQUE,
    full_name       VARCHAR(255),
    -- ADMIN=amministratore tenant, PM=project manager, SITE_ENGINEER=ingegnere cantiere,
    -- VIEWER=solo lettura, AUDITOR=audit e report
    role            VARCHAR(30)   NOT NULL DEFAULT 'VIEWER'
                    CHECK (role IN ('ADMIN','PM','SITE_ENGINEER','VIEWER','AUDITOR')),
    is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
    last_login_at   TIMESTAMPTZ,
    -- Preferenze interfaccia (lingua, tema, notifiche)
    -- Es: {"language": "it", "theme": "dark", "notifications": {"sal": true}}
    preferences     JSONB         NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE tenant.user_profile IS 'Profilo utenti BuildTrust. Email = chiave di correlazione con Keycloak JWT (Layer 1 autenticazione).';

-- ─── Indici ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_user_profile_tenant ON tenant.user_profile(tenant_id);
CREATE INDEX IF NOT EXISTS idx_user_profile_email  ON tenant.user_profile(email);
CREATE INDEX IF NOT EXISTS idx_user_profile_role   ON tenant.user_profile(role);

-- ─── Trigger updated_at su user_profile ──────────────────────────────────────
DROP TRIGGER IF EXISTS trg_user_profile_updated_at ON tenant.user_profile;
CREATE TRIGGER trg_user_profile_updated_at
    BEFORE UPDATE ON tenant.user_profile
    FOR EACH ROW EXECUTE FUNCTION tenant.update_updated_at();

-- ─── Verifica finale ─────────────────────────────────────────────────────────
DO $$
DECLARE
    company_exists     BOOLEAN;
    project_exists     BOOLEAN;
    user_profile_exists BOOLEAN;
BEGIN
    SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='tenant' AND table_name='company')       INTO company_exists;
    SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='tenant' AND table_name='project')       INTO project_exists;
    SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='tenant' AND table_name='user_profile')  INTO user_profile_exists;

    IF company_exists AND project_exists AND user_profile_exists THEN
        RAISE NOTICE 'OK: schema tenant ha company, project, user_profile';
    ELSE
        RAISE WARNING 'ATTENZIONE: company=% project=% user_profile=%',
            company_exists, project_exists, user_profile_exists;
    END IF;
END $$;

COMMIT;
