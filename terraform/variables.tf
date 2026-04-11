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

variable "db_instance_class" {
  description = "RDS instance class (db.r6g or db.r7g family)"
  type        = string
  default     = "db.r6g.large"
  nullable    = false

  validation {
    condition     = can(regex("^db\\.(r6g|r7g)\\.", var.db_instance_class))
    error_message = "Must be a memory-optimized instance class (db.r6g.* or db.r7g.*)."
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

variable "github_repo" {
  description = "GitHub repository for CI/CD source (e.g., org/repo-name)"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$", var.github_repo))
    error_message = "Must be in the format 'owner/repository'."
  }
}

variable "github_branch" {
  description = "Branch to trigger pipeline"
  type        = string
  default     = "main"
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
