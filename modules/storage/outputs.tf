output "bucket_staging_name" {
  value = google_storage_bucket.staging.name
}
output "bucket_ingest_name" {
  value = google_storage_bucket.ingest.name
}
output "bucket_handoff_name" {
  value = google_storage_bucket.handoff.name
}
output "bucket_exports_name" {
  value = google_storage_bucket.exports.name
}
output "bucket_iot_raw_name" {
  value = google_storage_bucket.iot_raw.name
}
output "bucket_staging_url" {
  value = google_storage_bucket.staging.url
}
