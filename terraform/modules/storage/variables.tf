# Storage Module - Input Variables

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

variable "iceberg_database_name" {
  description = "Name of the Glue Catalog database for Iceberg tables"
  type        = string
  nullable    = false
}

variable "iceberg_table_name" {
  description = "Name of the Iceberg table (without database prefix)"
  type        = string
  nullable    = false
}

variable "input_bucket_name" {
  description = "Name of the S3 Input Bucket"
  type        = string
  nullable    = false
}

variable "iceberg_bucket_name" {
  description = "Name of the S3 Iceberg Bucket"
  type        = string
  nullable    = false
}

variable "jar_bucket_name" {
  description = "Name of the S3 JAR Bucket"
  type        = string
  nullable    = false
}
