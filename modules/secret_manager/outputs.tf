output "secret_db_password_name" {
  description = "Nome del segreto con la password DB (usato nelle env var Cloud Run)"
  value       = google_secret_manager_secret.db_password.secret_id
}

output "secret_db_password_ro_name" {
  value = google_secret_manager_secret.db_password_ro.secret_id
}

output "secret_llm_api_key_name" {
  value = google_secret_manager_secret.llm_api_key.secret_id
}

output "secret_github_token_name" {
  value = google_secret_manager_secret.cloudbuild_github_token.secret_id
}
