# =============================================================================
# terraform.tfvars — Valori concreti per l'ambiente bt-platform-prod
#
# Questo file NON contiene segreti (password, API key).
# I segreti vivono in Secret Manager e vengono inseriti manualmente.
# =============================================================================

project_id  = "bt-platform-prod"
region      = "europe-west8"
environment = "prod"
org_id      = "862731545925"

db_instance_name = "bt-platform-pg-prod"
db_name          = "db_bt_platform"
db_version       = "POSTGRES_15"
db_tier          = "db-g1-small"

enable_db_init = false

enable_debug_pubsub_subscriptions = false

ocr_tasks_location                  = "europe-west6"
ocr_tasks_queue_name                = "bt-platform-ocr-extraction-prod"
ocr_tasks_max_concurrent_dispatches = 1
ocr_tasks_max_dispatches_per_second = 0.05
ocr_tasks_max_attempts              = 3
ocr_tasks_dispatch_deadline_seconds = 900

ms05_tasks_location                        = "europe-west6"
ms05_tasks_queue_name                      = "bt-platform-ms05-ingest-prod"
ms05_tasks_max_concurrent_dispatches       = 2
ms05_tasks_max_dispatches_per_second       = 1
ms05_tasks_max_attempts                    = 5
ms05_tasks_dispatch_deadline_seconds       = 360
ms05_worker_target_url                     = "https://production-ingestion-service-qspj7kbdla-oc.a.run.app/tasks/ingest"
bucket_watcher_production_dispatch_backend = "cloud_tasks"

ocr_worker_timeout_seconds    = 900
ocr_worker_max_instance_count = 1
ocr_worker_concurrency        = 1

ocr_vertex_location        = "europe-west8"
ocr_vertex_model_id        = "gemini-2.5-flash"
ocr_timeout_seconds        = 900
ocr_max_retries            = 3
ocr_schema_version         = "ocr-json-contract-v1"
ocr_auto_profiles          = "ferroberica_steel_ddt_v1"
evidence_link_handoff_mode = "required"

revit_export_bim_parser_image           = "europe-west8-docker.pkg.dev/bt-platform-prod/bt-platform/bim-parser-v1@sha256:bcd8b6e525abba983ee9df3af93d2d9dc145cd540e9c67cda6ba0027c8945215"
revit_export_ro_password_rotation_epoch = 2
iot_ingestion_image                     = "europe-west8-docker.pkg.dev/bt-platform-prod/bt-platform/iot-ingestion-service@sha256:8869a465df7e2f457545f793da943351dd094841d9b183b63a9087ef621d1b15"
ms05_recovery_image                     = "europe-west8-docker.pkg.dev/bt-platform-prod/bt-platform/production-ingestion-service@sha256:1cc1254e66f2b80b44321d2dbb37451d13c245ecdff5bef6ab2f97e36bc51b99"
