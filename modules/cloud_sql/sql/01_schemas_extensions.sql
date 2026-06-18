-- =============================================================================
-- 01_schemas_extensions.sql
-- Crea gli schemi PostgreSQL e abilita le estensioni necessarie
--
-- Eseguire come utente postgres (superuser) sul database db_bt_platform
-- Ordine: questo script va eseguito PRIMA di tutti gli altri
-- =============================================================================

-- Abilita generazione UUID automatica (uuid_generate_v4() o gen_random_uuid())
-- pgcrypto è incluso in PostgreSQL >= 13 senza installazione extra
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";  -- Alternativa per uuid_generate_v4()

-- =============================================================================
-- Creazione schemi
-- Ogni schema = un dominio funzionale separato.
-- Questo permette di assegnare permessi diversi per dominio e di isolare
-- le tabelle per chiarezza (es. bim.bim_model vs bim.work_activity).
-- =============================================================================

-- Schema 1: dati geometrici BIM (da Revit via plugin Orienta Trium)
CREATE SCHEMA IF NOT EXISTS bim;
COMMENT ON SCHEMA bim IS 'Imported BIM model data and project-specific BIM baseline/registry';

CREATE SCHEMA IF NOT EXISTS catalog;
COMMENT ON SCHEMA catalog IS 'Reusable/project-aware BT element type reference catalog independent from BIM imports';

-- Schema 2: processo costruttivo (fasi, lavorazioni, regole di misura)
CREATE SCHEMA IF NOT EXISTS process;
COMMENT ON SCHEMA process IS 'Processo costruttivo: fasi, lavorazioni, regole di misura, profili temporali';

-- Schema 3: computo metrico e valorizzazione economica (BOQ = Bill of Quantities)
CREATE SCHEMA IF NOT EXISTS boq;
COMMENT ON SCHEMA boq IS 'Computo metrico (BOQ): voci, prezzi unitari, link a lavorazioni';

-- Schema 4: dati di produzione industriale (OPC UA, Grigolin, Superbeton)
CREATE SCHEMA IF NOT EXISTS production;
COMMENT ON SCHEMA production IS 'Produzione industriale: record OPC UA, ricette calcestruzzo, ordini di produzione';

-- Schema 5: avanzamento lavori (SAL) - il cuore della piattaforma
CREATE SCHEMA IF NOT EXISTS progress;
COMMENT ON SCHEMA progress IS 'Avanzamento lavori: SAL per lavorazione e per elemento BIM, uso materiali in cantiere';

-- Schema 6: qualità (certificati di prova, non conformità NCR)
CREATE SCHEMA IF NOT EXISTS quality;
COMMENT ON SCHEMA quality IS 'Qualità: certificati di prova, non conformità (NCR), blocchi SAL';

-- Schema 7: tenant e progetti (gestione multi-cliente)
CREATE SCHEMA IF NOT EXISTS tenant;
COMMENT ON SCHEMA tenant IS 'Multi-tenancy: tenant (clienti/progetti), configurazioni per tenant';

-- Schema 8: documenti e file allegati
CREATE SCHEMA IF NOT EXISTS document;
COMMENT ON SCHEMA document IS 'Gestione documenti: metadati file caricati su GCS (BIM, contratti, DDT, ecc.)';

-- Schema 9: proiezioni CQRS read-side (viste materializzate aggregate)
CREATE SCHEMA IF NOT EXISTS read;
COMMENT ON SCHEMA read IS 'CQRS read-side: proiezioni aggregate per il frontend React/Hasura (sola lettura)';

-- Schema 10: integrazioni esterne (Procore, ACC, TeamSystem, Primavera)
CREATE SCHEMA IF NOT EXISTS external;
COMMENT ON SCHEMA external IS 'Integrazioni esterne: log sync, dati da Procore/ACC/TeamSystem/Primavera';

-- =============================================================================
-- Permessi per gli utenti applicativi
-- bt_app   = lettura + scrittura su tutti gli schemi (microservizi write-side)
-- bt_readonly = solo lettura (Hasura read-side, analytics, report)
-- =============================================================================

-- bt_app: accesso completo agli schemi applicativi
GRANT USAGE ON SCHEMA bim, catalog, process, boq, production, progress, quality, tenant, document, read, external
  TO bt_app;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA bim, catalog, process, boq, production, progress, quality, tenant, document, read, external
  TO bt_app;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA bim, catalog, process, boq, production, progress, quality, tenant, document, read, external
  TO bt_app;

-- Imposta il default per le tabelle future (CREATE TABLE eseguiti dopo questo script)
ALTER DEFAULT PRIVILEGES IN SCHEMA bim, catalog, process, boq, production, progress, quality, tenant, document, read, external
  GRANT ALL PRIVILEGES ON TABLES TO bt_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA bim, catalog, process, boq, production, progress, quality, tenant, document, read, external
  GRANT ALL PRIVILEGES ON SEQUENCES TO bt_app;

-- bt_readonly: solo SELECT su tutti gli schemi
GRANT USAGE ON SCHEMA bim, catalog, process, boq, production, progress, quality, tenant, document, read, external
  TO bt_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA bim, catalog, process, boq, production, progress, quality, tenant, document, read, external
  TO bt_readonly;

ALTER DEFAULT PRIVILEGES IN SCHEMA bim, catalog, process, boq, production, progress, quality, tenant, document, read, external
  GRANT SELECT ON TABLES TO bt_readonly;
