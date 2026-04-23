# PROJECT_CONTEXT — BuildTrust Piattaforma BIM
## Ponte sul Po di Levante · GCP Integration Platform
**Versione:** v1.3 · **Aggiornato:** 2026-03-19

---

## 1. OVERVIEW

Piattaforma di integrazione BIM su GCP che riceve file JSON esportati da Revit
(plugin Orienta Trium), li valida, li processa e li carica nel database PostgreSQL
seguendo il data model progettato da Marco (data architect).

**Opera:** Ponte sul Po di Levante  
**Codice progetto:** 0549-IDG  
**Stack:** GCP Cloud Run · Cloud Storage · Cloud SQL · Pub/Sub · EventArc · Cloud Build

---

## 2. GCP PROJECT

| Campo | Valore |
|---|---|
| Project ID | `bt-bim-po-levante-prod` |
| Project name | `BT-BIM-Po-Levante-PROD` |
| Project number | `380448233409` |
| Region | `europe-west8` (Milano) |

---

## 3. DATABASE — Cloud SQL PostgreSQL

| Campo | Valore |
|---|---|
| Istanza | `bt-bim-po-levante-pg-prod` |
| Connection name | `bt-bim-po-levante-prod:europe-west8:bt-bim-po-levante-pg-prod` |
| Database | `db_bim` |
| Schema | `bt_v1` |
| Utente applicativo | `bim_etl_app` |
| Password | Secret Manager → `db_password` |
| Accesso da Cloud Run | IP Privato (Cloud SQL Connector pg8000) |

### 3.1 Tabelle (18) nello schema bt_v1

**BIM (dati geometrici da Revit):**
- `bim_model` — modelli BIM importati
- `bim_element` — elementi BIM filtrati (target: 83)
- `bim_quantity` — quantità geometriche degli elementi

**Processo costruttivo:**
- `construction_phase` — fasi (es. Strutture)
- `work_activity` — lavorazioni (es. Getto CLS)
- `element_activity` — link elemento ↔ lavorazione
- `measurement_rule` — regole di misura
- `time_profile` — stime temporali

**Computo metrico (BOQ):**
- `boq` — computo metrico
- `boq_item` — voci del computo
- `boq_activity` — link voce ↔ lavorazione

**Avanzamento lavori (SAL):**
- `work_progress` — avanzamento per lavorazione
- `element_progress` — avanzamento per elemento BIM

**Produzione:**
- `production_record` — record di produzione (OPC UA)
- `mix_recipe` — ricette calcestruzzo
- `mix_recipe_component` — componenti ricetta

**Qualità:**
- `quality_test_certificate` — certificati di prova
- `non_conformity` — non conformità (NCR)

---

## 4. CLOUD STORAGE — BUCKET

### 4.1 Staging Bucket
**Nome:** `bt-bim-po-levante-staging-prod`  
**Struttura prefissi:**
```
uploads/          ← qui viene caricato il JSON da Revit (upload manuale/plugin)
rejected/         ← file rifiutati (dimensione o estensione)
```

### 4.2 Ingest Bucket
**Nome:** `bt-bim-po-levante-ingest-prod`  
**Struttura prefissi:**
```
landing/
  incoming/       ← file appena ricevuti da staging
  rejected/       ← file rifiutati dal bim-ingest
llm/
  incoming/       ← JSON pronti per elaborazione LLM/passthrough
  done/           ← JSON elaborati da bim-llm-merge
handoff/
  etl/            ← JSON pronti per bim-etl (output di bim-llm-merge)
processed/
  etl/            ← JSON già caricati nel DB (output di bim-etl)
audit/
  raw/            ← file non-JSON archiviati
  enriched/       ← (futuro) JSON arricchiti da LLM
error/
  ingest/         ← errori da bim-ingest
  llm/            ← errori da bim-llm-merge
  etl/            ← errori da bim-etl
```

---

## 5. CLOUD RUN SERVICES

> Versioni v1 = produzione attiva. Le versioni senza suffisso sono disabilitate/legacy.

### 5.1 bim-staging-router-v1
**Funzione:** Riceve notifica GCS → copia JSON da staging a ingest  
**URL:** `https://bim-staging-router-v1-380448233409.europe-west8.run.app`

