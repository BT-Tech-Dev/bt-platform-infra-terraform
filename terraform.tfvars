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

ocr_worker_timeout_seconds    = 900
ocr_worker_max_instance_count = 1
ocr_worker_concurrency        = 1

ocr_vertex_location = "europe-west8"
ocr_vertex_model_id = "gemini-2.5-flash"
ocr_timeout_seconds = 900
ocr_max_retries     = 3
ocr_schema_version  = "ocr-json-contract-v1"
ocr_auto_profiles   = "ferroberica_steel_ddt_v1"

revit_export_bim_parser_image           = "europe-west8-docker.pkg.dev/bt-platform-prod/bt-platform/bim-parser-v1@sha256:55c6792d89fa1354e8e73a8081bf5f852838face0e65e1b1d131074e882be280"
revit_export_ro_password_rotation_epoch = 2
