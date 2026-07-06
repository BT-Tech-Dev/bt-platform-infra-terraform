output "ocr_extraction_queue_name" {
  description = "Nome della queue Cloud Tasks OCR."
  value       = google_cloud_tasks_queue.ocr_extraction.name
}

output "ocr_extraction_queue_id" {
  description = "ID completo della queue Cloud Tasks OCR."
  value       = google_cloud_tasks_queue.ocr_extraction.id
}

output "ocr_extraction_queue_location" {
  description = "Location della queue Cloud Tasks OCR."
  value       = google_cloud_tasks_queue.ocr_extraction.location
}
