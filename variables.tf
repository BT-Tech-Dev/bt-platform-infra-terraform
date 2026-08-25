# =============================================================================
# variables.tf — Definizione di tutte le variabili di input del root module
#
# I valori reali sono in terraform.tfvars (non committare se contiene segreti).
# Le variabili senza "default" DEVONO essere valorizzate in tfvars.
# =============================================================================

# ─── Progetto GCP ────────────────────────────────────────────────────────────

variable "project_id" {
  description = "ID del progetto GCP dove deployare tutta l'infrastruttura"
  type        = string
  # Esempio: "bt-platform-prod"
}

variable "region" {
  description = "Regione GCP primaria. europe-west8 = Milano (bassa latenza per clienti italiani)"
  type        = string
  default     = "europe-west8"
}

variable "billing_account" {
  description = "ID del billing account GCP (serve solo se si crea il progetto via Terraform)"
  type        = string
  default     = ""
}

# ─── Organizzazione ──────────────────────────────────────────────────────────

variable "org_id" {
  description = "ID numerico dell'organizzazione GCP (buildtrust.it)"
  type        = string
  default     = "862731545925"
}

# ─── Database ────────────────────────────────────────────────────────────────

variable "db_instance_name" {
  description = "Nome dell'istanza Cloud SQL PostgreSQL"
  type        = string
  default     = "bt-platform-pg-prod"
}

variable "db_name" {
  description = "Nome del database principale all'interno dell'istanza Cloud SQL"
  type        = string
  default     = "db_bt_platform"
}

variable "db_version" {
  description = "Versione PostgreSQL. 15 è la versione LTS attuale con supporto ottimo per UUID e JSON"
  type        = string
  default     = "POSTGRES_15"
}

variable "db_tier" {
  description = <<-EOT
    Tipo di macchina Cloud SQL.
    db-f1-micro  = 0.6 GB RAM (solo test/dev, non per produzione)
    db-g1-small  = 1.7 GB RAM (sviluppo/staging leggero)
    db-n1-standard-1 = 3.75 GB RAM (produzione minima consigliata)
    Per ora usiamo g1-small, si scala facilmente senza downtime.
  EOT
  type        = string
  default     = "db-g1-small"
}

# ─── Tenant iniziali ─────────────────────────────────────────────────────────

variable "enable_db_init" {
  description = "Se true, abilita il bootstrap DB via Cloud Build. Default false per evitare init_db involontari su ambienti live."
  type        = bool
  default     = false
}

variable "db_init_version" {
  description = "Versione manuale del bootstrap DB. Incrementare solo quando si vuole rilanciare esplicitamente init_db."
  type        = string
  default     = "manual-0"
}

variable "enable_debug_pubsub_subscriptions" {
  description = "Abilita subscription Pub/Sub manuali per debug/replay."
  type        = bool
  default     = false
}

variable "ocr_tasks_location" {
  description = "Regione Cloud Tasks per la queue OCR. europe-west8 non e' supportata da Cloud Tasks; default EU piu' vicino: europe-west6."
  type        = string
  default     = "europe-west6"
}

variable "ocr_tasks_queue_name" {
  description = "Nome della queue Cloud Tasks per il pilot OCR MS-05."
  type        = string
  default     = "bt-platform-ocr-extraction-prod"
}

variable "ocr_tasks_max_concurrent_dispatches" {
  description = "Massimo numero di task OCR dispatchati in parallelo."
  type        = number
  default     = 1
}

variable "ocr_tasks_max_dispatches_per_second" {
  description = "Rate massimo OCR pilot. 0.05 = circa 1 dispatch ogni 20 secondi."
  type        = number
  default     = 0.05
}

variable "ocr_tasks_max_attempts" {
  description = "Numero massimo di tentativi Cloud Tasks per task OCR."
  type        = number
  default     = 3
}

variable "ocr_tasks_min_retry_backoff_seconds" {
  description = "Backoff minimo Cloud Tasks OCR, in secondi."
  type        = number
  default     = 10
}

variable "ocr_tasks_max_retry_backoff_seconds" {
  description = "Backoff massimo Cloud Tasks OCR, in secondi."
  type        = number
  default     = 300
}

variable "ocr_tasks_max_retry_duration_seconds" {
  description = "Durata massima retry Cloud Tasks OCR, in secondi."
  type        = number
  default     = 3600
}

