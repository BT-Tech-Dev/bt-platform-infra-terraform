variable "project_id" { type = string }
variable "region" { type = string }
variable "environment" { type = string }
variable "enable_debug_pubsub_subscriptions" {
  description = "Abilita subscription Pub/Sub manuali per debug/replay."
  type        = bool
  default     = false
}
