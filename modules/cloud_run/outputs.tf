output "bim_parser_url" {
  description = "URL HTTPS del servizio Cloud Run bim-parser-v1"
  value       = google_cloud_run_v2_service.bim_parser.uri
}

output "bim_parser_name" {
  description = "Nome del servizio Cloud Run (usato da EventArc per il routing)"
  value       = google_cloud_run_v2_service.bim_parser.name
}

output "bucket_watcher_url" {
  description = "URL HTTPS del servizio Cloud Run bucket-watcher"
  value       = google_cloud_run_v2_service.bucket_watcher.uri
}

output "bucket_watcher_name" {
  description = "Nome del servizio Cloud Run bucket-watcher (usato da EventArc)"
  value       = google_cloud_run_v2_service.bucket_watcher.name
}

output "production_ingestion_service_name" {
  description = "Nome del servizio Cloud Run production-ingestion-service"
  value       = google_cloud_run_v2_service.production_ingestion_service.name
}

output "production_ingestion_service_url" {
  description = "URL HTTPS del servizio Cloud Run production-ingestion-service"
  value       = google_cloud_run_v2_service.production_ingestion_service.uri
}

output "production_ingestion_ocr_worker_name" {
  description = "Nome del servizio Cloud Run OCR worker"
  value       = google_cloud_run_v2_service.production_ingestion_ocr_worker.name
}

output "production_ingestion_ocr_worker_url" {
  description = "URL HTTPS del servizio Cloud Run OCR worker"
  value       = google_cloud_run_v2_service.production_ingestion_ocr_worker.uri
}

output "iot_ingestion_service_name" {
  description = "Nome del servizio Cloud Run IoT ingestion"
  value       = google_cloud_run_v2_service.iot_ingestion_service.name
}

output "iot_ingestion_service_url" {
  description = "URL HTTPS del servizio Cloud Run IoT ingestion"
  value       = google_cloud_run_v2_service.iot_ingestion_service.uri
}
