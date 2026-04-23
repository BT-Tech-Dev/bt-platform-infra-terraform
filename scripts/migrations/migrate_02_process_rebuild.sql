-- =============================================================================
-- migrate_02_process_rebuild.sql
-- Schema: process — aggiunge le tabelle contrattuali
--
-- ESEGUIRE DOPO migrate_01 (le WBS devono essere già in bim).
--
-- COSA FA:
--   Aggiunge le tabelle che descrivono il contratto d'appalto:
--     contract           → contratto principale (importo, date, appaltatore)
--     clause             → clausole del contratto (testo legale)
--     payment_condition  → condizioni di pagamento SAL (percentuali, trigger)
--     milestone          → tappe contrattuali (date pianificate/effettive)
--     gantt_activity     → attività Gantt importate da MS Project (WBS Gantt)
--
-- PERCHÉ:
--   Lo schema "process" diventa il dominio contrattuale: contiene tutto
--   ciò che viene importato dai documenti di appalto (PDF contratto,
--   Excel computo, MPP Gantt). Questi dati alimenteranno MS-02, MS-03, MS-04.
--
-- SICURO DA RIESEGUIRE: usa CREATE TABLE IF NOT EXISTS.
-- =============================================================================

BEGIN;

-- ─── contract ─────────────────────────────────────────────────────────────────
-- Il contratto d'appalto principale tra BuildTrust e l'appaltatore.
-- Un tenant può avere più contratti (es. lotto strutture + lotto finiture).
CREATE TABLE IF NOT EXISTS process.contract (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Multi-tenancy: ogni contratto appartiene a un tenant (progetto)
    tenant_id       UUID         NOT NULL REFERENCES tenant.tenant(id),
    -- Numero contratto (es. "CDA-2025-0549-001")
    contract_number VARCHAR(100) NOT NULL,
    description     TEXT,
    -- Nome dell'appaltatore (es. "Consorzio Stabile Lavori SpA")
    contractor_name VARCHAR(255),
    -- Valore economico totale del contratto (in valuta)
    contract_value  NUMERIC(18,2),
    currency        VARCHAR(3)   NOT NULL DEFAULT 'EUR',
    signed_date     DATE,
    start_date      DATE,
    end_date        DATE,
    -- draft=bozza, active=in esecuzione, completed=concluso, terminated=risolto
    status          VARCHAR(20)  NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft', 'active', 'completed', 'terminated', 'suspended')),
    -- Dati aggiuntivi (es. riferimenti legali, norme applicabili)
    metadata        JSONB        NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, contract_number)
);
COMMENT ON TABLE process.contract IS 'Contratti d''appalto. Alimentato da MS-02 Contract Parser (PDF/DOCX).';

