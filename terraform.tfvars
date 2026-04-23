# =============================================================================
# terraform.tfvars — Valori concreti per l'ambiente bt-platform-prod
#
# Questo file NON contiene segreti (password, API key).
# I segreti vivono in Secret Manager e vengono inseriti manualmente.
# =============================================================================

project_id   = "bt-platform-prod"
region       = "europe-west8"
environment  = "prod"
org_id       = "862731545925"

db_instance_name = "bt-platform-pg-prod"
db_name          = "db_bt_platform"
db_version       = "POSTGRES_15"
db_tier          = "db-g1-small"
