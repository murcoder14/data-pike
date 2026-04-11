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

output "db_password_secret_arn" {
  description = "ARN of the Secrets Manager secret storing the database master password"
  value       = aws_secretsmanager_secret.db_password.arn
}

output "db_password_secret_name" {
  description = "Name of the Secrets Manager secret storing the database master password"
  value       = aws_secretsmanager_secret.db_password.name
}

output "secret_rotation_lambda_arn" {
  description = "ARN of the Lambda function used for secret rotation"
  value       = aws_lambda_function.secret_rotation.arn
}

output "db_master_password" {
  description = "The generated database master password"
  value       = random_password.db_master.result
  sensitive   = true
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
