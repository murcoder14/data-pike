# Flink Data Pipeline - Root Outputs

# --- State Management Outputs ---

output "state_bucket_arn" {
  description = "ARN of the S3 bucket used for Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "lock_table_arn" {
  description = "ARN of the DynamoDB table used for Terraform state locking"
  value       = aws_dynamodb_table.terraform_lock.arn
}

# --- KMS Outputs ---

output "kms_key_arn" {
  description = "ARN of the KMS CMK for encryption at rest"
  value       = module.storage.kms_key_arn
}

output "kms_key_id" {
  description = "ID of the KMS CMK for encryption at rest"
  value       = module.storage.kms_key_id
}

output "kms_alias_arn" {
  description = "ARN of the KMS key alias"
  value       = module.storage.kms_alias_arn
}

# --- Glue Catalog Outputs ---

output "glue_database_name" {
  description = "Name of the Glue Catalog database"
  value       = module.storage.glue_database_name
}

output "glue_table_name" {
  description = "Name of the Glue Catalog Iceberg table"
  value       = module.storage.glue_table_name
}

output "iceberg_warehouse_path" {
  description = "S3 path for the Iceberg warehouse"
  value       = module.storage.iceberg_warehouse_path
}

# --- S3 Bucket Outputs ---

output "input_bucket_arn" {
  description = "ARN of the S3 Input Bucket for file ingestion"
  value       = module.storage.input_bucket_arn
}

output "input_bucket_name" {
  description = "Name of the S3 Input Bucket"
  value       = module.storage.input_bucket_id
}

output "iceberg_bucket_arn" {
  description = "ARN of the S3 Iceberg Bucket for Apache Iceberg table storage"
  value       = module.storage.iceberg_bucket_arn
}

output "iceberg_bucket_name" {
  description = "Name of the S3 Iceberg Bucket"
  value       = module.storage.iceberg_bucket_id
}

output "jar_bucket_arn" {
  description = "ARN of the S3 JAR Bucket for Flink application artifacts"
  value       = module.storage.jar_bucket_arn
}

output "jar_bucket_name" {
  description = "Name of the S3 JAR Bucket"
  value       = module.storage.jar_bucket_id
}

# --- VPC Outputs ---

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.networking.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.networking.private_subnet_ids
}

output "private_subnet_cidr_blocks" {
  description = "CIDR blocks of the private subnets"
  value       = module.networking.private_subnet_cidr_blocks
}

# --- Security Group Outputs ---

output "flink_security_group_id" {
  description = "ID of the Flink application security group"
  value       = module.networking.flink_security_group_id
}

# --- VPC Endpoint Outputs ---

output "s3_vpc_endpoint_id" {
  description = "ID of the S3 gateway VPC endpoint"
  value       = module.networking.s3_vpc_endpoint_id
}

output "kinesis_vpc_endpoint_id" {
  description = "ID of the Kinesis interface VPC endpoint"
  value       = module.networking.kinesis_vpc_endpoint_id
}

output "private_route_table_id" {
  description = "ID of the private subnet route table"
  value       = module.networking.private_route_table_id
}

# --- Kinesis Outputs ---

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  value       = module.kinesis.kinesis_stream_arn
}

output "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream"
  value       = module.kinesis.kinesis_stream_name
}

# --- EventBridge Outputs ---

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for S3 object-created events"
  value       = module.kinesis.eventbridge_rule_arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for S3 object-created events"
  value       = module.kinesis.eventbridge_rule_name
}

output "eventbridge_kinesis_role_arn" {
  description = "ARN of the IAM role used by EventBridge to put records into Kinesis"
  value       = module.kinesis.eventbridge_kinesis_role_arn
}

# --- CloudWatch Log Group Outputs ---

output "flink_log_group_name" {
  description = "Name of the CloudWatch log group for the Flink application"
  value       = module.monitoring.flink_log_group_name
}

output "flink_log_group_arn" {
  description = "ARN of the CloudWatch log group for the Flink application"
  value       = module.monitoring.flink_log_group_arn
}

# --- Flink Execution Role Outputs ---

output "flink_execution_role_arn" {
  description = "ARN of the IAM role for the Flink application"
  value       = module.flink.flink_execution_role_arn
}

output "flink_execution_role_name" {
  description = "Name of the IAM role for the Flink application"
  value       = module.flink.flink_execution_role_name
}

# CI/CD outputs removed — module torn down

output "flink_application_name" {
  description = "Name of the Managed Service for Apache Flink application"
  value       = module.flink.flink_application_name
}

output "flink_application_arn" {
  description = "ARN of the Managed Service for Apache Flink application"
  value       = module.flink.flink_application_arn
}

output "flink_application_id" {
  description = "Identifier of the Managed Service for Apache Flink application"
  value       = module.flink.flink_application_id
}

output "flink_application_status" {
  description = "Status of the Managed Service for Apache Flink application"
  value       = module.flink.flink_application_status
}

output "flink_application_version_id" {
  description = "Current version of the Managed Service for Apache Flink application"
  value       = module.flink.flink_application_version_id
}

# --- Flink Application Outputs ---
