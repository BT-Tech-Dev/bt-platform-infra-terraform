# =============================================================================
# modules/cloud_sql/main.tf — Istanza PostgreSQL multi-tenant
#
# Crea:
#   - Istanza Cloud SQL PostgreSQL 15 (bt-platform-pg-prod)
#   - Database principale (db_bt_platform)
#   - Utente applicativo (bt_app) — legge/scrive su tutti gli schemi
#   - Utente read-only (bt_readonly) — solo lettura per analytics/Hasura
#
# Gli schemi SQL (bim, process, boq, ecc.) NON vengono creati qui:
# Terraform non può eseguire DDL SQL durante plan/apply in modo sicuro.
# Vanno creati con: make init-db  (che esegue scripts/init_db.sh)
#
# Connessione da Cloud Run:
#   Usa il Cloud SQL Connector (pg8000/asyncpg), NON un IP diretto.
#   La connection string è: bt-platform-prod:europe-west8:bt-platform-pg-prod
# =============================================================================

resource "google_sql_database_instance" "main" {
  name             = var.db_instance_name
  project          = var.project_id
  region           = var.region
  database_version = var.db_version

  # deletion_protection = true impedisce la cancellazione accidentale via Terraform.
  # Per distruggere l'istanza bisogna prima impostarlo a false e fare apply.
  deletion_protection = true

  settings {
    tier = var.db_tier

    # ─── Availability ─────────────────────────────────────────────────────
    # ZONAL = una sola zona, più economico ma meno resiliente
    # REGIONAL = replica automatica in una seconda zona (consigliato per prod)
    # Per ora ZONAL (si cambia in 1 clic senza downtime significativo)
    availability_type = "ZONAL"

    # ─── Disco ────────────────────────────────────────────────────────────
    disk_autoresize       = true     # GCP aumenta il disco automaticamente se si riempie
    disk_autoresize_limit = 100      # Limite max 100 GB (evita costi incontrollati)
    disk_size             = 20       # GB iniziali
    disk_type             = "PD_SSD" # SSD per performance migliori su query JSON/JSONB

    # ─── Backup ───────────────────────────────────────────────────────────
    backup_configuration {
      enabled                        = true
      start_time                     = "03:00" # Backup alle 3:00 AM (basso traffico)
      location                       = "eu"    # Backup nella region EU
      point_in_time_recovery_enabled = true    # Permette ripristino a qualsiasi momento (PITR)
      transaction_log_retention_days = 7       # Mantieni 7 giorni di WAL log
      backup_retention_settings {
        retained_backups = 14 # Mantieni gli ultimi 14 backup giornalieri
      }
    }

    # ─── Manutenzione ─────────────────────────────────────────────────────
    maintenance_window {
      day          = 7 # Domenica (meno traffico)
      hour         = 4 # Alle 4:00 AM
      update_track = "stable"
    }

    # ─── Configurazione PostgreSQL ─────────────────────────────────────────
    database_flags {
      # Abilita il log delle query lente (> 1 secondo) per debugging performance
      name  = "log_min_duration_statement"
      value = "1000" # millisecondi
    }

    database_flags {
      # Abilita il log delle connessioni per audit di sicurezza
      name  = "log_connections"
      value = "on"
    }

    database_flags {
      # Forza SSL per tutte le connessioni
      name  = "ssl_min_protocol_version"
      value = "TLSv1.2"
    }

    # ─── IP Configuration ─────────────────────────────────────────────────
    # Cloud Run si connette via Cloud SQL Connector (API proxy), non IP diretto.
    # L'IP pubblico serve solo per amministrazione locale via Cloud SQL Proxy.
    ip_configuration {
      ipv4_enabled = true             # IP pubblico abilitato per admin locale
      ssl_mode     = "ENCRYPTED_ONLY" # SSL obbligatorio

      # NESSUNA rete autorizzata: nessuno può connettersi direttamente all'IP.
      # La connessione è solo via Cloud SQL Connector API (Cloud Run) o
      # Cloud SQL Auth Proxy locale (admin).
    }

    insights_config {
      query_insights_enabled  = true # Raccoglie statistiche sulle query (utile per ottimizzazione)
      query_string_length     = 1024
      record_application_tags = false
      record_client_address   = false
    }

    user_labels = {
      environment = var.environment
      component   = "database"
    }
  }
}

# ─── Database ────────────────────────────────────────────────────────────────
resource "google_sql_database" "main" {
  name      = var.db_name
  instance  = google_sql_database_instance.main.name
  project   = var.project_id
  charset   = "UTF8"
  collation = "en_US.UTF8"
}

# ─── Utente applicativo ───────────────────────────────────────────────────────
# bt_app: utente con accesso completo agli schemi dell'applicazione.
# La password viene generata casualmente qui ma NON salvata in Terraform state.
# IMPORTANTE: dopo terraform apply, bisogna impostare la password manualmente
# e salvarla in Secret Manager (bt-platform-db-password-prod).
#
# Procedura:
#   1. Genera password forte: openssl rand -base64 32
#   2. Setta in Cloud SQL: gcloud sql users set-password bt_app --instance=bt-platform-pg-prod --password=...
#   3. Salva in Secret Manager: gcloud secrets versions add bt-platform-db-password-prod --data-file=...

resource "google_sql_user" "app_user" {
  name     = "bt_app"
  instance = google_sql_database_instance.main.name
  project  = var.project_id

  # La password viene gestita fuori da Terraform (Secret Manager).
  # Questo campo è richiesto dal provider ma il valore reale viene
  # impostato manualmente dopo il deploy.
  password = "CHANGE_ME_VIA_SECRET_MANAGER"

  lifecycle {
    # Non aggiornare la password se cambia nel tfstate (la gestiamo fuori Terraform)
    ignore_changes = [password]
  }
}

# ─── Utente read-only ─────────────────────────────────────────────────────────
# bt_readonly: permette solo SELECT. Usato da Hasura (read side CQRS) e analytics.
resource "google_sql_user" "readonly_user" {
  name     = "bt_readonly"
  instance = google_sql_database_instance.main.name
  project  = var.project_id
  password = "CHANGE_ME_VIA_SECRET_MANAGER"

  lifecycle {
    ignore_changes = [password]
  }
}

resource "google_sql_user" "revit_export_ro" {
  name                = "revit_export_ro"
  instance            = google_sql_database_instance.main.name
  project             = var.project_id
  password_wo         = var.revit_export_ro_password
  password_wo_version = var.revit_export_ro_password_rotation_epoch
}

# ─── IAM: il SA ETL può connettersi via Cloud SQL Connector ──────────────────
resource "google_project_iam_member" "sql_client_etl" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${var.sa_etl_email}"
}
