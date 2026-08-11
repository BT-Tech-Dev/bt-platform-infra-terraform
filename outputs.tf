# =============================================================================
# outputs.tf — Valori di output esposti dopo terraform apply
#
# Questi valori vengono stampati a terminale e sono usabili da altri moduli
# o da script di configurazione (es. init_db.sh).
# =============================================================================

# ─── Cloud SQL ───────────────────────────────────────────────────────────────

output "db_connection_name" {
  description = "Connection name Cloud SQL nel formato project:region:instance. Usato dai Cloud Run per connettersi via Cloud SQL Connector."
  value       = module.cloud_sql.connection_name
}

output "db_instance_ip" {
  description = "IP pubblico dell'istanza Cloud SQL (per debug/admin locale via proxy)"
  value       = module.cloud_sql.instance_ip
  sensitive   = true # Nascosto nel log CI/CD per sicurezza
}

# ─── Storage ─────────────────────────────────────────────────────────────────

output "bucket_staging_name" {
  description = "Nome bucket GCS staging (dove il plugin Revit carica i JSON)"
  value       = module.storage.bucket_staging_name
}

output "bucket_ingest_name" {
  description = "Nome bucket GCS ingest (pipeline di lavorazione)"
  value       = module.storage.bucket_ingest_name
}

output "bucket_handoff_name" {
  description = "Nome bucket GCS handoff (passaggio tra servizi della pipeline)"
  value       = module.storage.bucket_handoff_name
}

# ─── IAM — Service Accounts ──────────────────────────────────────────────────

output "sa_parser_email" {
  description = "Email service account del BIM parser (usato dal Cloud Run bim-parser-v1)"
  value       = module.iam.sa_parser_email
}

output "sa_eventarc_email" {
  description = "Email service account EventArc (usato per invocare Cloud Run dai trigger)"
  value       = module.iam.sa_eventarc_email
}

output "sa_cloudbuild_email" {
  description = "Email service account Cloud Build (CI/CD: build Docker + deploy Cloud Run)"
  value       = module.iam.sa_cloudbuild_email
}

output "sa_ocr_worker_email" {
  description = "Email service account dedicato all'OCR worker"
  value       = module.iam.sa_ocr_worker_email
}

output "sa_ocr_tasks_oidc_email" {
  description = "Email service account OIDC usato da Cloud Tasks per invocare l'OCR worker"
  value       = module.iam.sa_ocr_tasks_oidc_email
}

# ─── Artifact Registry ───────────────────────────────────────────────────────

output "artifact_registry_url" {
  description = "URL base Artifact Registry per pushare le immagini Docker: REGION-docker.pkg.dev/PROJECT/REPO"
  value       = module.artifact_registry.registry_url
}

# ─── Cloud Run ───────────────────────────────────────────────────────────────

output "bim_parser_url" {
  description = "URL del Cloud Run bim-parser-v1 (placeholder, sarà il primo servizio della pipeline)"
  value       = module.cloud_run.bim_parser_url
}

# ─── Pub/Sub ─────────────────────────────────────────────────────────────────

output "pubsub_topics" {
  description = "Mappa nome → ID di tutti i topic Pub/Sub creati"
  value       = module.pubsub.topic_ids
}
output "production_ingestion_ocr_worker_url" {
  description = "URL del Cloud Run privato production-ingestion-ocr-worker"
  value       = module.cloud_run.production_ingestion_ocr_worker_url
}

output "revit_actual_export_job_name" {
  description = "Nome del Cloud Run Job per l'export Revit actual Balocco2"
  value       = module.revit_export_job.name
}

output "revit_actual_export_bucket_name" {
  description = "Bucket privato degli export Revit actual"
  value       = module.storage.bucket_exports_name
}

output "production_ingestion_ocr_worker_name" {
  description = "Nome del Cloud Run privato production-ingestion-ocr-worker"
  value       = module.cloud_run.production_ingestion_ocr_worker_name
}

output "ocr_extraction_queue_name" {
  description = "Nome della queue Cloud Tasks OCR"
  value       = module.cloud_tasks.ocr_extraction_queue_name
}

output "ocr_extraction_queue_location" {
  description = "Location della queue Cloud Tasks OCR"
  value       = module.cloud_tasks.ocr_extraction_queue_location
}

output "iot_ingestion_service_name" {
  description = "Nome del Cloud Run service IoT ingestion"
  value       = module.cloud_run.iot_ingestion_service_name
}

output "iot_ingestion_service_url" {
  description = "URL HTTPS del Cloud Run service IoT ingestion"
  value       = module.cloud_run.iot_ingestion_service_url
}

output "iot_raw_bucket_name" {
  description = "Bucket GCS raw immutabile per payload IoT"
  value       = module.storage.bucket_iot_raw_name
}

output "iot_api_gateway_url" {
  description = "URL HTTPS pubblico del gateway IoT per UG65"
  value       = "https://${google_api_gateway_gateway.iot_ingestion.default_hostname}"
}

output "iot_api_gateway_name" {
  description = "Nome della gateway API IoT"
  value       = google_api_gateway_gateway.iot_ingestion.name
}

output "iot_api_managed_service_name" {
  description = "Managed Service name dell'API IoT, usato dalla restrizione della API key"
  value       = google_api_gateway_api.iot_ingestion.managed_service
}
