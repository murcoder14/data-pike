# CI/CD Module - Input Variables

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

variable "kms_key_arn" {
  description = "ARN of the KMS CMK for encryption"
  type        = string
  nullable    = false
}

variable "kms_alias_arn" {
  description = "ARN of the KMS key alias"
  type        = string
  nullable    = false
}

variable "jar_bucket_arn" {
  description = "ARN of the S3 JAR Bucket"
  type        = string
  nullable    = false
}

variable "jar_bucket_id" {
  description = "Name/ID of the S3 JAR Bucket"
  type        = string
  nullable    = false
}

variable "input_bucket_arn" {
  description = "ARN of the S3 Input Bucket"
  type        = string
  nullable    = false
}

variable "iceberg_bucket_arn" {
  description = "ARN of the S3 Iceberg Bucket"
  type        = string
  nullable    = false
}

variable "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  type        = string
  nullable    = false
}

variable "codebuild_build_log_group_name" {
  description = "Name of the CloudWatch log group for Build Stage"
  type        = string
  nullable    = false
}

variable "codebuild_build_log_group_arn" {
  description = "ARN of the CloudWatch log group for Build Stage"
  type        = string
  nullable    = false
}

variable "codebuild_plan_log_group_name" {
  description = "Name of the CloudWatch log group for Plan Stage"
  type        = string
  nullable    = false
}

variable "codebuild_plan_log_group_arn" {
  description = "ARN of the CloudWatch log group for Plan Stage"
  type        = string
  nullable    = false
}

variable "codebuild_apply_log_group_name" {
  description = "Name of the CloudWatch log group for Apply Stage"
  type        = string
  nullable    = false
}

variable "codebuild_apply_log_group_arn" {
  description = "ARN of the CloudWatch log group for Apply Stage"
  type        = string
  nullable    = false
}

variable "flink_log_group_arn" {
  description = "ARN of the CloudWatch log group for Flink"
  type        = string
  nullable    = false
}

variable "terraform_state_bucket_arn" {
  description = "ARN of the Terraform state S3 bucket"
  type        = string
  nullable    = false
}

variable "terraform_lock_table_arn" {
  description = "ARN of the Terraform state lock DynamoDB table"
  type        = string
  nullable    = false
}

variable "github_repo" {
  description = "GitHub repository for CI/CD source (e.g., org/repo-name)"
  type        = string
  nullable    = false
}

variable "github_branch" {
  description = "Branch to trigger pipeline"
  type        = string
  nullable    = false
}

variable "file_key" {
  description = "S3 object key for the FAT JAR"
  type        = string
  nullable    = false
}

variable "pipeline_artifacts_bucket_name" {
  description = "Name of the S3 bucket for pipeline artifacts"
  type        = string
  nullable    = false
}

variable "iceberg_database_name" {
  description = "Glue Catalog database name for Iceberg tables (injected into plan/apply as TF_VAR)"
  type        = string
  nullable    = false
}

variable "iceberg_table_name" {
  description = "Iceberg table name (injected into plan/apply as TF_VAR)"
  type        = string
  nullable    = false
}
