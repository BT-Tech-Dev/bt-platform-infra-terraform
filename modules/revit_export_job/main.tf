resource "google_cloud_run_v2_job" "revit_actual_balocco2_zone1_piles" {
  name     = "revit-actual-balocco2-zone1-piles"
  location = var.region
  project  = var.project_id

  template {
    task_count  = 1
    parallelism = 1

    template {
      service_account = var.service_account_email
      max_retries     = 1
      timeout         = "900s"

      volumes {
        name = "cloudsql"
        cloud_sql_instance {
          instances = [var.db_connection_name]
        }
      }

      containers {
        image   = var.image
        command = ["python"]
        args = [
          "/app/scripts/export_revit_actual_job.py",
          "--project-code", "balocco2",
          "--profile", "balocco2_zone1_pile_installed_v1",
          "--target-revit-file", "0572-IDG-PLOG-L00-A-STR-3D-A-converted.rvt",
          "--output-gcs-prefix", "gs://${var.export_bucket_name}/exports/revit-actual",
        ]

        resources {
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
        }

        env {
          name  = "REVIT_ACTUAL_EXPORT_OUTPUT_PREFIX"
          value = "gs://${var.export_bucket_name}/exports/revit-actual/"
        }
        env {
          name  = "INSTANCE_CONNECTION_NAME"
          value = var.db_connection_name
        }
        env {
          name  = "DB_USER"
          value = var.db_user
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

  labels = {
    environment = var.environment
    service     = "revit-actual-export"
    project     = "balocco2"
  }
}
