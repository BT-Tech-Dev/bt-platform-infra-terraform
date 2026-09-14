-- =============================================================================
-- migrate_32_contract_gantt_milestone_support.sql
-- Schema: process
--
-- Migration condivisa per contract-ingestor-v1 e gantt-parser-v1.
--
-- NUMERAZIONE: 32, non 23. migrate_23..30 sono di fatto già riservati da un
-- filone di lavoro non ancora mergiato (Roberto Armellini, process.operational_event/
-- Moretti) -- migrate_31_grant_revit_export_operational_event.sql è già su main e
-- referenzia migrate_30 come prerequisito. Usare quel range collide appena quel
-- lavoro merge. 32 è il primo numero libero sicuro dopo l'ultimo file reale.
--
-- COSA FA:
--   1. process.contract: source_gcs_path/source_file_hash (revision guard di
--      contract-ingestor-v1, mirror di bim.bim_model/boq.boq).
--   2. process.milestone: colonna conditions JSONB (Opzione A, SAL-02-T13) +
--      UNIQUE(tenant_id, contract_id, code) -- serve sia all'upsert di
--      contract-ingestor-v1 sia all'UPDATE di gantt-parser-v1.
--   3. Nuova tabella process.gantt_import: header/revision-tracking per
--      progetto Gantt -- una riga per progetto, non a versioni (un Gantt
--      cambia in continuazione; ogni reimport aggiorna lo stato esistente).
--   4. process.gantt_activity: platform_project_code + indice unico
--      (tenant_id, platform_project_code, wbs_code) -- necessario perché
--      contract_id è nullable qui e wbs_code da solo non basta a
--      discriminare tra progetti diversi dello stesso tenant.
--
-- NOTA: additiva soltanto. process.contract, process.milestone e
-- process.gantt_activity sono vuote su main oggi (verificato) -- nessun
-- backfill necessario, nessuna riga esistente toccata.
-- =============================================================================

BEGIN;

-- 1. process.contract -- tracciamento file sorgente
ALTER TABLE process.contract
    ADD COLUMN IF NOT EXISTS source_gcs_path TEXT,
    ADD COLUMN IF NOT EXISTS source_file_hash VARCHAR(64);

-- 2. process.milestone -- conditions (Opzione A) + vincolo di unicità
ALTER TABLE process.milestone
    ADD COLUMN IF NOT EXISTS conditions JSONB;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'uq_milestone_contract_code'
    ) THEN
        ALTER TABLE process.milestone
            ADD CONSTRAINT uq_milestone_contract_code UNIQUE (tenant_id, contract_id, code);
    END IF;
END $$;

-- 3. process.gantt_import -- nuova tabella, header per progetto
CREATE TABLE IF NOT EXISTS process.gantt_import (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               UUID         NOT NULL REFERENCES tenant.company(id),
    contract_id             UUID         REFERENCES process.contract(id),
    platform_project_code   VARCHAR(50)  NOT NULL,
    source_gcs_path         TEXT,
    source_file_hash        VARCHAR(64),
    imported_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, platform_project_code)
);

-- 4. process.gantt_activity -- discriminatore di progetto + vincolo di unicità
ALTER TABLE process.gantt_activity
    ADD COLUMN IF NOT EXISTS platform_project_code VARCHAR(50) NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_gantt_activity_project_wbs
    ON process.gantt_activity (tenant_id, platform_project_code, wbs_code);

COMMIT;
