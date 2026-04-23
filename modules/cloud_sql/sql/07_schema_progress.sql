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

-- ─── FK cross-schema: production.production_record → progress.element_progress ──
-- Non poteva essere dichiarato in 06_schema_production.sql perché element_progress
-- non esisteva ancora. Lo aggiungiamo ora che entrambe le tabelle esistono.
DO $$
BEGIN
    ALTER TABLE production.production_record
        ADD CONSTRAINT fk_prod_record_element_progress
        FOREIGN KEY (element_progress_id)
        REFERENCES progress.element_progress(id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
