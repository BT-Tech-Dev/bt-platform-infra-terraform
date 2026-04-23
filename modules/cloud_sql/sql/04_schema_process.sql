-- =============================================================================
-- 04_schema_process.sql
-- Schema: process
--
-- Contiene i dati contrattuali: il contratto d'appalto, le sue clausole,
-- le condizioni di pagamento SAL, le milestone e il Gantt di progetto.
--
-- Flusso: PDF contratto → MS-02 Contract Parser → process.contract/clause/payment_condition
--         MPP/Excel Gantt → MS-04 Gantt Parser → process.gantt_activity
--
-- Nota: le tabelle WBS (construction_phase, work_activity, ecc.) sono in schema bim.
-- =============================================================================

-- ─── contract ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS process.contract (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID         NOT NULL REFERENCES tenant.company(id),
    contract_number VARCHAR(100) NOT NULL,
    description     TEXT,
    contractor_name VARCHAR(255),
    contract_value  NUMERIC(18,2),
    currency        VARCHAR(3)   NOT NULL DEFAULT 'EUR',
    signed_date     DATE,
    start_date      DATE,
    end_date        DATE,
    status          VARCHAR(20)  NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft','active','completed','terminated','suspended')),
    metadata        JSONB        NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, contract_number)
);
COMMENT ON TABLE process.contract IS 'Contratti d''appalto. Alimentato da MS-02 Contract Parser (PDF/DOCX).';

-- ─── clause ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS process.clause (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID         NOT NULL REFERENCES tenant.company(id),
    contract_id     UUID         NOT NULL REFERENCES process.contract(id) ON DELETE CASCADE,
    clause_number   VARCHAR(50),
    title           VARCHAR(255),
    body            TEXT,
    clause_type     VARCHAR(30)  NOT NULL DEFAULT 'GENERAL'
                    CHECK (clause_type IN ('GENERAL','PAYMENT','PENALTY','VARIATION',
                                           'GUARANTEE','TERMINATION','COMPLIANCE','OTHER')),
    impacts_sal     BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE process.clause IS 'Clausole contrattuali estratte via LLM da MS-02 Contract Parser.';

-- ─── payment_condition ────────────────────────────────────────────────────────
-- Condizioni di pagamento: definiscono le tranche del contratto.
-- Input per il SAL Engine per il calcolo della valorizzazione economica.
CREATE TABLE IF NOT EXISTS process.payment_condition (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID         NOT NULL REFERENCES tenant.company(id),
    contract_id     UUID         NOT NULL REFERENCES process.contract(id) ON DELETE CASCADE,
    condition_code  VARCHAR(50),
    description     TEXT,
    -- Percentuale del contratto da pagare (es. 30.00 = 30%)
    percentage      NUMERIC(6,3) CHECK (percentage > 0 AND percentage <= 100),
    trigger_type    VARCHAR(30)  NOT NULL DEFAULT 'SAL_MILESTONE'
                    CHECK (trigger_type IN ('SAL_MILESTONE','DATE','DELIVERY','COMPLETION','ADVANCE')),
    days_to_pay     INTEGER      NOT NULL DEFAULT 30 CHECK (days_to_pay > 0),
    requires_nc_clearance BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE process.payment_condition IS 'Condizioni di pagamento SAL: percentuali, trigger, giorni. Input per SAL Engine (check 3).';

-- ─── milestone ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS process.milestone (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID         NOT NULL REFERENCES tenant.company(id),
    contract_id     UUID         NOT NULL REFERENCES process.contract(id) ON DELETE CASCADE,
    code            VARCHAR(50),
    name            VARCHAR(255) NOT NULL,
    description     TEXT,
    planned_date    DATE,
    actual_date     DATE,
    status          VARCHAR(20)  NOT NULL DEFAULT 'PLANNED'
                    CHECK (status IN ('PLANNED','IN_PROGRESS','COMPLETED','DELAYED','CANCELLED')),
    -- Giorni di ritardo calcolati automaticamente dal DB: positivo=ritardo, negativo=anticipo
    delay_days      INTEGER GENERATED ALWAYS AS (
                        CASE WHEN actual_date IS NOT NULL AND planned_date IS NOT NULL
                             THEN actual_date - planned_date
                             ELSE NULL END
                    ) STORED,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE process.milestone IS 'Milestone contrattuali con date pianificate/effettive. Alimentato da MS-04 Gantt Parser.';

-- ─── gantt_activity ───────────────────────────────────────────────────────────
-- Struttura gerarchica WBS del Gantt (importato da MS Project o Excel).
-- parent_id = NULL per le attività radice del Gantt.
CREATE TABLE IF NOT EXISTS process.gantt_activity (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID         NOT NULL REFERENCES tenant.company(id),
    contract_id     UUID         REFERENCES process.contract(id),
    parent_id       UUID         REFERENCES process.gantt_activity(id),
    wbs_code        VARCHAR(50)  NOT NULL,
    name            VARCHAR(255) NOT NULL,
    planned_start   DATE,
    planned_finish  DATE,
    actual_start    DATE,
    actual_finish   DATE,
    duration_days   INTEGER,
    percent_complete NUMERIC(5,2) NOT NULL DEFAULT 0
                     CHECK (percent_complete >= 0 AND percent_complete <= 100),
    resource_names  TEXT,
    predecessors    TEXT,  -- Codici WBS predecessori, separati da virgola
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE process.gantt_activity IS 'WBS Gantt gerarchica importata da MS Project (MS-04). parent_id=NULL per la radice.';

-- ─── Indici ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_proc_contract_tenant    ON process.contract(tenant_id);
CREATE INDEX IF NOT EXISTS idx_proc_contract_status    ON process.contract(status);
CREATE INDEX IF NOT EXISTS idx_proc_clause_contract    ON process.clause(contract_id);
CREATE INDEX IF NOT EXISTS idx_proc_clause_tenant      ON process.clause(tenant_id);
CREATE INDEX IF NOT EXISTS idx_proc_paycond_contract   ON process.payment_condition(contract_id);
CREATE INDEX IF NOT EXISTS idx_proc_milestone_contract ON process.milestone(contract_id);
CREATE INDEX IF NOT EXISTS idx_proc_milestone_tenant   ON process.milestone(tenant_id);
CREATE INDEX IF NOT EXISTS idx_proc_gantt_contract     ON process.gantt_activity(contract_id);
CREATE INDEX IF NOT EXISTS idx_proc_gantt_parent       ON process.gantt_activity(parent_id);
CREATE INDEX IF NOT EXISTS idx_proc_gantt_wbs          ON process.gantt_activity(tenant_id, wbs_code);

-- ─── Trigger updated_at ──────────────────────────────────────────────────────
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
