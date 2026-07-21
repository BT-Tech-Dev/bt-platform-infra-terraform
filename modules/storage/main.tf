# =============================================================================
# modules/storage/main.tf — Bucket GCS per la pipeline BIM
#
# 3 bucket, stessa logica del vecchio progetto bt-bim-po-levante ma nel
# nuovo progetto bt-platform-prod e con naming multi-tenant:
#
#   staging  → il plugin Revit (Orienta Trium) carica i JSON BIM qui
#   ingest   → pipeline di validazione e processamento
#   handoff  → zona di scambio tra i microservizi (ETL, LLM, parser)
#
# Lifecycle: i file vengono spostati tra bucket dalla pipeline stessa.
# I file "vecchi" (30-90gg) vengono archiviati/eliminati automaticamente
# tramite le lifecycle rules.
# =============================================================================

locals {
  # Prefisso comune per tutti i bucket del progetto
  bucket_prefix                  = "bt-platform"
  ocr_raw_response_object_prefix = trim(var.ocr_raw_response_object_prefix, "/")
  vertex_ai_service_agent        = "service-${data.google_project.current.number}@gcp-sa-aiplatform.iam.gserviceaccount.com"
}

data "google_project" "current" {
  project_id = var.project_id
}

# ─── Bucket: Staging ─────────────────────────────────────────────────────────
# Punto di ingresso della pipeline. Il plugin Revit carica i JSON qui.
# Struttura:
#   uploads/          ← upload dal plugin (o manuale)
#   rejected/         ← file respinti (dimensione > 50MB, estensione sbagliata)

resource "google_storage_bucket" "staging" {
  name          = "${local.bucket_prefix}-staging-${var.environment}"
  project       = var.project_id
  location      = var.region
  storage_class = "STANDARD"

  # Impedisce la cancellazione accidentale via terraform destroy
  # (impostare a false SOLO per ambienti di test)
  force_destroy = false

  # Versionamento: mantieni le versioni precedenti dei file (utile per debug)
  versioning {
    enabled = true
  }

  # Regole di retention automatica per evitare accumulo di file
  lifecycle_rule {
    condition {
      age            = 30 # giorni
      matches_prefix = ["rejected/"]
    }
    action {
      type = "Delete" # Cancella i file respinti dopo 30 giorni
    }
  }

  lifecycle_rule {
    condition {
      age            = 90
      matches_prefix = ["uploads/"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE" # Tier più economico per archivio storico
    }
  }

  # Blocca l'accesso pubblico al bucket (solo SA autorizzati possono accedere)
  uniform_bucket_level_access = true

  labels = {
    environment = var.environment
    component   = "bim-pipeline"
    bucket_role = "staging"
  }
}

# ─── Bucket: Ingest ──────────────────────────────────────────────────────────
# Pipeline di lavorazione interna.
# Struttura (stessa del vecchio progetto bt-bim-po-levante-ingest-prod):
#   landing/incoming/   ← file appena ricevuti da staging
#   landing/rejected/   ← file respinti da bim-ingest
#   llm/incoming/       ← pronti per LLM/passthrough
#   llm/done/           ← elaborati da bim-llm-merge
#   error/              ← file con errori di processing

resource "google_storage_bucket" "ingest" {
  name          = "${local.bucket_prefix}-ingest-${var.environment}"
  project       = var.project_id
  location      = var.region
  storage_class = "STANDARD"
  force_destroy = false

  versioning {
    enabled = false # No versioning su ingest: i file sono transitori
  }

  # Pulisce i file di errore dopo 60 giorni
  lifecycle_rule {
    condition {
      age            = 60
      matches_prefix = ["error/"]
    }
    action { type = "Delete" }
  }

  # Sposta i file "done" su Nearline dopo 90 giorni (archivio economico)
  lifecycle_rule {
    condition {
      age            = 90
      matches_prefix = ["llm/done/"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  uniform_bucket_level_access = true

  labels = {
    environment = var.environment
    component   = "bim-pipeline"
    bucket_role = "ingest"
  }
}

# ─── Bucket: Handoff ─────────────────────────────────────────────────────────
# Zona di scambio tra i microservizi della pipeline.
# Struttura:
#   etl/        ← JSON pronti per bim-parser/etl (output di bim-llm-merge)
#   processed/  ← JSON già caricati nel DB (output di bim-parser)
#   audit/      ← file di audit e log operativi

resource "google_storage_bucket" "handoff" {
  name          = "${local.bucket_prefix}-handoff-${var.environment}"
  project       = var.project_id
  location      = var.region
  storage_class = "STANDARD"
  force_destroy = false

  versioning {
    enabled = false
  }

  lifecycle_rule {
    condition {
      age            = 180 # 6 mesi per l'audit
      matches_prefix = ["audit/"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE" # Archivio a lungo termine, accesso raro
    }
  }

  lifecycle_rule {
    condition {
      age            = 30
      matches_prefix = ["etl/"]
    }
    action { type = "Delete" }
  }

  uniform_bucket_level_access = true

  labels = {
    environment = var.environment
    component   = "bim-pipeline"
    bucket_role = "handoff"
  }
}

resource "google_storage_bucket" "exports" {
  name                        = "${local.bucket_prefix}-exports-${var.environment}"
  project                     = var.project_id
  location                    = var.region
  storage_class               = "STANDARD"
  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  labels = {
    environment = var.environment
    component   = "revit-export"
    bucket_role = "exports"
  }
}

# ─── IAM: permessi sui bucket ────────────────────────────────────────────────
# Il parser (Cloud Run bim-parser-v1) deve poter leggere e scrivere su tutti i bucket

resource "google_storage_bucket_iam_member" "parser_staging" {
  bucket = google_storage_bucket.staging.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.sa_parser_email}"
}

resource "google_storage_bucket_iam_member" "parser_ingest" {
  bucket = google_storage_bucket.ingest.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.sa_parser_email}"
}

resource "google_storage_bucket_iam_member" "parser_handoff" {
  bucket = google_storage_bucket.handoff.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.sa_parser_email}"
}

resource "google_storage_bucket_iam_member" "etl_handoff" {
  bucket = google_storage_bucket.handoff.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.sa_etl_email}"
}

resource "google_storage_bucket_iam_member" "revit_export_writer" {
  bucket = google_storage_bucket.exports.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${var.sa_revit_export_email}"

  condition {
    title       = "RevitActualExportPrefixOnly"
    description = "Allow the Revit export Job to create objects only under exports/revit-actual/."
    expression  = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.exports.name}/objects/exports/revit-actual/\")"
  }
}