| Env var | Valore |
|---|---|
| STAGING_BUCKET | `bt-bim-po-levante-staging-prod` |
| INGEST_BUCKET | `bt-bim-po-levante-ingest-prod` |
| SOURCE_PREFIX | `uploads/` |
| DEST_PREFIX | `landing/incoming/` |
| REJECTED_PREFIX | `rejected/` |
| ALLOWED_EXTENSIONS | `.json` |
| MAX_SIZE_MB | `50` |
| LOG_LEVEL | `INFO` |

**Resources:** CPU=1, RAM=512MiB, Concurrency=80, Timeout=300s

---

### 5.2 bim-ingest-v1
**Funzione:** Valida estensione e dimensione → routing JSON verso llm/incoming/ o audit/  
**URL:** `https://bim-ingest-v1-380448233409.europe-west8.run.app`

| Env var | Valore |
|---|---|
| INGEST_BUCKET | `bt-bim-po-levante-ingest-prod` |
| LANDING_PREFIX | `landing/incoming/` |
| LLM_INCOMING_PREFIX | `llm/incoming/` |
| NON_JSON_PREFIX | `audit/raw/nonjson/` |
| REJECTED_PREFIX | `landing/rejected/` |
| ERROR_PREFIX | `error/ingest/` |
| ALLOWED_EXTENSIONS | `.json,.ifc,.pdf,.xlsx,.csv,.xls,.txt` |
| MAX_SIZE_MB | `50` |
| LOG_LEVEL | `INFO` |

**Resources:** CPU=1, RAM=512MiB, Concurrency=80, Timeout=300s

---

### 5.3 bim-llm-merge-v1
**Funzione:** Passthrough (LLM_ENABLED=false) → flattening parametri → handoff verso ETL  
**Nota:** Predisposto per LLM OpenAI ma attualmente disabilitato.  
**URL:** `https://bim-llm-merge-v1-380448233409.europe-west8.run.app`

| Env var | Valore |
|---|---|
| INGEST_BUCKET | `bt-bim-po-levante-ingest-prod` |
| LLM_INCOMING_PREFIX | `llm/incoming/` |
| LLM_DONE_PREFIX | `llm/done/` |
| AUDIT_RAW_PREFIX | `audit/raw/` |
| AUDIT_ENRICHED_PREFIX | `audit/enriched/` |
| ETL_HANDOFF_PREFIX | `handoff/etl/` |
| ERROR_PREFIX | `error/llm/` |
| LLM_ENABLED | `false` |
| LLM_MODEL | `gpt-4o-mini` |
| LLM_BASE_URL | `https://api.openai.com/v1` |
| LLM_API_KEY | Secret Manager → `llm_api_key` |
| LLM_TIMEOUT_SEC | `120` |
| LLM_TEMPERATURE | `0.2` |
| LLM_MAX_TOKENS | `2000` |
| FLATTEN_PARAMETERS | `true` |
| PRUNE_MODE | `light` |
| CHUNK_SIZE | `500` |
| MAX_SIZE_MB | `50` |
| INSTANCE_CONNECTION_NAME | `bt-bim-po-levante-prod:europe-west8:bt-bim-po-levante-pg-prod` |
| DB_USER | `bim_etl_app` |
| DB_NAME | `db_bim` |
| DB_SCHEMA | `bt_v1` |
| DB_PASSWORD | Secret Manager → `db_password` |

**Resources:** CPU=1, RAM=512MiB, Concurrency=80, Timeout=300s

---

### 5.4 bim-etl-v1
**Funzione:** Carica JSON da handoff/etl/ nel DB PostgreSQL bt_v1  
**URL:** `https://bim-etl-v1-380448233409.europe-west8.run.app`

