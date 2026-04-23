-- =============================================================================
-- migrate_01_bim_add_wbs.sql
-- Schema: bim ← sposta le 5 tabelle WBS da process
--
-- COSA FA:
--   Sposta construction_phase, work_activity, measurement_rule,
--   time_profile, element_activity dallo schema "process" a "bim".
--
-- PERCHÉ:
--   Le WBS tables descrivono la struttura costruttiva degli elementi BIM.
--   Appartengono logicamente al dominio BIM, non al dominio "contratto".
--   Lo schema "process" verrà ripulito per contenere solo dati contrattuali.
--
-- NOTA POSTGRESQL:
--   ALTER TABLE ... SET SCHEMA ... sposta la tabella E aggiorna automaticamente
--   tutti i vincoli FK che puntano a quella tabella (non serve toccare le altre tabelle).
--   I FK da process.work_activity → bim.construction_phase etc. restano validi.
--   Il FK da progress.work_progress.activity_id → bim.work_activity(id)
--   viene aggiornato automaticamente.
--
-- SICURO DA RIESEGUIRE: lo script usa DO/EXCEPTION per ignorare operazioni già fatte.
-- =============================================================================

BEGIN;

-- ─── Sposta construction_phase ───────────────────────────────────────────────
DO $$
BEGIN
    -- Controlla se la tabella è ancora in process (non ancora mossa)
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'process' AND table_name = 'construction_phase'
    ) THEN
        ALTER TABLE process.construction_phase SET SCHEMA bim;
        RAISE NOTICE 'Spostata: process.construction_phase → bim.construction_phase';
    ELSE
        RAISE NOTICE 'SKIP: construction_phase non trovata in process (già mossa o non esiste)';
    END IF;
END $$;

-- ─── Sposta work_activity ────────────────────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'process' AND table_name = 'work_activity'
    ) THEN
        ALTER TABLE process.work_activity SET SCHEMA bim;
        RAISE NOTICE 'Spostata: process.work_activity → bim.work_activity';
    ELSE
        RAISE NOTICE 'SKIP: work_activity non trovata in process';
    END IF;
END $$;

-- ─── Sposta measurement_rule ─────────────────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'process' AND table_name = 'measurement_rule'
    ) THEN
        ALTER TABLE process.measurement_rule SET SCHEMA bim;
        RAISE NOTICE 'Spostata: process.measurement_rule → bim.measurement_rule';
    ELSE
        RAISE NOTICE 'SKIP: measurement_rule non trovata in process';
    END IF;
END $$;

-- ─── Sposta time_profile ─────────────────────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'process' AND table_name = 'time_profile'
    ) THEN
        ALTER TABLE process.time_profile SET SCHEMA bim;
        RAISE NOTICE 'Spostata: process.time_profile → bim.time_profile';
    ELSE
        RAISE NOTICE 'SKIP: time_profile non trovata in process';
    END IF;
END $$;

-- ─── Sposta element_activity ─────────────────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'process' AND table_name = 'element_activity'
    ) THEN
        ALTER TABLE process.element_activity SET SCHEMA bim;
        RAISE NOTICE 'Spostata: process.element_activity → bim.element_activity';
    ELSE
        RAISE NOTICE 'SKIP: element_activity non trovata in process';
    END IF;
END $$;

-- ─── Verifica finale ─────────────────────────────────────────────────────────
DO $$
DECLARE
    missing_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO missing_count
    FROM information_schema.tables
    WHERE table_schema = 'bim'
      AND table_name IN ('construction_phase','work_activity','measurement_rule','time_profile','element_activity');

    IF missing_count = 5 THEN
        RAISE NOTICE 'OK: tutte e 5 le tabelle WBS sono ora in schema bim';
    ELSE
        RAISE WARNING 'ATTENZIONE: trovate solo % tabelle su 5 in schema bim', missing_count;
    END IF;
END $$;

COMMIT;
