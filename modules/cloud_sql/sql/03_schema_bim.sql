-- =============================================================================
-- 03_schema_bim.sql
-- Schema: bim
--
-- Contiene i dati geometrici esportati da Revit (plugin Orienta Trium)
-- E le tabelle WBS (Work Breakdown Structure) che descrivono la struttura
-- costruttiva degli elementi BIM.
--
-- Flusso: Revit → JSON → GCS staging → bim-parser-v1 → bim_model/element/quantity
-- Flusso WBS: MS-02/MS-03 → process schema → mappatura WBS → bim.work_activity
--
-- Tabelle BIM:
--   bim_model        → file .rvt esportato (una campagna di export)
--   bim_element      → elementi strutturali filtrati (83 per Ponte Po Levante)
--   bim_quantity     → quantità geometriche (volume, area, lunghezza)
--
-- Tabelle WBS (spostated da process in v3.0):
--   construction_phase → macro-fasi costruttive (es. "Strutture", "Finiture")
--   work_activity      → lavorazioni specifiche (es. "Getto CLS platea")
--   element_activity   → link elemento BIM ↔ lavorazione (con peso SAL)
--   measurement_rule   → quale quantità BIM usare per la lavorazione
--   time_profile       → produttività attesa (m³/giorno, ore/unità)
-- =============================================================================

-- ─── bim_model ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bim.bim_model (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- MULTI-TENANCY: ogni riga appartiene a un solo tenant (company). NON NULLABLE.
    tenant_id       UUID         NOT NULL REFERENCES tenant.company(id),
    -- Codice progetto Revit (es. "0549-IDG")
    project_code    VARCHAR(50)  NOT NULL,
    -- Nome file Revit senza estensione (es. "0549-IDG-PPDL-L00-A-INF-3D-A")
    file_name       VARCHAR(255) NOT NULL,
    -- GUID univoco dell'export (generato dal plugin Orienta Trium)
    export_guid     VARCHAR(100),
    -- Strumento di authoring (sempre "Revit" per ora)
    authoring_tool  VARCHAR(100) NOT NULL DEFAULT 'Revit',
    -- Versione IFC dello standard (IFC2x3, IFC4, IFC4.3)
    ifc_version     VARCHAR(20),
    -- Versione del file JSON di export (es. "1.0")
    json_version    VARCHAR(20),
    -- Data/ora dell'export da Revit
    exported_at     TIMESTAMPTZ,
    -- Percorso GCS del file JSON originale (per tracciabilità)
    source_gcs_path TEXT,
    -- Hash SHA-256 del file JSON (per verificare integrità)
    source_file_hash VARCHAR(64),
    -- Numero totale elementi nel file originale (prima del filtro)
    total_elements_raw    INTEGER DEFAULT 0,
    -- Numero elementi importati (dopo il filtro famiglie)
    total_elements_imported INTEGER DEFAULT 0,
    -- Stato importazione
    import_status   VARCHAR(20)  NOT NULL DEFAULT 'pending'
                    CHECK (import_status IN ('pending', 'processing', 'completed', 'failed')),
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    -- Impedisce doppia importazione dello stesso file GCS per lo stesso tenant
    CONSTRAINT uq_bim_model_tenant_path UNIQUE (tenant_id, source_gcs_path)
);
COMMENT ON TABLE bim.bim_model IS 'Modelli BIM importati da Revit via plugin Orienta Trium. Un record per ogni export JSON.';
COMMENT ON COLUMN bim.bim_model.total_elements_raw IS 'Totale elementi nel JSON prima del filtro famiglie (es. 700+)';
COMMENT ON COLUMN bim.bim_model.total_elements_imported IS 'Elementi effettivamente importati dopo filtro (es. 83 per Ponte Po Levante)';

