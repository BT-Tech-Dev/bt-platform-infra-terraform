-- =============================================================================
-- 02_schema_tenant.sql
-- Schema: tenant
--
-- VA ESEGUITO PRIMA DI TUTTI GLI ALTRI SCHEMI perché tutte le tabelle
-- degli altri schemi hanno una FK verso tenant.company(id).
--
-- Tabelle:
--   company      → l'azienda/cliente BuildTrust (ex "tenant.tenant")
--   project      → il progetto/opera all'interno della company (ex "tenant_project")
--   user_profile → profili utente della piattaforma
-- =============================================================================

-- ─── Funzione condivisa: aggiorna updated_at automaticamente ─────────────────
-- Questa funzione è usata da company e user_profile.
-- Deve esistere prima dei trigger che la richiamano.
CREATE OR REPLACE FUNCTION tenant.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ─── company ─────────────────────────────────────────────────────────────────
-- L'entità principale di multi-tenancy: ogni company = un cliente BuildTrust.
-- Esempio: "Consorzio Stabile Lavori" è la company, e ha il progetto "Ponte Po Levante".
CREATE TABLE IF NOT EXISTS tenant.company (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Codice breve univoco (es. "PPDL", "BAL2") — usato nei nomi risorse GCP
    code        VARCHAR(20)  NOT NULL UNIQUE,
    -- Nome completo del cliente/progetto
    name        VARCHAR(255) NOT NULL,
    description TEXT,
    -- active = operativo, suspended = temporaneamente bloccato, archived = storico
    status      VARCHAR(20)  NOT NULL DEFAULT 'active'
                CHECK (status IN ('active', 'suspended', 'archived')),
    -- Configurazione JSON per company (es. bucket prefix, codice progetto Revit)
    -- JSONB = JSON binario, più efficiente per query con operatori ->/->>
    -- Es: {"revit_project_code": "0549-IDG", "gcs_prefix": "ppdl/"}
    config      JSONB        NOT NULL DEFAULT '{}',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE tenant.company IS 'Tenant della piattaforma: ogni company = cliente BuildTrust con uno o più progetti.';
COMMENT ON COLUMN tenant.company.code IS 'Codice breve univoco (es. PPDL per Ponte Po di Levante, BAL2 per Balocco 2)';

CREATE INDEX IF NOT EXISTS idx_company_code   ON tenant.company(code);
CREATE INDEX IF NOT EXISTS idx_company_status ON tenant.company(status);

DROP TRIGGER IF EXISTS trg_company_updated_at ON tenant.company;
CREATE TRIGGER trg_company_updated_at
    BEFORE UPDATE ON tenant.company
    FOR EACH ROW EXECUTE FUNCTION tenant.update_updated_at();

-- ─── project ─────────────────────────────────────────────────────────────────
-- Progetto/opera specifico all'interno di una company.
-- Una company può avere più progetti (es. lotti diversi della stessa opera).
CREATE TABLE IF NOT EXISTS tenant.project (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- FK alla company proprietaria del progetto
    tenant_id    UUID         NOT NULL REFERENCES tenant.company(id) ON DELETE CASCADE,
    project_code VARCHAR(50)  NOT NULL,  -- Es. "0549-IDG"
    project_name VARCHAR(255) NOT NULL,
    status       VARCHAR(20)  NOT NULL DEFAULT 'active'
                 CHECK (status IN ('active', 'completed', 'suspended')),
    started_at   DATE,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, project_code)
);
COMMENT ON TABLE tenant.project IS 'Progetti all''interno di una company. Una company può avere più lotti/progetti.';

CREATE INDEX IF NOT EXISTS idx_project_tenant_id ON tenant.project(tenant_id);

-- ─── user_profile ─────────────────────────────────────────────────────────────
-- Profilo applicativo degli utenti della piattaforma.
-- L'autenticazione è delegata a Keycloak (Layer 1): qui i metadati applicativi.
CREATE TABLE IF NOT EXISTS tenant.user_profile (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Company a cui appartiene questo utente
    tenant_id       UUID          NOT NULL REFERENCES tenant.company(id) ON DELETE CASCADE,
    -- Email = chiave di lookup dal JWT Keycloak (sub o email claim)
    email           VARCHAR(255)  NOT NULL UNIQUE,
    full_name       VARCHAR(255),
    -- ADMIN=amministratore tenant, PM=project manager, SITE_ENGINEER=ingegnere cantiere,
    -- VIEWER=solo lettura, AUDITOR=report e audit SAL
    role            VARCHAR(30)   NOT NULL DEFAULT 'VIEWER'
                    CHECK (role IN ('ADMIN', 'PM', 'SITE_ENGINEER', 'VIEWER', 'AUDITOR')),
    is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
    last_login_at   TIMESTAMPTZ,
    -- Es: {"language": "it", "theme": "dark", "notifications": {"sal": true, "nc": true}}
    preferences     JSONB         NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE tenant.user_profile IS 'Profili utente BuildTrust. Email corrisponde al claim JWT di Keycloak.';

CREATE INDEX IF NOT EXISTS idx_user_profile_tenant ON tenant.user_profile(tenant_id);
CREATE INDEX IF NOT EXISTS idx_user_profile_email  ON tenant.user_profile(email);
CREATE INDEX IF NOT EXISTS idx_user_profile_role   ON tenant.user_profile(role);

DROP TRIGGER IF EXISTS trg_user_profile_updated_at ON tenant.user_profile;
CREATE TRIGGER trg_user_profile_updated_at
    BEFORE UPDATE ON tenant.user_profile
    FOR EACH ROW EXECUTE FUNCTION tenant.update_updated_at();
