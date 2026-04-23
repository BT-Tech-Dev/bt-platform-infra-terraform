output "connection_name" {
  description = "Connection name nel formato project:region:instance (usato da Cloud SQL Connector)"
  value       = google_sql_database_instance.main.connection_name
}

output "instance_ip" {
  description = "IP pubblico dell'istanza (per admin locale via proxy)"
  value       = google_sql_database_instance.main.public_ip_address
  sensitive   = true
}

output "instance_name" {
  value = google_sql_database_instance.main.name
}

output "database_name" {
  value = google_sql_database.main.name
}
