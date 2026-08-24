resource "google_cloud_run_v2_job" "recovery" {
  name     = "ms05-ingestion-recovery-${var.environment}"
  location = var.region
  project  = var.project_id

  template {
    task_count  = 1
    parallelism = 1
    template {
      service_account = var.service_account_email
      max_retries     = 1
      timeout         = "600s"
      volumes {
        name = "cloudsql"
        cloud_sql_instance {
          instances = [var.db_connection_name]
        }
      }
      containers {
        image   = var.image
        command = ["python"]
        args    = ["/app/scripts/ingestion_recovery_job.py"]
        resources {
          limits = { cpu = "1", memory = "512Mi" }
        }
        env {
          name  = "GCP_PROJECT_ID"
          value = var.tasks_project_id
        }
        env {
          name  = "STAGING_BUCKET"
          value = var.staging_bucket_name
        }
        env {
          name  = "INSTANCE_CONNECTION_NAME"
          value = var.db_connection_name
        }
        env {
          name  = "DB_USER"
          value = "bt_app"
        }
        env {
          name  = "DB_NAME"
          value = var.db_name
        }
        env {
          name  = "LOG_LEVEL"
          value = "INFO"
        }
        env {
          name  = "MS05_TASKS_PROJECT_ID"
          value = var.tasks_project_id
        }
        env {
          name  = "MS05_TASKS_LOCATION"
          value = var.tasks_location
        }
        env {
          name  = "MS05_TASKS_QUEUE"
          value = var.tasks_queue
        }
        env {
          name  = "MS05_TASKS_SERVICE_ACCOUNT_EMAIL"
          value = var.tasks_oidc_service_account_email
        }
        env {
          name  = "MS05_WORKER_TARGET_URL"
          value = var.worker_target_url
        }
        env {
          name  = "MS05_TASKS_DISPATCH_DEADLINE_SECONDS"
          value = "360"
        }
        env {
          name = "DB_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = var.db_password_secret_name
              version = "latest"
            }
          }
        }
        volume_mounts {
          name       = "cloudsql"
          mount_path = "/cloudsql"
        }
      }
    }
  }
  labels = { environment = var.environment, service = "ms05-ingestion-recovery" }
}

resource "google_cloud_run_v2_job_iam_member" "scheduler_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.recovery.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.scheduler_service_account_email}"
}