-- ─── clause ───────────────────────────────────────────────────────────────────
-- Singole clausole estratte dal contratto (da LLM o manuale).
CREATE TABLE IF NOT EXISTS process.clause (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID         NOT NULL REFERENCES tenant.tenant(id),
    contract_id     UUID         NOT NULL REFERENCES process.contract(id) ON DELETE CASCADE,
    -- Numero/codice della clausola (es. "Art. 12", "Clausola 3.1")
    clause_number   VARCHAR(50),
    title           VARCHAR(255),
    -- Testo integrale della clausola
    body            TEXT,
    -- Tipo clausola: GENERAL=generale, PAYMENT=pagamento, PENALTY=penale,
    -- VARIATION=variante, GUARANTEE=garanzia, TERMINATION=risoluzione
    clause_type     VARCHAR(30)  NOT NULL DEFAULT 'GENERAL'
                    CHECK (clause_type IN ('GENERAL','PAYMENT','PENALTY','VARIATION',
                                           'GUARANTEE','TERMINATION','COMPLIANCE','OTHER')),
    -- Flag: se true, questa clausola impatta il calcolo SAL
    impacts_sal     BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE process.clause IS 'Clausole contrattuali estratte via LLM da MS-02 Contract Parser.';

-- ─── payment_condition ────────────────────────────────────────────────────────
-- Condizioni di pagamento SAL: definiscono quando e quanto pagare.
-- Es: "Al raggiungimento del 30% SAL → emettere SAL n.1 pari al 30% del contratto"
CREATE TABLE IF NOT EXISTS process.payment_condition (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID         NOT NULL REFERENCES tenant.tenant(id),
    contract_id     UUID         NOT NULL REFERENCES process.contract(id) ON DELETE CASCADE,
    -- Codice breve (es. "PAY-01", "SAL-ACCONTO")
    condition_code  VARCHAR(50),
    description     TEXT,
    -- Percentuale del contratto da pagare (es. 30.00 = 30%)
    percentage      NUMERIC(6,3)
                    CHECK (percentage > 0 AND percentage <= 100),
    -- Quando si attiva il pagamento:
    --   SAL_MILESTONE = al raggiungimento di un SAL target
    --   DATE = alla data specifica
    --   DELIVERY = alla consegna di un documento/opera
    --   COMPLETION = al completamento del contratto
    trigger_type    VARCHAR(30)  NOT NULL DEFAULT 'SAL_MILESTONE'
                    CHECK (trigger_type IN ('SAL_MILESTONE','DATE','DELIVERY','COMPLETION','ADVANCE')),
    -- Giorni per il pagamento (D+30 dal SAL = 30 giorni dalla certificazione)
    days_to_pay     INTEGER      NOT NULL DEFAULT 30
                    CHECK (days_to_pay > 0),
    -- Flag: se true, questo pagamento è subordinato al check NC
    requires_nc_clearance BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE process.payment_condition IS 'Condizioni di pagamento SAL: percentuali, trigger, giorni di pagamento. Input per SAL Engine.';

-- ─── milestone ────────────────────────────────────────────────────────────────
-- Tappe fondamentali del contratto con date pianificate/effettive.
-- Es: "Consegna armature" prevista 2025-03-15, effettiva 2025-03-18 → ritardo 3gg
CREATE TABLE IF NOT EXISTS process.milestone (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID         NOT NULL REFERENCES tenant.tenant(id),
    contract_id     UUID         NOT NULL REFERENCES process.contract(id) ON DELETE CASCADE,
    -- Codice milestone (es. "M01", "CONS-FONDAZ")
    code            VARCHAR(50),
    name            VARCHAR(255) NOT NULL,
    description     TEXT,
    planned_date    DATE,
    actual_date     DATE,
    -- PLANNED=pianificata, IN_PROGRESS=in corso, COMPLETED=completata, DELAYED=in ritardo
    status          VARCHAR(20)  NOT NULL DEFAULT 'PLANNED'
                    CHECK (status IN ('PLANNED','IN_PROGRESS','COMPLETED','DELAYED','CANCELLED')),
    -- Giorni di ritardo (negativo = anticipo). Calcolato applicativamente.
    delay_days      INTEGER GENERATED ALWAYS AS (
                        CASE WHEN actual_date IS NOT NULL AND planned_date IS NOT NULL
                             THEN actual_date - planned_date
                             ELSE NULL END
                    ) STORED,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE process.milestone IS 'Milestone contrattuali con date pianificate/effettive. Alimentato da MS-04 Gantt Parser.';

-- ─── gantt_activity ───────────────────────────────────────────────────────────
-- Attività Gantt importate da MS Project (.MPP) o Excel.
-- Struttura gerarchica: ogni attività può avere un parent (WBS Gantt).
CREATE TABLE IF NOT EXISTS process.gantt_activity (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID         NOT NULL REFERENCES tenant.tenant(id),
    -- Il contratto a cui appartiene questo Gantt (nullable: Gantt può essere standalone)
    contract_id     UUID         REFERENCES process.contract(id),
    -- Nodo padre nella gerarchia Gantt (NULL = attività radice)
    parent_id       UUID         REFERENCES process.gantt_activity(id),
    -- Codice WBS del Gantt (es. "1.2.3" = terzo figlio del secondo figlio della radice)
    wbs_code        VARCHAR(50)  NOT NULL,
    name            VARCHAR(255) NOT NULL,
    -- Date pianificate (da MS Project/Excel)
    planned_start   DATE,
    planned_finish  DATE,
    -- Date effettive (aggiornate durante l'esecuzione)
    actual_start    DATE,
    actual_finish   DATE,
    -- Durata in giorni lavorativi
    duration_days   INTEGER,
    -- Avanzamento percentuale (0.00 – 100.00)
    percent_complete NUMERIC(5,2) NOT NULL DEFAULT 0
                     CHECK (percent_complete >= 0 AND percent_complete <= 100),
    -- Risorse assegnate (da MS Project, stringa libera)
    resource_names  TEXT,
    -- Predecessori (codici WBS separati da virgola, es. "1.2.1,1.2.2")
    predecessors    TEXT,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE process.gantt_activity IS 'Attività Gantt con struttura gerarchica WBS. Importato da MS Project via MS-04 Gantt Parser.';

-- ─── Indici ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_proc_contract_tenant   ON process.contract(tenant_id);
CREATE INDEX IF NOT EXISTS idx_proc_contract_status   ON process.contract(status);
CREATE INDEX IF NOT EXISTS idx_proc_clause_contract   ON process.clause(contract_id);
CREATE INDEX IF NOT EXISTS idx_proc_clause_tenant     ON process.clause(tenant_id);
CREATE INDEX IF NOT EXISTS idx_proc_paycond_contract  ON process.payment_condition(contract_id);
CREATE INDEX IF NOT EXISTS idx_proc_milestone_contract ON process.milestone(contract_id);
CREATE INDEX IF NOT EXISTS idx_proc_milestone_tenant  ON process.milestone(tenant_id);
CREATE INDEX IF NOT EXISTS idx_proc_gantt_contract    ON process.gantt_activity(contract_id);
CREATE INDEX IF NOT EXISTS idx_proc_gantt_parent      ON process.gantt_activity(parent_id);
CREATE INDEX IF NOT EXISTS idx_proc_gantt_wbs         ON process.gantt_activity(tenant_id, wbs_code);

-- ─── Trigger updated_at su contract ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION process.update_contract_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_contract_updated_at ON process.contract;
CREATE TRIGGER trg_contract_updated_at
    BEFORE UPDATE ON process.contract
    FOR EACH ROW EXECUTE FUNCTION process.update_contract_updated_at();

COMMIT;
