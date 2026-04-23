-- =============================================================================
-- migrate_05_progress_add_sal.sql
-- Schema: progress — aggiunge tabelle SAL, rimuove activity_item_usage
--
-- COSA FA:
--   Rimuove: activity_item_usage (tabella rimossa dall'architettura)
--   Aggiunge: sal, sal_line_item, sal_check_result
--
-- PERCHÉ "sal" non era già qui:
--   Nella versione precedente lo "stato SAL" era distribuito in work_progress
--   tramite il campo sal_status. Con l'architettura v3.0, il SAL è un'entità
--   di primo livello (MS-06 SAL Engine) con 6 check sequenziali e hash di integrità.
--   La tabella "sal" è il documento SAL immutabile dopo la certificazione.
--
-- PERCHÉ rimuovere activity_item_usage:
--   Questa tabella tracciava l'utilizzo di casseri/materiali in cantiere.
--   L'architettura v3.0 sposta questo tracking nello schema production.
--   Sul nuovo progetto la tabella è vuota.
-- =============================================================================

BEGIN;

-- ─── Rimuovi activity_item_usage ─────────────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'progress' AND table_name = 'activity_item_usage'
    ) THEN
        DROP TABLE progress.activity_item_usage CASCADE;
        RAISE NOTICE 'Rimossa: progress.activity_item_usage';
    ELSE
        RAISE NOTICE 'SKIP: progress.activity_item_usage non trovata';
    END IF;
END $$;

-- ─── sal ─────────────────────────────────────────────────────────────────────
-- Il documento SAL (Stato di Avanzamento Lavori).
-- Dopo la certificazione diventa IMMUTABILE: integrity_hash lo protegge.
-- Ogni SAL copre un periodo (periodo_start → periodo_end) e aggrega
-- tutti i work_progress di quel periodo.
CREATE TABLE IF NOT EXISTS progress.sal (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID          NOT NULL REFERENCES tenant.tenant(id),
    -- Numero progressivo del SAL (es. "SAL-2026-001")
    sal_number      VARCHAR(50)   NOT NULL,
    -- Data di riferimento del SAL (di solito la fine del periodo)
    reference_date  DATE          NOT NULL,
    -- Periodo coperto dal SAL
    period_start    DATE,
    period_end      DATE,
    -- draft=bozza editabile, submitted=inviato per approvazione,
    -- certified=certificato e IMMUTABILE, rejected=rifiutato (torna a draft)
    status          VARCHAR(15)   NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft','submitted','certified','rejected')),
    -- Valore economico totale calcolato dal SAL Engine
    total_amount    NUMERIC(18,2),
    currency        VARCHAR(3)    NOT NULL DEFAULT 'EUR',
    -- SHA-256 calcolato dal SAL Engine al momento della certificazione.
    -- Comprende: tenant_id, sal_number, reference_date, total_amount, tutte le line_items.
    -- Se qualcuno modifica i dati dopo la certificazione, l'hash non corrisponde più.
    integrity_hash  VARCHAR(64),
    -- Chi ha certificato e quando
    certified_at    TIMESTAMPTZ,
    certified_by    VARCHAR(255),
    notes           TEXT,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, sal_number)
);
COMMENT ON TABLE progress.sal IS 'Documento SAL (Stato Avanzamento Lavori). Immutabile dopo certificazione (protetto da integrity_hash SHA-256).';
COMMENT ON COLUMN progress.sal.integrity_hash IS 'SHA-256 del SAL al momento della certificazione. Modifica dati → hash invalido → SAL corrotto.';