| Env var | Valore |
|---|---|
| INGEST_BUCKET | `bt-bim-po-levante-ingest-prod` |
| HANDOFF_PREFIX | `handoff/etl/` |
| PROCESSED_OUT_PREFIX | `processed/etl/` |
| ERROR_PREFIX | `error/etl/` |
| FINALIZE_DELETE_ORIGINAL | `true` |
| ALLOWED_EXTENSIONS | `.json` |
| MAX_SIZE_MB | `50` |
| INSTANCE_CONNECTION_NAME | `bt-bim-po-levante-prod:europe-west8:bt-bim-po-levante-pg-prod` |
| DB_USER | `bim_etl_app` |
| DB_NAME | `db_bim` |
| DB_SCHEMA | `bt_v1` |
| DB_PASSWORD | Secret Manager → `db_password` |
| LOG_LEVEL | `INFO` |

**Resources:** CPU=1, RAM=512MiB, Concurrency=**1** (importante: no parallelismo su ETL), Timeout=300s

---

## 6. FLUSSO DATI (PIPELINE)

```
[Revit Plugin - Orienta Trium]
        ↓ export JSON
[GCS: bt-bim-po-levante-staging-prod/uploads/]
        ↓ GCS notification → Pub/Sub: gcs-staging-uploads-v1
[EventArc: trg-staging-uploads-to-router-v1]
        ↓
[Cloud Run: bim-staging-router-v1]  copy JSON →
[GCS: ingest/landing/incoming/]
        ↓ GCS notification → Pub/Sub: gcs-ingest-landing-v1
[EventArc: trg-ingest-landing-to-ingest-v1]
        ↓
[Cloud Run: bim-ingest-v1]  valida ext/size → move a llm/incoming/
        ↓ GCS notification → Pub/Sub: gcs-ingest-llm-incoming-v1
[EventArc: trg-ingest-llm-incoming-to-llm-merge-v1]
        ↓
[Cloud Run: bim-llm-merge-v1]  flattening params → move a handoff/etl/
        ↓ GCS notification → Pub/Sub: gcs-ingest-processed-v1
[EventArc: trg-ingest-processed-to-etl-v1]
        ↓
[Cloud Run: bim-etl-v1]  carica in PostgreSQL → move a processed/etl/
        ↓
[Cloud SQL PostgreSQL: db_bim / bt_v1]
```

---

## 7. PUB/SUB TOPICS

| Topic ID | Full name |
|---|---|
| gcs-staging-uploads-v1 | `projects/bt-bim-po-levante-prod/topics/gcs-staging-uploads-v1` |
| gcs-ingest-landing-v1 | `projects/bt-bim-po-levante-prod/topics/gcs-ingest-landing-v1` |
| gcs-ingest-llm-incoming-v1 | `projects/bt-bim-po-levante-prod/topics/gcs-ingest-llm-incoming-v1` |
| gcs-ingest-processed-v1 | `projects/bt-bim-po-levante-prod/topics/gcs-ingest-processed-v1` |

> Esistono anche versioni legacy (senza -v1) ma non attive nella pipeline.  
> Esistono anche topic `container-analysis-*` creati automaticamente da GCP per Artifact Registry.

---

## 8. EVENTARC TRIGGERS

| Trigger | Topic Pub/Sub | Destinazione Cloud Run |
|---|---|---|
| trg-staging-uploads-to-router-v1 | gcs-staging-uploads-v1 | bim-staging-router-v1 |
| trg-ingest-landing-to-ingest-v1 | gcs-ingest-landing-v1 | bim-ingest-v1 |
| trg-ingest-llm-incoming-to-llm-merge-v1 | gcs-ingest-llm-incoming-v1 | bim-llm-merge-v1 |
| trg-ingest-processed-to-etl-v1 | gcs-ingest-processed-v1 | bim-etl-v1 |

**Tutti i trigger:** Regione europe-west8 · Tipo evento: `google.cloud.pubsub.topic.v1.messagePublished`  
**Service account trigger:** `sa-bim-eventarc-prod@bt-bim-po-levante-prod.iam.gserviceaccount.com`

---

## 9. CLOUD BUILD — CI/CD

**Repository GitHub:** `BT-Tech-Dev/bt-bim-po-levante-platform`  
**Connessione:** App GitHub di Cloud Build  
**Artifact Registry:** `europe-west8-docker.pkg.dev/bt-bim-po-levante-prod/bt-bim/`