-- ─── bim_element ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bim.bim_element (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID         NOT NULL REFERENCES tenant.company(id),
    -- FK al modello BIM da cui proviene questo elemento
    model_id    UUID         NOT NULL REFERENCES bim.bim_model(id) ON DELETE CASCADE,
    -- GUID IFC univoco dell'elemento (assegnato da Revit, stabile tra export)
    ifc_guid    VARCHAR(100) NOT NULL,
    -- Categoria Revit (es. "Structural Foundations", "Structural Framing")
    category    VARCHAR(100) NOT NULL,
    -- Nome famiglia Revit (es. "IDG_SF_STL_Segment1") — campo radice del JSON, NON parametro
    family      VARCHAR(255) NOT NULL,
    -- Nome tipo/simbolo Revit
    type_name   VARCHAR(255),
    -- Livello architettonico (es. "-1", "0", "Piano Terra")
    level       VARCHAR(100),
    -- Tutti i parametri di istanza e simbolo dal JSON (JSONB per query flessibili)
    -- Es: {"Length": {"Value": 12.5, "UM": "m"}, "Volume": {"Value": 0.45, "UM": "m³"}}
    parameters  JSONB        NOT NULL DEFAULT '{}',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    -- Un elemento IFC è univoco per modello (stesso GUID non può comparire due volte)
    UNIQUE (model_id, ifc_guid)
);
COMMENT ON TABLE bim.bim_element IS 'Elementi BIM filtrati (solo le famiglie strutturali rilevanti per il SAL).';
COMMENT ON COLUMN bim.bim_element.ifc_guid IS 'GUID IFC globalmente univoco (es. 2L$Pj4Y6P8Q9HcZpA). Stabile tra versioni Revit.';
COMMENT ON COLUMN bim.bim_element.parameters IS 'Tutti i parametri Revit come JSONB: {"NomeParametro": {"Value": X, "UM": "unità"}}';

-- ─── bim_quantity ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bim.bim_quantity (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID          NOT NULL REFERENCES tenant.company(id),
    element_id    UUID          NOT NULL REFERENCES bim.bim_element(id) ON DELETE CASCADE,
    -- Tipo di quantità (es. "Volume", "Area", "Length", "CutLength", "Weight")
    quantity_type VARCHAR(100)  NOT NULL,
    value         NUMERIC(15,4) NOT NULL,
    unit_of_measure VARCHAR(20) NOT NULL,  -- Es. "m³", "m²", "m", "kg"
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    -- Un elemento non può avere due righe con lo stesso tipo di quantità
    CONSTRAINT uq_bim_quantity_element_type UNIQUE (element_id, quantity_type)
);
COMMENT ON TABLE bim.bim_quantity IS 'Quantità geometriche degli elementi BIM (volume, area, lunghezza, ecc.). CutLength ha priorità su Length.';

-- ─── construction_phase ──────────────────────────────────────────────────────
-- Raggruppa le lavorazioni in macro-fasi (es. "Strutture", "Finiture", "Impianti").
-- Alimentato manualmente o da MS-02 Contract Parser.
CREATE TABLE IF NOT EXISTS bim.construction_phase (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id      UUID         NOT NULL REFERENCES tenant.company(id),
    -- Codice breve (es. "STR", "FIN", "IMP")
    code           VARCHAR(20)  NOT NULL,
    name           VARCHAR(255) NOT NULL,
    -- Ordine di esecuzione (1=prima fase, 2=seconda fase, ...)
    sequence_order INTEGER      NOT NULL DEFAULT 1,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, code)
);
COMMENT ON TABLE bim.construction_phase IS 'Macro-fasi costruttive (es. Strutture, Finiture, Impianti). Raggruppano le work_activity.';

-- ─── work_activity ────────────────────────────────────────────────────────────
-- Una lavorazione specifica all'interno di una fase costruttiva.
-- Es: fase "Strutture" → lavorazione "Getto calcestruzzo platea"
CREATE TABLE IF NOT EXISTS bim.work_activity (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID         NOT NULL REFERENCES tenant.company(id),
    phase_id    UUID         NOT NULL REFERENCES bim.construction_phase(id),
    -- Codice lavorazione (es. "CLS-GET", "CLS-POM", "ARM-STFF")
    code        VARCHAR(50)  NOT NULL,
    name        VARCHAR(255) NOT NULL,
    description TEXT,
    -- Unità di misura principale per questa lavorazione (es. "m³", "kg", "m²")
    unit_of_measure VARCHAR(20),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, code)
);
COMMENT ON TABLE bim.work_activity IS 'Lavorazioni costruttive (es. Getto CLS, Posa armature). Collegano elementi BIM al SAL.';

-- ─── element_activity ─────────────────────────────────────────────────────────
-- Collega ogni elemento BIM alle lavorazioni necessarie per realizzarlo.
-- WeightFactor: peso relativo della lavorazione sul SAL dell'elemento.
-- Es: fondazione → "armare" (40%) + "gettare" (60%) = WeightFactor 0.4 e 0.6
CREATE TABLE IF NOT EXISTS bim.element_activity (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID          NOT NULL REFERENCES tenant.company(id),
    element_id      UUID          NOT NULL REFERENCES bim.bim_element(id) ON DELETE CASCADE,
    activity_id     UUID          NOT NULL REFERENCES bim.work_activity(id),
    -- Peso percentuale di questa lavorazione sul completamento dell'elemento (0.0-1.0)
    weight_factor   NUMERIC(4,3)  NOT NULL DEFAULT 1.0
                    CHECK (weight_factor > 0 AND weight_factor <= 1),
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    UNIQUE (element_id, activity_id)
);
COMMENT ON TABLE bim.element_activity IS 'Link elemento BIM ↔ lavorazione. WeightFactor = contributo % della lavorazione al SAL dell''elemento.';

