variable "project_name" {
  description = "Project name used as a prefix for all resource names"
  type        = string
  default     = "flink-data-pipeline"
  nullable    = false
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
  nullable    = false

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "Must be a valid AWS region identifier (e.g., us-east-1)."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  nullable    = false

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be a valid CIDR block (e.g., 10.0.0.0/16)."
  }
}

variable "kinesis_shard_count" {
  description = "Number of Kinesis stream shards"
  type        = number
  default     = 1
  nullable    = false

  validation {
    condition     = var.kinesis_shard_count >= 1 && var.kinesis_shard_count <= 500
    error_message = "Shard count must be between 1 and 500."
  }
}

variable "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream (defaults to project_name-environment)"
  type        = string
  default     = ""
  nullable    = false
}

variable "file_key" {
  description = "S3 object key for the FAT JAR (changes trigger UpdateApplication)"
  type        = string
  nullable    = false

  validation {
    condition     = endswith(var.file_key, ".jar")
    error_message = "File key must end with .jar."
  }
}

variable "iceberg_database_name" {
  description = "Name of the Glue Catalog database for Iceberg tables"
  type        = string
  default     = "flink_pipeline"
  nullable    = false
}

variable "iceberg_table_name" {
  description = "Name of the Iceberg table (without database prefix)"
  type        = string
  default     = "processed_data"
  nullable    = false
}

variable "iceberg_catalog_name" {
  description = "Name of the Iceberg catalog (used by Flink application)"
  type        = string
  default     = "glue_catalog"
  nullable    = false
}

variable "input_bucket_name" {
  description = "Name of the S3 Input Bucket (defaults to project_name-environment-input)"
  type        = string
  default     = ""
  nullable    = false
}

variable "iceberg_bucket_name" {
  description = "Name of the S3 Iceberg Bucket (defaults to project_name-environment-iceberg)"
  type        = string
  default     = ""
  nullable    = false
}

variable "jar_bucket_name" {
  description = "Name of the S3 JAR Bucket (defaults to project_name-environment-jar)"
  type        = string
  default     = ""
  nullable    = false
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days. Keep at 1 for dev if short retention is acceptable."
  type        = number
  default     = 1
  nullable    = false

  validation {
    condition     = var.log_retention_days >= 1
    error_message = "Log retention must be at least 1 day."
  }
}

variable "enable_cloudwatch_logs_kms" {
  description = "Encrypt CloudWatch log groups with the project KMS key. Typically false in dev and true in staging/prod."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC flow logs. Typically false in dev and true in prod."
  type        = bool
  default     = false
  nullable    = false
}

