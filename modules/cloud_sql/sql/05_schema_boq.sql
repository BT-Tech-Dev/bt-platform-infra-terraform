-- =============================================================================
-- 05_schema_boq.sql
-- Schema: boq (Bill of Quantities = Computo Metrico)
--
-- Contiene il computo metrico: l'elenco delle voci con quantità e prezzi
-- unitari che definiscono il valore economico del contratto.
-- Viene importato da Excel (file .xlsx del computo metrico).
--
-- Il collegamento boq_item → work_activity (tramite boq_activity) permette
-- al SAL Engine di calcolare: quantità eseguita × prezzo unitario = valore SAL.
-- =============================================================================

-- ─── boq ─────────────────────────────────────────────────────────────────────
-- Un computo metrico = un documento contractuale
CREATE TABLE IF NOT EXISTS boq.boq (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID         NOT NULL REFERENCES tenant.company(id),
    -- Codice identificativo (es. "CME-0549")
    code        VARCHAR(50)  NOT NULL,
    description TEXT,
    -- Versione del documento (il computo può essere revisionato durante i lavori)
    version     VARCHAR(20)  NOT NULL DEFAULT 'v1.0',
    -- Data di emissione del computo
    issued_date DATE,
    -- Valore totale del contratto (somma di tutti i boq_item)
    total_value NUMERIC(15,2),
    -- Valuta (sempre EUR per clienti italiani)
    currency    VARCHAR(3)   NOT NULL DEFAULT 'EUR',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, code, version)
);

COMMENT ON TABLE boq.boq IS 'Computo metrico: documento contrattuale con l''elenco delle lavorazioni e prezzi';

-- ─── boq_item ─────────────────────────────────────────────────────────────────
-- Singola voce del computo (es. "Calcestruzzo C25/30: 145,00 €/m³")
CREATE TABLE IF NOT EXISTS boq.boq_item (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID          NOT NULL REFERENCES tenant.company(id),
    boq_id          UUID          NOT NULL REFERENCES boq.boq(id) ON DELETE CASCADE,
    -- Codice voce (es. "CLS-C25", "ARM-FE510")
    code            VARCHAR(50)   NOT NULL,
    description     TEXT          NOT NULL,
    -- Unità di misura (es. "m³", "kg", "m²", "cad")
    unit_of_measure VARCHAR(20)   NOT NULL,
    -- Prezzo per unità di misura (es. 145.00 €/m³)
    unit_price      NUMERIC(12,4) NOT NULL,
    -- Quantità contrattuale totale (dalla perizia contrattuale)
    contracted_qty  NUMERIC(15,4),
    -- Valore totale voce = contracted_qty × unit_price
    total_value     NUMERIC(15,2)
                    GENERATED ALWAYS AS (contracted_qty * unit_price) STORED,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    UNIQUE (boq_id, code)
);

COMMENT ON TABLE boq.boq_item IS 'Voci del computo metrico: descrizione, UM, prezzo unitario, quantità contrattuale';

-- ─── boq_activity ─────────────────────────────────────────────────────────────
-- Collega una voce del computo a una lavorazione del processo costruttivo.
-- Coefficient: moltiplicatore per convertire quantità BIM in valore economico
--   Es: 1 m³ gettato → coefficient 1.0 → 1 m³ valorizzato al prezzo voce
CREATE TABLE IF NOT EXISTS boq.boq_activity (
    id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID          NOT NULL REFERENCES tenant.company(id),
    boq_item_id UUID          NOT NULL REFERENCES boq.boq_item(id) ON DELETE CASCADE,
    activity_id UUID          NOT NULL REFERENCES bim.work_activity(id),
    coefficient NUMERIC(8,4)  NOT NULL DEFAULT 1.0,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    UNIQUE (boq_item_id, activity_id)
);

COMMENT ON TABLE boq.boq_activity IS 'Link voce computo ↔ lavorazione. Coefficient = fattore di conversione per la valorizzazione.';

-- ─── Indici ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_boq_tenant           ON boq.boq(tenant_id);
CREATE INDEX IF NOT EXISTS idx_boq_item_tenant      ON boq.boq_item(tenant_id);
CREATE INDEX IF NOT EXISTS idx_boq_item_boq         ON boq.boq_item(boq_id);
CREATE INDEX IF NOT EXISTS idx_boq_activity_tenant  ON boq.boq_activity(tenant_id);
CREATE INDEX IF NOT EXISTS idx_boq_activity_item    ON boq.boq_activity(boq_item_id);
CREATE INDEX IF NOT EXISTS idx_boq_activity_act     ON boq.boq_activity(activity_id);