variable "ocr_tasks_dispatch_deadline_seconds" {
  description = "Dispatch deadline OCR Cloud Tasks. Deve essere <= 1800 e <= timeout worker."
  type        = number
  default     = 900

  validation {
    condition     = var.ocr_tasks_dispatch_deadline_seconds >= 1 && var.ocr_tasks_dispatch_deadline_seconds <= 1800
    error_message = "ocr_tasks_dispatch_deadline_seconds deve essere tra 1 e 1800."
  }
}

variable "ocr_tasks_logging_sampling_ratio" {
  description = "Sampling ratio dei log Cloud Tasks OCR."
  type        = number
  default     = 1.0
}

# ─── Cloud Tasks: coda dispatch asincrono MS-05 ingest ───────────────────────
# Tranche infra-only: Bucket Watcher -> raw.ingestion_dispatch -> Cloud Tasks
# -> production-ingestion-service. Nessuna applicazione accoda ancora su
# questa coda; e' sicura da applicare senza toccare il routing Eventarc/
# Pub/Sub live.

variable "ms05_tasks_location" {
  description = "Regione Cloud Tasks per la queue MS-05 ingest. europe-west8 non e' supportata da Cloud Tasks; default EU piu' vicino: europe-west6."
  type        = string
  default     = "europe-west6"
}

variable "ms05_tasks_queue_name" {
  description = "Nome della queue Cloud Tasks per il dispatch asincrono MS-05 ingest."
  type        = string
  default     = "bt-platform-ms05-ingest-prod"
}

variable "ms05_tasks_max_concurrent_dispatches" {
  description = "Massimo numero di task MS-05 ingest dispatchati in parallelo."
  type        = number
  default     = 2
}

variable "ms05_tasks_max_dispatches_per_second" {
  description = "Rate massimo dispatch MS-05 ingest."
  type        = number
  default     = 1
}

variable "ms05_tasks_max_attempts" {
  description = "Numero massimo di tentativi Cloud Tasks per task MS-05 ingest."
  type        = number
  default     = 5
}

variable "ms05_tasks_min_retry_backoff_seconds" {
  description = "Backoff minimo Cloud Tasks MS-05 ingest, in secondi."
  type        = number
  default     = 10
}

variable "ms05_tasks_max_retry_backoff_seconds" {
  description = "Backoff massimo Cloud Tasks MS-05 ingest, in secondi."
  type        = number
  default     = 300
}

variable "ms05_tasks_max_retry_duration_seconds" {
  description = "Durata massima retry Cloud Tasks MS-05 ingest, in secondi."
  type        = number
  default     = 3600
}

variable "ms05_tasks_logging_sampling_ratio" {
  description = "Sampling ratio dei log Cloud Tasks MS-05 ingest."
  type        = number
  default     = 1.0
}

variable "ms05_tasks_dispatch_deadline_seconds" {
  description = "Dispatch deadline Cloud Tasks per l'ingest MS-05. Deve essere tra 1 e 1800 secondi."
  type        = number
  default     = 360

  validation {
    condition     = var.ms05_tasks_dispatch_deadline_seconds >= 1 && var.ms05_tasks_dispatch_deadline_seconds <= 1800
    error_message = "ms05_tasks_dispatch_deadline_seconds deve essere tra 1 e 1800."
  }
}

variable "ms05_worker_target_url" {
  description = "URL HTTPS del worker Cloud Run MS-05 /tasks/ingest per Cloud Tasks."
  type        = string

  validation {
    condition     = startswith(var.ms05_worker_target_url, "https://")
    error_message = "ms05_worker_target_url deve usare HTTPS."
  }
}

variable "bucket_watcher_production_dispatch_backend" {
  description = "Backend di dispatch production del Bucket Watcher: pubsub per rollback, cloud_tasks per il cutover MS-05."
  type        = string
  default     = "pubsub"

  validation {
    condition     = contains(["pubsub", "cloud_tasks"], var.bucket_watcher_production_dispatch_backend)
    error_message = "bucket_watcher_production_dispatch_backend deve essere pubsub o cloud_tasks."
  }
}

variable "ocr_worker_timeout_seconds" {
  description = "Timeout request Cloud Run OCR worker, in secondi."
  type        = number
  default     = 900
}

variable "ocr_worker_max_instance_count" {
  description = "Max istanze OCR worker per pilot."
  type        = number
  default     = 1
}

variable "ocr_worker_concurrency" {
  description = "Concorrenza OCR worker per pilot."
  type        = number
  default     = 1
}

variable "ocr_vertex_project_id" {
  description = "Project Vertex AI OCR. Vuoto = usa project_id."
  type        = string
  default     = ""
}

variable "ocr_vertex_location" {
  description = "Location Vertex AI per OCR Gemini."
  type        = string
  default     = "europe-west8"
}