-- ─── sal_line_item ────────────────────────────────────────────────────────────
-- Righe del SAL: una per ogni lavorazione inclusa nel SAL.
-- Snapshot dei dati al momento del SAL (valori denormalizzati per immutabilità).
-- Non è un JOIN a work_activity perché quei dati possono cambiare nel tempo.
CREATE TABLE IF NOT EXISTS progress.sal_line_item (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID          NOT NULL REFERENCES tenant.tenant(id),
    sal_id          UUID          NOT NULL REFERENCES progress.sal(id) ON DELETE CASCADE,
    -- FK al work_progress di riferimento (nullable: può essere creato a mano)
    work_progress_id UUID         REFERENCES progress.work_progress(id),
    -- Snapshot della lavorazione (denormalizzato per immutabilità del SAL)
    activity_code   VARCHAR(50),    -- copia di bim.work_activity.code al momento del SAL
    activity_name   VARCHAR(255),   -- copia del nome
    -- Quantità avanzata in questo SAL
    quantity_done   NUMERIC(15,4),
    unit_of_measure VARCHAR(20),
    -- Prezzo unitario (da BOQ al momento del SAL)
    unit_price      NUMERIC(15,4),
    -- Valore economico = quantity_done × unit_price
    line_amount     NUMERIC(15,2),
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE progress.sal_line_item IS 'Righe del SAL: una per lavorazione. Dati denormalizzati (snapshot) per garantire immutabilità dopo certificazione.';

-- ─── sal_check_result ────────────────────────────────────────────────────────
-- Risultati dei 6 check sequenziali del SAL Engine (MS-06).
-- Ogni check produce PASS/FAIL con score e dettaglio.
-- Il SAL può essere certificato solo se tutti i check obbligatori passano.
--
-- I 6 check:
--   1 = Parificazione automatica (aggregazione quantità per WBS)
--   2 = Incrocio quantità (BIM ↔ Production ↔ BOQ, soglia ≥98%)
--   3 = Valorizzazione economica (TPS, TCS, RA_k, verifica soglia contrattuale)
--   4 = Verifica documentale (certificati qualità + DDT, copertura ≥98%)
--   5 = NC Check (NC Major con blocks_sal=true → blocca il SAL)
--   6 = Rilascio (snapshot immutabile + hash integrità)
CREATE TABLE IF NOT EXISTS progress.sal_check_result (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID          NOT NULL REFERENCES tenant.tenant(id),
    sal_id          UUID          NOT NULL REFERENCES progress.sal(id) ON DELETE CASCADE,
    -- Numero check (1–6, in ordine sequenziale)
    check_number    INTEGER       NOT NULL CHECK (check_number BETWEEN 1 AND 6),
    -- Nome descrittivo del check (es. "Parificazione automatica")
    check_name      VARCHAR(100)  NOT NULL,
    -- PASS=superato, FAIL=non superato (blocca SAL), WARNING=superato con avvisi,
    -- SKIPPED=saltato (non applicabile per questa tipologia di SAL)
    status          VARCHAR(10)   NOT NULL
                    CHECK (status IN ('PASS','FAIL','WARNING','SKIPPED')),
    -- Score del check (es. 98.7 = 98.7% di conformità). NULL se non applicabile.
    score           NUMERIC(6,3),
    -- Soglia minima per il PASS (es. 98.0). NULL se il check è binario.
    threshold       NUMERIC(6,3),
    -- Dettaglio JSON del check (elementi che hanno passato/fallito, valori calcolati)
    details         JSONB         NOT NULL DEFAULT '{}',
    -- Messaggio di errore se status = 'FAIL' (testo leggibile dall'ingegnere)
    error_message   TEXT,
    -- Timestamp dell'esecuzione del check
    executed_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    -- Un SAL ha esattamente un risultato per check_number
    UNIQUE (sal_id, check_number)
);
COMMENT ON TABLE progress.sal_check_result IS 'Risultati dei 6 check del SAL Engine (MS-06). FAIL su qualsiasi check obbligatorio blocca la certificazione.';

-- ─── Indici ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_sal_tenant         ON progress.sal(tenant_id);
CREATE INDEX IF NOT EXISTS idx_sal_status         ON progress.sal(status);
CREATE INDEX IF NOT EXISTS idx_sal_ref_date       ON progress.sal(reference_date);
CREATE INDEX IF NOT EXISTS idx_sal_item_sal       ON progress.sal_line_item(sal_id);
CREATE INDEX IF NOT EXISTS idx_sal_item_tenant    ON progress.sal_line_item(tenant_id);
CREATE INDEX IF NOT EXISTS idx_sal_check_sal      ON progress.sal_check_result(sal_id);
CREATE INDEX IF NOT EXISTS idx_sal_check_status   ON progress.sal_check_result(status);

COMMIT;
