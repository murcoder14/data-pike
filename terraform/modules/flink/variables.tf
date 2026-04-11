# Flink Module - Input Variables

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  nullable    = false
}

variable "file_key" {
  description = "S3 object key for the FAT JAR"
  type        = string
  nullable    = false
}

variable "kms_key_arn" {
  description = "ARN of the KMS CMK for encryption"
  type        = string
  nullable    = false
}

variable "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
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

variable "jar_bucket_arn" {
  description = "ARN of the S3 JAR Bucket"
  type        = string
  nullable    = false
}

variable "flink_log_group_arn" {
  description = "ARN of the CloudWatch log group for Flink"
  type        = string
  nullable    = false
}

variable "flink_log_group_name" {
  description = "Name of the CloudWatch log group for Flink"
  type        = string
  nullable    = false
}

variable "flink_log_stream_name" {
  description = "Name of the Flink log stream"
  type        = string
  nullable    = false
}

variable "private_subnet_ids" {
  description = "IDs of the private subnets"
  type        = list(string)
  nullable    = false
}

variable "flink_security_group_id" {
  description = "ID of the Flink application security group"
  type        = string
  nullable    = false
}