-- ─── measurement_rule ─────────────────────────────────────────────────────────
-- Definisce quale quantità BIM usare per calcolare l'avanzamento di una lavorazione.
-- Es: lavorazione "Getto CLS" → usa quantità "Volume" (m³) degli elementi associati
CREATE TABLE IF NOT EXISTS bim.measurement_rule (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID         NOT NULL REFERENCES tenant.company(id),
    activity_id     UUID         NOT NULL REFERENCES bim.work_activity(id),
    -- Tipo quantità BIM da usare (deve corrispondere a bim_quantity.quantity_type)
    quantity_type   VARCHAR(100) NOT NULL,
    unit_of_measure VARCHAR(20)  NOT NULL,
    -- Aggregazione: SUM = somma delle quantità, MAX = massimo, AVG = media
    formula         TEXT         NOT NULL DEFAULT 'SUM',
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE bim.measurement_rule IS 'Regola di misura: quale quantità BIM usare per il SAL di una lavorazione.';

-- ─── time_profile ─────────────────────────────────────────────────────────────
-- Produttività attesa per una lavorazione.
-- Es: "Getto CLS" → 25 m³/giorno → TimePerUnit = 0.04 gg/m³
CREATE TABLE IF NOT EXISTS bim.time_profile (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID          NOT NULL REFERENCES tenant.company(id),
    activity_id     UUID          NOT NULL REFERENCES bim.work_activity(id),
    unit_of_measure VARCHAR(20)   NOT NULL,
    -- Produttività: unità prodotte per giornata lavorativa
    productivity    NUMERIC(10,3),
    -- Ore/uomo per unità (es. 0.04 gg/m³ = 4 ore per m³ con squadra di 10)
    time_per_unit   NUMERIC(10,4),
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE bim.time_profile IS 'Produttività attesa (m³/giorno, ore/unità). Input per stima tempi SAL.';

-- ─── Indici ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_bim_model_tenant    ON bim.bim_model(tenant_id);
CREATE INDEX IF NOT EXISTS idx_bim_model_project   ON bim.bim_model(project_code);
CREATE INDEX IF NOT EXISTS idx_bim_element_tenant  ON bim.bim_element(tenant_id);
CREATE INDEX IF NOT EXISTS idx_bim_element_model   ON bim.bim_element(model_id);
CREATE INDEX IF NOT EXISTS idx_bim_element_cat_fam ON bim.bim_element(category, family);
CREATE INDEX IF NOT EXISTS idx_bim_element_params  ON bim.bim_element USING gin(parameters);
CREATE INDEX IF NOT EXISTS idx_bim_quantity_tenant  ON bim.bim_quantity(tenant_id);
CREATE INDEX IF NOT EXISTS idx_bim_quantity_element ON bim.bim_quantity(element_id);
CREATE INDEX IF NOT EXISTS idx_bim_quantity_type    ON bim.bim_quantity(quantity_type);
CREATE INDEX IF NOT EXISTS idx_bim_phase_tenant     ON bim.construction_phase(tenant_id);
CREATE INDEX IF NOT EXISTS idx_bim_activity_tenant  ON bim.work_activity(tenant_id);
CREATE INDEX IF NOT EXISTS idx_bim_activity_phase   ON bim.work_activity(phase_id);
CREATE INDEX IF NOT EXISTS idx_bim_elem_act_tenant  ON bim.element_activity(tenant_id);
CREATE INDEX IF NOT EXISTS idx_bim_elem_act_elem    ON bim.element_activity(element_id);
CREATE INDEX IF NOT EXISTS idx_bim_elem_act_act     ON bim.element_activity(activity_id);
CREATE INDEX IF NOT EXISTS idx_bim_meas_rule_act    ON bim.measurement_rule(activity_id);
CREATE INDEX IF NOT EXISTS idx_bim_time_prof_act    ON bim.time_profile(activity_id);

-- ─── Constraint UNIQUE aggiunti post-deploy ───────────────────────────────────
-- Idempotenti: falliscono se eseguiti su un DB che ha già il constraint (es. prod).
-- Su un DB fresco i constraint sopra (inline in CREATE TABLE) li creano già.
-- Questi ALTER TABLE servono per aggiornare DB esistenti che mancavano del constraint.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'uq_bim_model_tenant_path'
    ) THEN
        ALTER TABLE bim.bim_model
            ADD CONSTRAINT uq_bim_model_tenant_path
            UNIQUE (tenant_id, source_gcs_path);
    END IF;
END$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'uq_bim_quantity_element_type'
    ) THEN
        ALTER TABLE bim.bim_quantity
            ADD CONSTRAINT uq_bim_quantity_element_type
            UNIQUE (element_id, quantity_type);
    END IF;
