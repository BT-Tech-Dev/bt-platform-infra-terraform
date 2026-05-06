# =============================================================================
# modules/pubsub/main.tf — Topic Pub/Sub per la pipeline BIM e eventi SAL
#
# Pub/Sub è il "sistema nervoso" della piattaforma: i servizi non si chiamano
# direttamente ma pubblicano eventi su topic. Gli altri servizi ascoltano
# e reagiscono. Questo disaccoppia i servizi e aumenta la resilienza.
#
# Pattern usato (stesso del vecchio progetto bt-bim):
#   GCS bucket → notifica GCS → Pub/Sub topic → EventArc trigger → Cloud Run
#
# Topic creati:
#   gcs-staging-uploads     → file caricati nel bucket staging
#   gcs-ingest-landing      → file spostati in ingest/landing/incoming/
#   gcs-ingest-llm          → file pronti per elaborazione LLM
#   gcs-handoff-etl         → file pronti per ETL/parser
#   sal-events              → eventi SAL rilasciati (per notifiche e proiezioni)
#   nc-events               → eventi non conformità (per alert e blocchi SAL)
# =============================================================================

locals {
  topic_prefix = "bt-platform"
}

# ─── Pipeline BIM: topic GCS ─────────────────────────────────────────────────

# Passo 1: file caricato nel bucket staging (dal plugin Revit)
resource "google_pubsub_topic" "gcs_staging_uploads" {
  name    = "${local.topic_prefix}-gcs-staging-uploads-${var.environment}"
  project = var.project_id

  labels = {
    environment = var.environment
    pipeline    = "bim-ingest"
    step        = "1-staging"
  }

  # Messaggi scadono dopo 7 giorni se non consumati
  message_retention_duration = "604800s"  # 7 giorni in secondi
}

# Passo 2: file nella zona di landing ingest
resource "google_pubsub_topic" "gcs_ingest_landing" {
  name    = "${local.topic_prefix}-gcs-ingest-landing-${var.environment}"
  project = var.project_id

  labels = {
    environment = var.environment
    pipeline    = "bim-ingest"
    step        = "2-landing"
  }

  message_retention_duration = "604800s"
}

# Passo 3: file pronti per LLM/passthrough
resource "google_pubsub_topic" "gcs_ingest_llm" {
  name    = "${local.topic_prefix}-gcs-ingest-llm-${var.environment}"
  project = var.project_id

  labels = {
    environment = var.environment
    pipeline    = "bim-ingest"
    step        = "3-llm"
  }

  message_retention_duration = "604800s"
}

# Passo 4: file pronti per l'ETL/parser
resource "google_pubsub_topic" "gcs_handoff_etl" {
  name    = "${local.topic_prefix}-gcs-handoff-etl-${var.environment}"
  project = var.project_id

  labels = {
    environment = var.environment
    pipeline    = "bim-ingest"
    step        = "4-etl"
  }

  message_retention_duration = "604800s"
}

# ─── Topic eventi business ────────────────────────────────────────────────────

# Evento SAL rilasciato dal SAL Engine (MS-06)
# Consumato da: MS-09 Read Projector, MS-10 Notification Service
resource "google_pubsub_topic" "sal_events" {
  name    = "${local.topic_prefix}-sal-events-${var.environment}"
  project = var.project_id

  labels = {
    environment = var.environment
    domain      = "sal-engine"
  }

  message_retention_duration = "2592000s"  # 30 giorni (eventi SAL importanti)
}

# Evento non conformità (NCR aperta, chiusa, escalation)
resource "google_pubsub_topic" "nc_events" {
  name    = "${local.topic_prefix}-nc-events-${var.environment}"
  project = var.project_id

  labels = {
    environment = var.environment
    domain      = "quality"
  }

  message_retention_duration = "2592000s"
}

# =============================================================================
# Topic GCS per doc_type specifici (pubblicati da bucket-watcher)
#
# Il bucket-watcher riceve l'evento GCS raw e lo smista su questi topic
# in base al doc_type nel percorso: uploads/{project_code}/{doc_type}/...
# Ogni topic alimenta il parser specializzato per quel tipo di documento.
# =============================================================================

resource "google_pubsub_topic" "gcs_bim" {
  name    = "${local.topic_prefix}-gcs-bim-${var.environment}"
  project = var.project_id

  labels = {
    environment = var.environment
    pipeline    = "bim-ingest"
    doc_type    = "bim"
  }

  message_retention_duration = "604800s"
}

resource "google_pubsub_topic" "gcs_production" {
  name    = "${local.topic_prefix}-gcs-production-${var.environment}"
  project = var.project_id

  labels = {
    environment = var.environment
    pipeline    = "production-ingest"
    doc_type    = "production"
  }

  message_retention_duration = "604800s"
}

resource "google_pubsub_topic" "gcs_boq" {
  name    = "${local.topic_prefix}-gcs-boq-${var.environment}"
  project = var.project_id

  labels = {
    environment = var.environment
    pipeline    = "boq-ingest"
    doc_type    = "boq"
  }

  message_retention_duration = "604800s"
}

resource "google_pubsub_topic" "gcs_gantt" {
  name    = "${local.topic_prefix}-gcs-gantt-${var.environment}"
  project = var.project_id

  labels = {
    environment = var.environment
    pipeline    = "gantt-ingest"
    doc_type    = "gantt"
  }

  message_retention_duration = "604800s"
}

# ─── Dead Letter Topic ────────────────────────────────────────────────────────
# Topic speciale per i messaggi che falliscono dopo N tentativi.
# Importante per il debug: invece di perdere i messaggi, finiscono qui.
resource "google_pubsub_topic" "dead_letter" {
  name    = "${local.topic_prefix}-dead-letter-${var.environment}"
  project = var.project_id

  labels = {
    environment = var.environment
    type        = "dead-letter"
  }

  message_retention_duration = "2592000s"  # 30 giorni per analisi errori
}

# ─── Subscription per il BIM Parser ─────────────────────────────────────────
# EventArc gestisce le proprie subscription automaticamente,
# ma questa è utile per debug e replay manuale dei messaggi.
resource "google_pubsub_subscription" "staging_uploads_sub" {
  name    = "${local.topic_prefix}-staging-uploads-sub-${var.environment}"
  topic   = google_pubsub_topic.gcs_staging_uploads.name
  project = var.project_id

  # Scadenza messaggio non consegnato: riprova fino a 10 minuti
  ack_deadline_seconds = 600

  # Prova massimo 5 volte prima di mandare al dead letter topic
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }

  # Mantieni i messaggi non consegnati per 7 giorni
  message_retention_duration = "604800s"
  retain_acked_messages      = false

  labels = {
    environment = var.environment
    service     = "bim-parser"
  }
}