resource "google_storage_bucket_iam_member" "ocr_worker_staging_reader" {
  bucket = google_storage_bucket.staging.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${var.sa_ocr_worker_email}"
}

resource "google_storage_bucket_iam_member" "vertex_ai_staging_holding_reader" {
  bucket = google_storage_bucket.staging.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${local.vertex_ai_service_agent}"

  condition {
    title       = "VertexAiHoldingPrefixReadOnly"
    description = "Allow Vertex AI service agent to read OCR source objects only under the staging holding prefix."
    expression  = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.staging.name}/objects/holding/\")"
  }
}

resource "google_storage_bucket_iam_member" "ocr_worker_handoff_raw_response_user" {
  bucket = google_storage_bucket.handoff.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${var.sa_ocr_worker_email}"

  condition {
    title       = "OcrRawResponsePrefixOnly"
    description = "Allow OCR worker writes/metadata updates only under the raw OCR response prefix."
    expression  = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.handoff.name}/objects/${local.ocr_raw_response_object_prefix}/\")"
  }
}

# ─── GCS SA: email del service account di sistema GCS ────────────────────────
# Questo SA è creato automaticamente da GCP; non lo gestiamo noi.
# GCS lo usa internamente per pubblicare notifiche su Pub/Sub.
data "google_storage_project_service_account" "gcs_sa" {
  project = var.project_id
}

# ─── IAM: GCS SA → Publisher sul topic staging-uploads (topic-level) ─────────
resource "google_pubsub_topic_iam_member" "gcs_sa_staging_publisher" {
  project = var.project_id
  topic   = var.topic_staging_uploads_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs_sa.email_address}"
}

# ─── GCS Storage Notification ─────────────────────────────────────────────────
# Pubblica un evento su Pub/Sub ogni volta che un file viene completato in uploads/
resource "google_storage_notification" "staging_uploads" {
  bucket             = google_storage_bucket.staging.name
  payload_format     = "JSON_API_V1"
  topic              = var.topic_staging_uploads_id
  event_types        = ["OBJECT_FINALIZE"]
  object_name_prefix = "uploads/"

  depends_on = [google_pubsub_topic_iam_member.gcs_sa_staging_publisher]
}
