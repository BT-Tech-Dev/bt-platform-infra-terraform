output "queue_name" {
  description = "Nome della queue Cloud Tasks."
  value       = google_cloud_tasks_queue.queue.name
}

output "queue_id" {
  description = "ID completo della queue Cloud Tasks."
  value       = google_cloud_tasks_queue.queue.id
}

output "queue_location" {
  description = "Location della queue Cloud Tasks."
  value       = google_cloud_tasks_queue.queue.location
}