| Trigger Cloud Build | Stato | Branch | Configura |
|---|---|---|---|
| cb-bim-staging-router-v1 | ✅ Abilitata | push su branch | `cloudbuild.yaml` |
| cb-bim-ingest-v1 | ✅ Abilitata | push su branch | `cloudbuild.yaml` |
| cb-bim-llm-merge-v1 | ✅ Abilitata | push su branch | `cloudbuild.yaml` |
| cb-bim-etl-v1 | ✅ Abilitata | push su branch | `cloudbuild.yaml` |

> Le versioni senza -v1 (cb-bim-etl, cb-bim-ingest ecc.) sono disabilitate.  
> **Deploy:** push al branch corretto → Cloud Build builda Docker image → push su Artifact Registry → deploy su Cloud Run automatico.

---

## 10. IAM — SERVICE ACCOUNTS

| SA Name | Email | Ruoli |
|---|---|---|
| sa-bim-etl-prod | `sa-bim-etl-prod@bt-bim-po-levante-prod.iam.gserviceaccount.com` | Cloud SQL Client, Storage Object Admin |
| sa-bim-eventarc-prod | `sa-bim-eventarc-prod@bt-bim-po-levante-prod.iam.gserviceaccount.com` | Cloud Run Invoker, EventArc Event Receiver, Pub/Sub Publisher |
| sa-bim-ingest-prod | `sa-bim-ingest-prod@bt-bim-po-levante-prod.iam.gserviceaccount.com` | Cloud Run Invoker, Cloud SQL Client |
| sa-bim-llm-prod | `sa-bim-llm-prod@bt-bim-po-levante-prod.iam.gserviceaccount.com` | Cloud SQL Client, Storage Object Admin |
| sa-bim-staging-prod | `sa-bim-staging-prod@bt-bim-po-levante-prod.iam.gserviceaccount.com` | Storage Object Admin, Storage Object Creator, Storage Object Viewer |
| sa-cloudbuild-deployer-436 | `sa-cloudbuild-deployer-436@bt-bim-po-levante-prod.iam.gserviceaccount.com` | Artifact Registry Writer, Cloud Run Admin, Logs Writer, Service Account User |

**Admin:** `admin@buildtrust.it` — Organization Administrator + Owner

---

## 11. SECRET MANAGER

| Secret | Usato da | Creato |
|---|---|---|
| `db_password` | bim-etl-v1, bim-llm-merge-v1 | 2026-01-19 |
| `llm_api_key` | bim-llm-merge-v1 (OpenAI API key) | 2026-01-19 |

---

## 12. TARGET ELEMENTI BIM (83 totale)

Il plugin Orienta Trium esporta più elementi di quelli necessari.
Il filtro avviene nel `bim-etl-v1`. Solo questi elementi vengono salvati nel DB:

| Categoria | N. | Regola di filtro | Famiglie ammesse |
|---|---|---|---|
| Structural Foundations | 48 | Tutti | — |
| Structural Columns | 2 | Tutti (Torri) | — |
| Structural Connections | 8 | Solo IDG_CN_SU_STL_SlidingBearing | `IDG_CN_SU_STL_SlidingBearing` |
| Structural Framing | 25 | Solo IDG Impalcati + Stralli | `IDG_SF_STL_Segment1..9`, `IDG_CN_CB_0.11m_STL`, `IDG_CN_CB_0.20m_STL` |
| **TOTALE** | **83** | | |

**ESCLUSE sempre:**
- `Model Groups` (7 gruppi Connection S1-S2..S7-S8)
- `Specialty Equipment` (539 elementi vari)
- `Structural Framing`: PL8*75 (256), PL20*195 (128), ANGLE* (17), BRACING (1)
- `Structural Connections`: BEAM 99661 (1), ROD170 (4), ROD85 (12)

---

## 13. JSON DI INPUT — STRUTTURA

