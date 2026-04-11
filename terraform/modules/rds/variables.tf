# RDS Module - Input Variables

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  nullable    = false
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  nullable    = false
}

variable "db_instance_class" {
  description = "RDS instance class (db.r6g or db.r7g family)"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^db\\.", var.db_instance_class))
    error_message = "Must be a valid RDS instance class (e.g., db.r6g.large)."
  }
}

variable "kms_key_arn" {
  description = "ARN of the KMS CMK for encryption"
  type        = string
  nullable    = false
}

variable "db_master_password" {
  description = "The database master password"
  type        = string
  sensitive   = true
  nullable    = false
}

variable "db_password_secret_arn" {
  description = "ARN of the Secrets Manager secret storing the database master password"
  type        = string
  nullable    = false
}

variable "private_subnet_ids" {
  description = "IDs of the private subnets"
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private subnets are required for Multi-AZ RDS."
  }
}

variable "rds_security_group_id" {
  description = "ID of the RDS security group"
  type        = string
  nullable    = false
}
