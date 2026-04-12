# Networking Module - Input Variables

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

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  nullable    = false

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be a valid CIDR block."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  nullable    = false
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days for VPC flow logs"
  type        = number
  nullable    = false
}

variable "cloudwatch_log_kms_key_arn" {
  description = "Optional KMS key ARN for CloudWatch Logs encryption"
  type        = string
  nullable    = true
  default     = null
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC flow logs"
  type        = bool
  nullable    = false
}
