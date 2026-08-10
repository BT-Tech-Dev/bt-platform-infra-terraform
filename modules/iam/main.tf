# =============================================================================
# modules/iam/main.tf — Service Accounts e ruoli IAM
#
# Un "Service Account" (SA) è come un'identità digitale per un servizio:
# invece di un utente umano che fa login, è un servizio (Cloud Run, Cloud Build)
# che si autentica con GCP usando questa identità. Ogni SA ha solo i permessi
# minimi necessari per fare il suo lavoro (principio del least privilege).
#
# Service accounts creati:
#   sa-bt-parser-prod    → Cloud Run bim-parser-v1 (legge/scrive GCS + SQL)
#   sa-bt-etl-prod       → ETL jobs (legge/scrive GCS + SQL)
#   sa-bt-eventarc-prod  → EventArc (invoca Cloud Run quando arriva un evento)
#   sa-bt-cloudbuild-prod → Cloud Build (builda Docker + deploya su Cloud Run)
# =============================================================================

# ─── Service Account: BIM Parser ─────────────────────────────────────────────
# Usato dal Cloud Run bim-parser-v1 per leggere i JSON da GCS e scrivere in PostgreSQL

resource "google_service_account" "parser" {
  account_id   = "sa-bt-parser-${var.environment}"
  display_name = "BT BIM Parser — Cloud Run bim-parser-v1"
  description  = "Usato da Cloud Run bim-parser-v1: legge staging/ingest GCS, scrive su PostgreSQL"
  project      = var.project_id
}

# Permesso per connettersi a Cloud SQL via Cloud SQL Connector
resource "google_project_iam_member" "parser_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.parser.email}"
}

# Permesso per leggere e scrivere oggetti su GCS
resource "google_project_iam_member" "parser_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.parser.email}"
}

# Permesso per leggere i segreti da Secret Manager (es. db_password)
resource "google_project_iam_member" "parser_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.parser.email}"
}

# Permesso per pubblicare messaggi sui topic Pub/Sub (bim, production, boq, gantt)
resource "google_project_iam_member" "parser_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.parser.email}"
}

# Permette all'operatore autorizzato di impersonare il parser SA solo per
# amministrazione locale controllata e canary MS-05 OCR.
resource "google_service_account_iam_member" "admin_parser_token_creator" {
  service_account_id = google_service_account.parser.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:admin@buildtrust.it"
}

# ─── Service Account: OCR worker runtime ─────────────────────────────────────
# Runtime privato del worker OCR. Ha accesso a Cloud SQL, GCS artifact/source e
# Vertex AI, ma non può accodare task.

resource "google_service_account" "ocr_worker" {
  account_id   = "sa-bt-ocr-worker-${var.environment}"
  display_name = "BT MS-05 OCR Worker"
  description  = "Runtime Cloud Run OCR worker: esegue estrazioni Vertex AI e persiste risultati OCR"
  project      = var.project_id
}

resource "google_project_iam_member" "ocr_worker_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.ocr_worker.email}"
}

resource "google_project_iam_member" "ocr_worker_vertex_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.ocr_worker.email}"
}

# ─── Service Account: Cloud Tasks OIDC caller ────────────────────────────────
# Identità usata solo come OIDC token subject per invocare il worker OCR.

resource "google_service_account" "ocr_tasks_oidc" {
  account_id   = "sa-bt-ocr-tasks-${var.environment}"
  display_name = "BT MS-05 OCR Cloud Tasks OIDC"
  description  = "OIDC caller identity for Cloud Tasks -> OCR worker"
  project      = var.project_id
}

# ─── Service Account: ETL ────────────────────────────────────────────────────
# Usato per i job ETL batch (es. import dati Grigolin, import BOQ)

resource "google_service_account" "etl" {
  account_id   = "sa-bt-etl-${var.environment}"
  display_name = "BT ETL — Job batch di importazione dati"
  description  = "Usato dai job ETL batch: legge GCS, scrive su PostgreSQL, legge segreti"
  project      = var.project_id
}

resource "google_project_iam_member" "etl_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.etl.email}"
}

resource "google_project_iam_member" "etl_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.etl.email}"
}

resource "google_project_iam_member" "etl_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.etl.email}"
}

# ─── Service Account: EventArc ───────────────────────────────────────────────
# EventArc usa questo SA per invocare Cloud Run quando scatta un trigger.
# Senza questo, EventArc non avrebbe il permesso di "chiamare" il Cloud Run.

resource "google_service_account" "eventarc" {
  account_id   = "sa-bt-eventarc-${var.environment}"
  display_name = "BT EventArc — Trigger GCS→Pub/Sub→CloudRun"
  description  = "Usato dai trigger EventArc per invocare Cloud Run e pubblicare su Pub/Sub"
  project      = var.project_id
}