Il plugin Orienta Trium esporta un JSON con questa struttura top-level:
```json
{
  "FileName": "0549-IDG-PPDL-L00-A-INF-3D-A",
  "ExportGuid": "...",
  "DateTime": "...",
  "VersionJsonFile": "...",
  "ProjectInformation": [
    {"Name": "Project_Number_", "Value": "0549-IDG"},
    {"Name": "PI_File_Name", "Value": "..."}
  ],
  "Elements": {
    "Structural Foundations": [ {elemento1}, ... ],
    "Structural Framing": [ ... ],
    "Structural Connections": [ ... ],
    "Structural Columns": [ ... ],
    "Model Groups": [ ... ],
    "Specialty Equipment": [ ... ],
    "Materials": [ ... ],
    "Levels": [ ... ]
  }
}
```
Ogni elemento ha: `IfcGuid`, `FamilyName`, `SymbolName`, `Category`, `Level`,  
`InstanceParameters: [{Name, Value, UM}]`, `SymbolParameters: [{Name, Value, UM}]`

---

## 14. SISTEMA ESTERNO — REVIT PLUGIN

**Fornitore:** Orienta Trium  
**Funzione:** Esporta il modello BIM Revit in formato JSON  
**File Revit:** `0549-IDG-PPDL-L00-A-INF-3D-A.rvt`  
**Upload:** Manuale su `bt-bim-po-levante-staging-prod/uploads/`  
**Stato attuale:** JSON al ~90% del modello finale, strutture completate

---

## 15. NOTE OPERATIVE

### Reset DB completo (per test)
```sql
-- Eseguire in ordine (rispettare FK)
TRUNCATE TABLE bt_v1.bim_quantity             RESTART IDENTITY CASCADE;
TRUNCATE TABLE bt_v1.element_activity         RESTART IDENTITY CASCADE;
TRUNCATE TABLE bt_v1.element_progress         RESTART IDENTITY CASCADE;
TRUNCATE TABLE bt_v1.bim_element              RESTART IDENTITY CASCADE;
TRUNCATE TABLE bt_v1.bim_model                RESTART IDENTITY CASCADE;
TRUNCATE TABLE bt_v1.measurement_rule         RESTART IDENTITY CASCADE;
TRUNCATE TABLE bt_v1.time_profile             RESTART IDENTITY CASCADE;
TRUNCATE TABLE bt_v1.boq_activity             RESTART IDENTITY CASCADE;
TRUNCATE TABLE bt_v1.work_progress            RESTART IDENTITY CASCADE;
TRUNCATE TABLE bt_v1.work_activity            RESTART IDENTITY CASCADE;
TRUNCATE TABLE bt_v1.construction_phase       RESTART IDENTITY CASCADE;
TRUNCATE TABLE bt_v1.boq_item                 RESTART IDENTITY CASCADE;
TRUNCATE TABLE bt_v1.boq                      RESTART IDENTITY CASCADE;
TRUNCATE TABLE bt_v1.non_conformity           RESTART IDENTITY CASCADE;
TRUNCATE TABLE bt_v1.quality_test_certificate RESTART IDENTITY CASCADE;
TRUNCATE TABLE bt_v1.production_record        RESTART IDENTITY CASCADE;
TRUNCATE TABLE bt_v1.mix_recipe_component     RESTART IDENTITY CASCADE;
TRUNCATE TABLE bt_v1.mix_recipe               RESTART IDENTITY CASCADE;
```

### Verifica elementi dopo import
```sql
-- Conta per categoria (target: 48+2+8+25=83)
SELECT category, family, COUNT(*) as n
FROM bt_v1.bim_element
GROUP BY category, family
ORDER BY category, family;

-- Conta quantità
SELECT COUNT(*) FROM bt_v1.bim_quantity;
```

### Deploy nuovo codice (bim-etl-v1)
```bash
# Modifica main.py nel repo BT-Tech-Dev/bt-bim-po-levante-platform
# Push sul branch configurato nel trigger cb-bim-etl-v1
# Cloud Build fa tutto automaticamente
```

---

## 16. VERSIONING FILE

| Versione | Data | Modifiche |
|---|---|---|
| v1.0 | 2026-01-19 | Setup iniziale infrastruttura |
| v1.1 | 2026-02-24 | Deploy v1 services (produzione) |
| v1.2 | 2026-02-26 | Fix filtri ETL (Connections sub-filter) |
| v1.3 | 2026-03-19 | Fix filtri ETL (Framing sub-filter), PROJECT_CONTEXT.md creato |