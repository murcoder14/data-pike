# Storage Module - Outputs

output "kms_key_arn" {
  description = "ARN of the KMS CMK for encryption at rest"
  value       = aws_kms_key.encryption.arn
}

output "kms_key_id" {
  description = "ID of the KMS CMK for encryption at rest"
  value       = aws_kms_key.encryption.key_id
}

output "kms_alias_arn" {
  description = "ARN of the KMS key alias"
  value       = aws_kms_alias.encryption.arn
}

output "input_bucket_arn" {
  description = "ARN of the S3 Input Bucket for file ingestion"
  value       = aws_s3_bucket.input.arn
}

output "input_bucket_id" {
  description = "Name/ID of the S3 Input Bucket"
  value       = aws_s3_bucket.input.id
}

output "iceberg_bucket_arn" {
  description = "ARN of the S3 Iceberg Bucket for Apache Iceberg table storage"
  value       = aws_s3_bucket.iceberg.arn
}

output "iceberg_bucket_id" {
  description = "Name/ID of the S3 Iceberg Bucket"
  value       = aws_s3_bucket.iceberg.id
}

output "jar_bucket_arn" {
  description = "ARN of the S3 JAR Bucket for Flink application artifacts"
  value       = aws_s3_bucket.jar.arn
}

output "jar_bucket_id" {
  description = "Name/ID of the S3 JAR Bucket"
  value       = aws_s3_bucket.jar.id
}

# --- Glue Catalog Outputs ---

output "glue_database_name" {
  description = "Name of the Glue Catalog database"
  value       = aws_glue_catalog_database.iceberg.name
}

output "glue_table_name" {
  description = "Name of the Glue Catalog Iceberg table"
  value       = aws_glue_catalog_table.iceberg.name
}

output "iceberg_warehouse_path" {
  description = "S3 path for the Iceberg warehouse"
  value       = "s3://${aws_s3_bucket.iceberg.id}/warehouse"
}
