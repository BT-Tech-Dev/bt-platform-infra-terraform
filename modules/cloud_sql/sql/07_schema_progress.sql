-- =============================================================================
-- 07_schema_progress.sql
-- Schema: progress
--
-- Il cuore operativo della piattaforma: registra e certifica l'avanzamento lavori.
--
-- Flusso SAL (6 check sequenziali del SAL Engine MS-06):
--   1. work_progress: avanzamento per lavorazione (chi, quanto, quando)
--   2. element_progress: avanzamento per singolo elemento BIM
--   3. sal: documento SAL aggregato (immutabile dopo certificazione)
--   4. sal_line_item: righe del SAL con valorizzazione economica
--   5. sal_check_result: risultati dei 6 check di verifica
-- =============================================================================

-- ─── work_progress ───────────────────────────────────────────────────────────
-- Avanzamento lavori per una specifica lavorazione.
-- Un SAL periodico (mensile) genera uno o più record work_progress.
CREATE TABLE IF NOT EXISTS progress.work_progress (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID          NOT NULL REFERENCES tenant.company(id),
    -- FK alla lavorazione in bim.work_activity (schema bim dopo migrazione v3.0)
    activity_id     UUID          NOT NULL REFERENCES bim.work_activity(id),
    -- Data di riferimento del SAL (data del report, non dell'esecuzione fisica)
    reference_date  DATE          NOT NULL,
    -- Percentage = 0-100%, Quantity = valore assoluto in unità di misura
    progress_type   VARCHAR(20)   NOT NULL DEFAULT 'Quantity'
                    CHECK (progress_type IN ('Percentage', 'Quantity')),
    progress_value  NUMERIC(15,4) NOT NULL,
    unit_of_measure VARCHAR(20),
    notes           TEXT,
    -- Draft → Submitted → Certified (immutabile) o Rejected (torna a Draft)
    sal_status      VARCHAR(20)   NOT NULL DEFAULT 'Draft'
                    CHECK (sal_status IN ('Draft', 'Submitted', 'Certified', 'Rejected')),
    -- SHA-256 del record al momento della certificazione.
    -- Se il record viene modificato dopo la certificazione, l'hash non corrisponde.
    integrity_hash  VARCHAR(64),
    certified_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE progress.work_progress IS 'Avanzamento lavori per lavorazione. Alimenta il SAL Engine per il calcolo del valore economico.';
COMMENT ON COLUMN progress.work_progress.integrity_hash IS 'SHA-256 al momento della certificazione. Qualsiasi modifica post-certificazione invalida l''hash.';

-- ─── element_progress ────────────────────────────────────────────────────────
-- Dettaglio per singolo elemento BIM: quanta quantità è stata completata.
-- Granularità massima del SAL: singolo plinto, singola trave, singola colonna.
CREATE TABLE IF NOT EXISTS progress.element_progress (
    id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         UUID          NOT NULL REFERENCES tenant.company(id),
    work_progress_id  UUID          NOT NULL REFERENCES progress.work_progress(id) ON DELETE CASCADE,
    element_id        UUID          NOT NULL REFERENCES bim.bim_element(id),
    quantity_done     NUMERIC(15,4) NOT NULL,
    unit_of_measure   VARCHAR(20)   NOT NULL,
    created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE progress.element_progress IS 'Avanzamento per singolo elemento BIM: granularità massima del SAL.';

-- ─── sal ─────────────────────────────────────────────────────────────────────
-- Documento SAL (Stato di Avanzamento Lavori).
-- IMMUTABILE dopo certificazione: integrity_hash garantisce l'integrità.
CREATE TABLE IF NOT EXISTS progress.sal (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID          NOT NULL REFERENCES tenant.company(id),
    -- Numero progressivo SAL (es. "SAL-2026-001")
    sal_number      VARCHAR(50)   NOT NULL,
    reference_date  DATE          NOT NULL,
    period_start    DATE,
    period_end      DATE,
    status          VARCHAR(15)   NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft','submitted','certified','rejected')),
    -- Valore economico totale (calcolato da SAL Engine, check 3)
    total_amount    NUMERIC(18,2),
    currency        VARCHAR(3)    NOT NULL DEFAULT 'EUR',
    -- SHA-256 del SAL calcolato al momento della certificazione.
    -- Copre: tenant_id, sal_number, reference_date, total_amount, tutte le line_items.
    integrity_hash  VARCHAR(64),
    certified_at    TIMESTAMPTZ,
    certified_by    VARCHAR(255),
    notes           TEXT,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, sal_number)
);
COMMENT ON TABLE progress.sal IS 'Documento SAL. Immutabile dopo certificazione (integrity_hash SHA-256).';

-- ─── sal_line_item ────────────────────────────────────────────────────────────
-- Righe del SAL: una per lavorazione inclusa.
-- Dati denormalizzati (snapshot) per garantire che il SAL non cambi
-- anche se work_activity viene modificata successivamente.
CREATE TABLE IF NOT EXISTS progress.sal_line_item (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID          NOT NULL REFERENCES tenant.company(id),
    sal_id          UUID          NOT NULL REFERENCES progress.sal(id) ON DELETE CASCADE,
    work_progress_id UUID         REFERENCES progress.work_progress(id),
    -- Snapshot della lavorazione al momento del SAL (denormalizzato)
    activity_code   VARCHAR(50),    -- copia di bim.work_activity.code
    activity_name   VARCHAR(255),   -- copia del nome
    quantity_done   NUMERIC(15,4),
    unit_of_measure VARCHAR(20),
    unit_price      NUMERIC(15,4),  -- da BOQ al momento del SAL
    line_amount     NUMERIC(15,2),  -- quantity_done × unit_price, calcolato dal SAL Engine
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE progress.sal_line_item IS 'Righe SAL con snapshot denormalizzato. Garantisce immutabilità del SAL indipendentemente da modifiche future alle lavorazioni.';

-- ─── sal_check_result ────────────────────────────────────────────────────────
-- Risultati dei 6 check sequenziali del SAL Engine (MS-06).
-- FAIL su qualsiasi check obbligatorio blocca la certificazione.
CREATE TABLE IF NOT EXISTS progress.sal_check_result (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID          NOT NULL REFERENCES tenant.company(id),
    sal_id          UUID          NOT NULL REFERENCES progress.sal(id) ON DELETE CASCADE,
    -- Check 1=Parificazione, 2=Incrocio quantità, 3=Valorizzazione economica,
    -- 4=Verifica documentale, 5=NC Check (blocco Major NC), 6=Rilascio+hash
    check_number    INTEGER       NOT NULL CHECK (check_number BETWEEN 1 AND 6),
    check_name      VARCHAR(100)  NOT NULL,
    status          VARCHAR(10)   NOT NULL
                    CHECK (status IN ('PASS','FAIL','WARNING','SKIPPED')),
    score           NUMERIC(6,3),     -- Es: 98.7 = 98.7% di conformità
    threshold       NUMERIC(6,3),     -- Es: 98.0 = soglia minima richiesta
    details         JSONB         NOT NULL DEFAULT '{}',
    error_message   TEXT,
    executed_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    UNIQUE (sal_id, check_number)
);
COMMENT ON TABLE progress.sal_check_result IS '6 check del SAL Engine. FAIL blocca certificazione. SKIPPED = non applicabile per questa tipologia SAL.';

-- ─── Indici ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_prog_wp_tenant     ON progress.work_progress(tenant_id);
CREATE INDEX IF NOT EXISTS idx_prog_wp_activity   ON progress.work_progress(activity_id);
CREATE INDEX IF NOT EXISTS idx_prog_wp_date       ON progress.work_progress(reference_date);
CREATE INDEX IF NOT EXISTS idx_prog_wp_status     ON progress.work_progress(sal_status);
CREATE INDEX IF NOT EXISTS idx_prog_ep_tenant     ON progress.element_progress(tenant_id);
CREATE INDEX IF NOT EXISTS idx_prog_ep_wp         ON progress.element_progress(work_progress_id);
CREATE INDEX IF NOT EXISTS idx_prog_ep_element    ON progress.element_progress(element_id);
CREATE INDEX IF NOT EXISTS idx_sal_tenant         ON progress.sal(tenant_id);
CREATE INDEX IF NOT EXISTS idx_sal_status         ON progress.sal(status);
CREATE INDEX IF NOT EXISTS idx_sal_ref_date       ON progress.sal(reference_date);
CREATE INDEX IF NOT EXISTS idx_sal_item_sal       ON progress.sal_line_item(sal_id);
CREATE INDEX IF NOT EXISTS idx_sal_item_tenant    ON progress.sal_line_item(tenant_id);
CREATE INDEX IF NOT EXISTS idx_sal_check_sal      ON progress.sal_check_result(sal_id);
CREATE INDEX IF NOT EXISTS idx_sal_check_status   ON progress.sal_check_result(status);

-- =============================================================================
-- Layer 4 reconciliation and progress derivation drafts
--
-- MS-05 writes Layer 3 only. The reconciliation service writes Layer 4.
-- =============================================================================

CREATE TABLE IF NOT EXISTS progress.evidence_link (
    evidence_link_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenant.company(id),
    project_code VARCHAR(50) NOT NULL,
    project_element_id UUID,
    evidence_kind VARCHAR(30) NOT NULL,
    evidence_id UUID NOT NULL,
    evidence_type VARCHAR(100) NOT NULL,
    matched_identifier_id UUID,
    match_method VARCHAR(50),
    match_value VARCHAR(200),
    confidence NUMERIC(4,3),
    link_status VARCHAR(30) NOT NULL DEFAULT 'unmatched',
    is_effective BOOLEAN NOT NULL DEFAULT FALSE,
    reason TEXT,
    matched_by VARCHAR(200),
    matched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_by VARCHAR(200),
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    FOREIGN KEY (project_element_id, tenant_id, project_code)
        REFERENCES bim.project_element_registry(project_element_id, tenant_id, project_code),
    FOREIGN KEY (matched_identifier_id, tenant_id, project_code)
        REFERENCES bim.project_element_identifier(identifier_id, tenant_id, project_code),
    CHECK (evidence_kind IN ('production_record', 'quality_test_result', 'document_ref')),
    CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
    CHECK (link_status IN ('confirmed', 'needs_review', 'unmatched', 'rejected', 'superseded')),
    CHECK (link_status <> 'confirmed' OR project_element_id IS NOT NULL),
    CHECK (
        link_status <> 'unmatched'
        OR (project_element_id IS NULL AND matched_identifier_id IS NULL)
    ),
    CHECK (
        NOT is_effective
        OR (link_status = 'confirmed' AND project_element_id IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS progress.progress_derivation_rule (
    progress_derivation_rule_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenant.company(id),
    project_code VARCHAR(50),
    element_type_id UUID REFERENCES catalog.element_type(element_type_id),
    activity_code VARCHAR(100) NOT NULL,
    rule_name VARCHAR(200) NOT NULL,
    evidence_kind VARCHAR(30) NOT NULL,
    evidence_type VARCHAR(100) NOT NULL,
    derivation_method VARCHAR(50) NOT NULL,
    progress_weight NUMERIC(8,5),
    rule_expression JSONB NOT NULL DEFAULT '{}'::jsonb,
    rule_version INTEGER NOT NULL DEFAULT 1,
    effective_from DATE,
    effective_to DATE,
    approval_status VARCHAR(30) NOT NULL DEFAULT 'draft',
    approved_by VARCHAR(200),
    approved_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    FOREIGN KEY (tenant_id, project_code)
        REFERENCES tenant.project(tenant_id, project_code),
    CHECK (
        (tenant_id IS NULL AND project_code IS NULL)
        OR (tenant_id IS NOT NULL AND project_code IS NOT NULL)
    ),
    CHECK (evidence_kind IN ('production_record', 'quality_test_result', 'document_ref')),
    CHECK (progress_weight IS NULL OR progress_weight BETWEEN 0 AND 1),
    CHECK (rule_version > 0),
    CHECK (effective_to IS NULL OR effective_from IS NULL OR effective_to >= effective_from),
    CHECK (approval_status IN ('draft', 'approved', 'retired')),
    CHECK (jsonb_typeof(rule_expression) = 'object')
);

COMMENT ON TABLE progress.evidence_link IS
    'Layer 4 evidence links written by reconciliation. MS-05 writes Layer 3 only; the SAL Engine reads Layer 4/progress.';
COMMENT ON COLUMN progress.evidence_link.evidence_id IS
    'Controlled polymorphic reference selected by evidence_kind. Referential integrity is enforced by reconciliation until reviewed triggers are approved.';
COMMENT ON COLUMN progress.evidence_link.link_status IS
    'confirmed/effective=evidence linked to a project element and eligible for SAL/progress; unmatched/needs_review=one current unresolved review/audit outcome per evidence; rejected/superseded=non-effective history.';
COMMENT ON COLUMN progress.evidence_link.reason IS
    'Reason for unmatched, needs_review, rejected, or superseded reconciliation outcomes.';
COMMENT ON COLUMN progress.evidence_link.is_effective IS
    'Only confirmed links with a project_element_id may be effective. SAL/progress derivation must consume confirmed effective links only.';
COMMENT ON TABLE progress.progress_derivation_rule IS
    'Draft approved-rule model for deriving Layer 4 progress facts consumed by the SAL Engine.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_evidence_link_effective
    ON progress.evidence_link(tenant_id, project_code, evidence_kind, evidence_id)
    WHERE is_effective
      AND link_status = 'confirmed'
      AND project_element_id IS NOT NULL;
-- Reconciliation-service ON CONFLICT must repeat this predicate exactly.
CREATE UNIQUE INDEX IF NOT EXISTS uq_evidence_link_current_unresolved
    ON progress.evidence_link(tenant_id, project_code, evidence_kind, evidence_id)
    WHERE link_status IN ('unmatched', 'needs_review')
      AND is_effective = FALSE;
CREATE INDEX IF NOT EXISTS idx_evidence_link_element_effective
    ON progress.evidence_link(tenant_id, project_code, project_element_id)
    WHERE is_effective
      AND link_status = 'confirmed'
      AND project_element_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_evidence_link_review_queue
    ON progress.evidence_link(tenant_id, project_code, link_status, confidence)
    WHERE link_status = 'needs_review';
CREATE INDEX IF NOT EXISTS idx_evidence_link_unmatched_reprocess
    ON progress.evidence_link(tenant_id, project_code, evidence_kind, evidence_type)
    WHERE link_status = 'unmatched';
CREATE UNIQUE INDEX IF NOT EXISTS uq_progress_derivation_rule_scope_version
    ON progress.progress_derivation_rule(
        COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE(project_code, ''),
        COALESCE(element_type_id, '00000000-0000-0000-0000-000000000000'::uuid),
        activity_code,
        evidence_kind,
        evidence_type,
        rule_version
    );
CREATE INDEX IF NOT EXISTS idx_progress_derivation_rule_lookup
    ON progress.progress_derivation_rule(
        tenant_id, project_code, element_type_id, evidence_kind, evidence_type
    )
    WHERE is_active AND approval_status = 'approved';