variable "ocr_vertex_model_id" {
  description = "Model ID Vertex Gemini per OCR pilot."
  type        = string
  default     = "gemini-2.5-flash"
}

variable "ocr_timeout_seconds" {
  description = "Timeout applicativo OCR provider, in secondi."
  type        = number
  default     = 900
}

variable "ocr_max_retries" {
  description = "Retry applicativi OCR provider."
  type        = number
  default     = 3
}

variable "ocr_raw_response_object_prefix" {
  description = "Prefix GCS nel bucket handoff per raw provider responses OCR."
  type        = string
  default     = "ocr/raw-responses/"
}

variable "ocr_schema_version" {
  description = "Versione schema OCR JSON attesa dall'applicazione."
  type        = string
  default     = "ocr-json-contract-v1"
}

variable "ocr_auto_profiles" {
  description = "Profili OCR auto-dispatch abilitabili quando OCR_AUTO_DISPATCH_ENABLED diventa true."
  type        = string
  default     = "ferroberica_steel_ddt_v1"
}

variable "evidence_link_handoff_mode" {
  description = "Enforcement mode for correction-safe operational-event evidence-link handoff in MS-05."
  type        = string

  validation {
    condition     = contains(["disabled", "required"], var.evidence_link_handoff_mode)
    error_message = "evidence_link_handoff_mode must be disabled or required."
  }
}

variable "initial_tenants" {
  description = <<-EOT
    Lista dei tenant iniziali da inserire nel seed del database.
    Ogni tenant è un cliente/progetto della piattaforma BuildTrust.
    Il tenant_id è un UUID fisso (determinístico) usato come FK in tutte le tabelle.
  EOT
  type = list(object({
    id          = string # UUID v4
    name        = string # Nome completo progetto
    code        = string # Codice breve (es. "PPDL", "BAL2")
    description = string
  }))
  default = [
    {
      id          = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
      name        = "Ponte sul Po di Levante"
      code        = "PPDL"
      description = "Opera: Viadotto Ponte sul Po di Levante, Codice 0549-IDG"
    },
    {
      id          = "b2c3d4e5-f6a7-8901-bcde-f12345678901"
      name        = "Balocco 2"
      code        = "BAL2"
      description = "Opera: Balocco 2 — stabilimento di produzione prefabbricati"
    }
  ]
}

# ─── Naming ──────────────────────────────────────────────────────────────────

variable "github_owner" {
  description = "Owner del repository GitHub (es. 'BT-Tech-Dev')"
  type        = string
  default     = "BT-Tech-Dev"
}

variable "github_repo_name" {
  description = "Nome del repository GitHub per bt-platform (es. 'bt-platform')"
  type        = string
  default     = "bt-bim-platform"
}

variable "bim_parser_tenant_id" {
  description = "UUID del tenant (company) per cui gira bim-parser-v1. Default: PPDL (Ponte Po di Levante)"
  type        = string
  default     = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}

variable "revit_export_bim_parser_image" {
  description = "Immutable Artifact Registry image digest used by the Revit actual export Job."
  type        = string

  validation {
    condition     = can(regex("^.+@sha256:[a-f0-9]{64}$", var.revit_export_bim_parser_image))
    error_message = "revit_export_bim_parser_image must use an immutable @sha256 digest reference."
  }
}

variable "ms05_recovery_image" {
  description = "Immutable production-ingestion-service image for the MS-05 recovery Job."
  type        = string

  validation {
    condition     = can(regex("^.+@sha256:[a-f0-9]{64}$", var.ms05_recovery_image))
    error_message = "ms05_recovery_image must use an immutable @sha256 digest reference."
  }
}

variable "revit_export_ro_password_rotation_epoch" {
  description = "Change deliberately to rotate the Revit export database password and Secret Manager version together."
  type        = number
  default     = 1

  validation {
    condition     = var.revit_export_ro_password_rotation_epoch >= 1
    error_message = "revit_export_ro_password_rotation_epoch must be at least 1."
  }
}

variable "iot_ingestion_image" {
  description = "Immutable Artifact Registry image digest for iot-ingestion-service. Set only after the application image is built."
  type        = string

  validation {
    condition     = can(regex("^.+/iot-ingestion-service@sha256:[a-f0-9]{64}$", var.iot_ingestion_image))
    error_message = "iot_ingestion_image must be an immutable iot-ingestion-service @sha256 digest reference."
  }
}

variable "environment" {
  description = "Ambiente di deployment. Usato nei nomi delle risorse per distinguere prod/staging/dev"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "L'ambiente deve essere uno tra: prod, staging, dev."
  }
}
