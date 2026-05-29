-- =============================================================================
-- 10_schema_read.sql
-- Schema: read (CQRS Read Side)
--
-- Pattern CQRS (Command Query Responsibility Segregation):
-- Write Side = gli 11 microservizi scrivono ognuno nel proprio schema
-- Read Side = MS-09 Read Projector aggrega i dati e li scrive qui
--
-- Il frontend React e Hasura leggono SOLO da questo schema.
-- Questo permette di ottimizzare i dati per la lettura (denormalizzati,
-- pre-calcolati) senza toccare i dati di scrittura.
--
-- Queste "proiezioni" vengono rigenerate da eventi Pub/Sub ogni volta
-- che cambiano i dati nelle tabelle write-side.
-- =============================================================================

-- ─── project_sal_summary ─────────────────────────────────────────────────────
-- Vista aggregata del SAL per progetto: percentuale completamento, valore economico
CREATE TABLE IF NOT EXISTS read.project_sal_summary (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID          NOT NULL REFERENCES tenant.company(id),
    -- Aggiornato ogni volta che un SAL viene certificato o aggiornato
    last_updated_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    -- Contatori elementi BIM
    total_elements      INTEGER       NOT NULL DEFAULT 0,
    elements_in_progress INTEGER      NOT NULL DEFAULT 0,
    elements_completed  INTEGER       NOT NULL DEFAULT 0,
    -- Percentuale avanzamento fisica (0.00 - 100.00)
    completion_pct      NUMERIC(5,2)  NOT NULL DEFAULT 0.00,
    -- Valorizzazione economica
    contracted_value    NUMERIC(15,2) NOT NULL DEFAULT 0.00,
    certified_value     NUMERIC(15,2) NOT NULL DEFAULT 0.00,
    -- Data ultimo SAL certificato
    last_sal_date       DATE,
    -- Hash del SAL per verifica integrità
    last_sal_hash       VARCHAR(64),
    UNIQUE (tenant_id)
);

COMMENT ON TABLE read.project_sal_summary IS 'CQRS: riepilogo SAL per progetto. Aggiornato da MS-09 ad ogni evento SAL. Ottimizzato per dashboard frontend.';

-- ─── element_completion_view ─────────────────────────────────────────────────
-- Stato di completamento per ogni elemento BIM (granularità massima)
CREATE TABLE IF NOT EXISTS read.element_completion_view (
    id                UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         UUID          NOT NULL REFERENCES tenant.company(id),
    element_id        UUID          NOT NULL REFERENCES bim.bim_element(id),
    -- Quantità totale dal BIM
    total_quantity    NUMERIC(15,4) NOT NULL DEFAULT 0,
    unit_of_measure   VARCHAR(20),
    -- Quantità completata e certificata
    certified_qty     NUMERIC(15,4) NOT NULL DEFAULT 0,
    -- Percentuale completamento (0.00 - 100.00)
    completion_pct    NUMERIC(5,2)  NOT NULL DEFAULT 0,
    -- Valore economico certificato per questo elemento
    certified_value   NUMERIC(15,2) NOT NULL DEFAULT 0,
    last_updated_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, element_id)
);

COMMENT ON TABLE read.element_completion_view IS 'CQRS: stato completamento per elemento BIM. Alimentato da MS-09 per la Digital Twin View del frontend.';

-- ─── Indici ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_read_sal_tenant    ON read.project_sal_summary(tenant_id);
CREATE INDEX IF NOT EXISTS idx_read_elem_tenant   ON read.element_completion_view(tenant_id);
CREATE INDEX IF NOT EXISTS idx_read_elem_id       ON read.element_completion_view(element_id);
CREATE INDEX IF NOT EXISTS idx_read_elem_pct      ON read.element_completion_view(completion_pct);
