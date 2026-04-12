# Kinesis Module - Input Variables

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

variable "kinesis_shard_count" {
  description = "Number of Kinesis stream shards"
  type        = number
  nullable    = false

  validation {
    condition     = var.kinesis_shard_count >= 1
    error_message = "Shard count must be at least 1."
  }
}

variable "kms_key_arn" {
  description = "ARN of the KMS CMK for encryption"
  type        = string
  nullable    = false

  validation {
    condition     = startswith(var.kms_key_arn, "arn:aws:kms:")
    error_message = "Must be a valid KMS key ARN."
  }
}

variable "input_bucket_id" {
  description = "Name/ID of the S3 Input Bucket (for EventBridge rule pattern)"
  type        = string
  nullable    = false
}

variable "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream"
  type        = string
  nullable    = false
}
