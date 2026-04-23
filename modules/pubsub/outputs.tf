output "topic_staging_uploads_id" {
  description = "ID completo del topic per upload staging (usato da EventArc e GCS notification)"
  value       = google_pubsub_topic.gcs_staging_uploads.id
}
output "topic_ingest_landing_id" {
  value = google_pubsub_topic.gcs_ingest_landing.id
}
output "topic_ingest_llm_id" {
  value = google_pubsub_topic.gcs_ingest_llm.id
}
output "topic_handoff_etl_id" {
  value = google_pubsub_topic.gcs_handoff_etl.id
}
output "topic_sal_events_id" {
  value = google_pubsub_topic.sal_events.id
}
output "topic_nc_events_id" {
  value = google_pubsub_topic.nc_events.id
}
output "topic_dead_letter_id" {
  value = google_pubsub_topic.dead_letter.id
}

# Mappa nome → ID per output aggregato nel root module
output "topic_ids" {
  description = "Mappa di tutti i topic: nome_breve → ID completo"
  value = {
    staging_uploads = google_pubsub_topic.gcs_staging_uploads.id
    ingest_landing  = google_pubsub_topic.gcs_ingest_landing.id
    ingest_llm      = google_pubsub_topic.gcs_ingest_llm.id
    handoff_etl     = google_pubsub_topic.gcs_handoff_etl.id
    sal_events      = google_pubsub_topic.sal_events.id
    nc_events       = google_pubsub_topic.nc_events.id
    dead_letter     = google_pubsub_topic.dead_letter.id
  }
}