# Permesso EventArc per ricevere eventi
resource "google_project_iam_member" "eventarc_event_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.eventarc.email}"
}

# Permesso per pubblicare messaggi su Pub/Sub
resource "google_project_iam_member" "eventarc_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.eventarc.email}"
}

# ─── Service Account: Cloud Build ────────────────────────────────────────────
# Cloud Build lo usa per: buildare le immagini Docker, pusharle su Artifact
# Registry, e deployare i nuovi container su Cloud Run.

resource "google_service_account" "cloudbuild" {
  account_id   = "sa-bt-cloudbuild-${var.environment}"
  display_name = "BT Cloud Build — CI/CD Docker build e deploy"
  description  = "Usato da Cloud Build per buildare immagini Docker e deployare su Cloud Run"
  project      = var.project_id
}

# Permesso per pushare immagini Docker su Artifact Registry
resource "google_project_iam_member" "cloudbuild_ar_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Permesso per deployare nuove versioni su Cloud Run
resource "google_project_iam_member" "cloudbuild_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Permesso per scrivere i log di build su Cloud Logging
resource "google_project_iam_member" "cloudbuild_logs_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Permesso per "impersonare" altri service account durante il deploy
# (Cloud Build deve poter deployare Cloud Run con il SA del parser)
resource "google_project_iam_member" "cloudbuild_sa_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# ─── Service Account GCS: email per IAM topic-level ─────────────────────────
# Il SA GCS di sistema è creato automaticamente da GCP.
# Il binding roles/pubsub.publisher è assegnato a LIVELLO DI TOPIC (non di progetto)
# nel modulo eventarc/main.tf, co-locato con google_storage_notification.
# Qui esportiamo solo l'email via output per eventuali usi futuri.

data "google_project" "current" {
  project_id = var.project_id
}

locals {
  gcs_service_account       = "service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com"
  cloud_tasks_service_agent = "service-${data.google_project.current.number}@gcp-sa-cloudtasks.iam.gserviceaccount.com"
  # Dal 2024, GCP usa il Compute Engine default SA per i nuovi progetti (non il vecchio cloudbuild SA)
  compute_default_sa = "${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}

resource "google_service_account_iam_member" "cloud_tasks_oidc_token_creator" {
  service_account_id = google_service_account.ocr_tasks_oidc.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${local.cloud_tasks_service_agent}"
}

resource "google_service_account" "revit_export" {
  account_id   = "sa-bt-revit-export-${var.environment}"
  display_name = "BT Revit Actual Export"
  description  = "Cloud Run Job runtime for read-only Revit actual exports"
  project      = var.project_id
}

resource "google_service_account" "iot_ingestion_runtime" {
  account_id   = "iot-ingestion-runtime"
  display_name = "BT IoT ingestion runtime"
  description  = "Cloud Run runtime for authenticated UG65 IoT measurement ingestion"
  project      = var.project_id
}

resource "google_project_iam_member" "iot_ingestion_runtime_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.iot_ingestion_runtime.email}"
}

resource "google_service_account" "ug65_balocco2_iot_invoker" {
  account_id   = "ug65-balocco2-iot-invoker"
  display_name = "UG65 Balocco2 IoT invoker"
  description  = "OIDC caller for iot-ingestion-service only"
  project      = var.project_id
}

resource "google_project_iam_member" "revit_export_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.revit_export.email}"
}

resource "google_service_account_iam_member" "parser_ocr_tasks_oidc_sa_user" {
  service_account_id = google_service_account.ocr_tasks_oidc.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.parser.email}"
}

# ─── Compute Engine default SA: permessi Cloud Build ─────────────────────────
# Dal 2024, Cloud Build usa il Compute Engine default SA per eseguire i job.
# Senza questi ruoli, "gcloud builds submit" fallisce con errore 403 storage.
#
# roles/cloudbuild.builds.builder → permessi minimi per eseguire un build:
#   storage.objects.get/create/list (legge il sorgente, scrive i log e le immagini)
#
# roles/secretmanager.secretAccessor → permesso per leggere i segreti durante il build
#   (es. la password postgres in cloudbuild-init-db.yaml)
#
# roles/cloudsql.client → permesso per usare cloud-sql-proxy durante il build
#   (necessario per connettersi a Cloud SQL in cloudbuild-init-db.yaml)

resource "google_project_iam_member" "compute_sa_cloudbuild_builder" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${local.compute_default_sa}"
}

resource "google_project_iam_member" "compute_sa_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${local.compute_default_sa}"
}

resource "google_project_iam_member" "compute_sa_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${local.compute_default_sa}"
}
