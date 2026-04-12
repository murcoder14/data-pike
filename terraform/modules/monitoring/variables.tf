# Monitoring Module - Input Variables

variable "project_name" {
  description = "Project name used as a prefix for all resource names"
  type        = string
  nullable    = false
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  nullable    = false
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  nullable    = false
}

variable "cloudwatch_log_kms_key_arn" {
  description = "Optional KMS key ARN for CloudWatch Logs encryption"
  type        = string
  nullable    = true
  default     = null
}