END$$;

-- =============================================================================
-- Migration 07 — 2026-05-06
-- Eseguita manualmente sul DB di produzione il 2026-05-06.
-- Registrata qui per tenere il DDL di riferimento allineato con lo schema reale.
--
-- ATTENZIONE: questi statement sono già stati eseguiti su prod.
--   - Su un DB di sviluppo nuovo: possono fallire se le colonne/tabelle esistono già.
--   - Usare "IF NOT EXISTS" / "IF EXISTS" per idempotenza.
-- =============================================================================

-- ─── bim_element: ID authoring Revit (parametro DE_IdElement) ─────────────────
-- Permette di correlare ogni elemento con il suo ID nell'ambiente di authoring BIM.
ALTER TABLE bim.bim_element
    ADD COLUMN IF NOT EXISTS bim_authoring_id VARCHAR(50);

COMMENT ON COLUMN bim.bim_element.bim_authoring_id
    IS 'ID dell''elemento nel sistema di authoring BIM (parametro DE_IdElement del JSON Revit)';

-- ─── bim_quantity: aggiunta fase costruttiva ──────────────────────────────────
-- La fase "DE" (Design) distingue i dati di progettazione da As-Built, ecc.
-- DEFAULT 'DE' per retrocompatibilità con i record già presenti.
ALTER TABLE bim.bim_quantity
    ADD COLUMN IF NOT EXISTS phase VARCHAR(2) NOT NULL DEFAULT 'DE';

-- Aggiorna il UNIQUE constraint per includere la fase.
-- Il vecchio constraint uq_bim_quantity_element_type è sostituito da uno che include phase.
ALTER TABLE bim.bim_quantity
    DROP CONSTRAINT IF EXISTS uq_bim_quantity_element_type;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'uq_bim_quantity_element_type_phase'
    ) THEN
        ALTER TABLE bim.bim_quantity
            ADD CONSTRAINT uq_bim_quantity_element_type_phase
            UNIQUE (element_id, quantity_type, phase);
    END IF;
END$$;

COMMENT ON COLUMN bim.bim_quantity.phase
    IS 'Fase costruttiva del dato: DE=Design, AB=As-Built, ecc. Sempre DE per quantità geometriche BIM.';

-- ─── bim_element_attribute: attributi parametrici per fase costruttiva ─────────
-- Archivia i parametri Revit prefissati (DE_, AB_, LK_, MA_) e i campi WBS
-- per ogni elemento, con tipo valore determinato automaticamente (numerico/testo/data).
CREATE TABLE IF NOT EXISTS bim.bim_element_attribute (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    -- FK a bim_element (NON a element_id esterno — è la PK del record bim_element)
    element_id     UUID         NOT NULL REFERENCES bim.bim_element(id) ON DELETE CASCADE,
    -- Fase costruttiva derivata dal prefisso del parametro Revit
    phase          VARCHAR(5)   NOT NULL CHECK (phase IN ('DE','AB','LK','MA','WBS')),
    -- Nome parametro senza prefisso (es. "DE_IdElement" → "IdElement")
    attribute_name VARCHAR(200) NOT NULL,
    -- Uno solo dei tre campi valore è non-NULL per riga
    value_numeric  NUMERIC(20,6),
    value_text     VARCHAR(500),
    value_date     DATE,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_bim_attr_element_phase_name UNIQUE (element_id, phase, attribute_name)
);

COMMENT ON TABLE bim.bim_element_attribute
    IS 'Attributi parametrici Revit per fase costruttiva. Estratti da parametri DE_/AB_/LK_/MA_ e campi _WBS.';
COMMENT ON COLUMN bim.bim_element_attribute.phase
    IS 'DE=Design, AB=As-Built, LK=Lavorazioni, MA=Manutenzione, WBS=Work Breakdown Structure';
COMMENT ON COLUMN bim.bim_element_attribute.attribute_name
    IS 'Nome parametro senza prefisso (per DE_: strip ''DE_'', per WBS: nome completo incluso suffisso)';

-- Indici per lookup per fase e per attribute_name
CREATE INDEX IF NOT EXISTS idx_bim_attr_element   ON bim.bim_element_attribute(element_id);
CREATE INDEX IF NOT EXISTS idx_bim_attr_phase      ON bim.bim_element_attribute(phase);
CREATE INDEX IF NOT EXISTS idx_bim_attr_name       ON bim.bim_element_attribute(attribute_name);
