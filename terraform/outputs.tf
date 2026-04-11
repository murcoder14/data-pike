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

# --- Secrets Manager Outputs ---

output "db_password_secret_arn" {
  description = "ARN of the Secrets Manager secret storing the database master password"
  value       = module.storage.db_password_secret_arn
}

output "db_password_secret_name" {
  description = "Name of the Secrets Manager secret storing the database master password"
  value       = module.storage.db_password_secret_name
}

output "secret_rotation_lambda_arn" {
  description = "ARN of the Lambda function used for secret rotation"
  value       = module.storage.secret_rotation_lambda_arn
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

output "rds_security_group_id" {
  description = "ID of the RDS PostgreSQL security group"
  value       = module.networking.rds_security_group_id
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

# --- RDS Outputs ---

output "rds_instance_id" {
  description = "Identifier of the RDS PostgreSQL instance"
  value       = module.rds.rds_instance_id
}

output "rds_instance_arn" {
  description = "ARN of the RDS PostgreSQL instance"
  value       = module.rds.rds_instance_arn
}

output "rds_instance_endpoint" {
  description = "Connection endpoint for the RDS PostgreSQL instance"
  value       = module.rds.rds_instance_endpoint
}

output "rds_instance_address" {
  description = "Hostname of the RDS PostgreSQL instance"
  value       = module.rds.rds_instance_address
}

output "rds_instance_port" {
  description = "Port of the RDS PostgreSQL instance"
  value       = module.rds.rds_instance_port
}

output "rds_db_name" {
  description = "Name of the default database on the RDS instance"
  value       = module.rds.rds_db_name
}

output "rds_subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = module.rds.rds_subnet_group_name
}

output "rds_enhanced_monitoring_role_arn" {
  description = "ARN of the IAM role for RDS Enhanced Monitoring"
  value       = module.rds.rds_enhanced_monitoring_role_arn
}

# --- RDS Proxy Outputs ---

output "rds_proxy_arn" {
  description = "ARN of the RDS Proxy"
  value       = module.rds.rds_proxy_arn
}

output "rds_proxy_endpoint" {
  description = "Connection endpoint for the RDS Proxy"
  value       = module.rds.rds_proxy_endpoint
}

output "rds_proxy_name" {
  description = "Name of the RDS Proxy"
  value       = module.rds.rds_proxy_name
}

output "rds_proxy_role_arn" {
  description = "ARN of the IAM role used by the RDS Proxy for Secrets Manager access"
  value       = module.rds.rds_proxy_role_arn
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

output "codebuild_build_log_group_name" {
  description = "Name of the CloudWatch log group for the Build Stage CodeBuild project"
  value       = module.monitoring.codebuild_build_log_group_name
}

output "codebuild_plan_log_group_name" {
  description = "Name of the CloudWatch log group for the Plan Stage CodeBuild project"
  value       = module.monitoring.codebuild_plan_log_group_name
}

output "codebuild_apply_log_group_name" {
  description = "Name of the CloudWatch log group for the Apply Stage CodeBuild project"
  value       = module.monitoring.codebuild_apply_log_group_name
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

# --- CI/CD IAM Role Outputs ---

output "codebuild_build_role_arn" {
  description = "ARN of the IAM role for the Build Stage CodeBuild project"
  value       = module.cicd.codebuild_build_role_arn
}

output "codebuild_build_role_name" {
  description = "Name of the IAM role for the Build Stage CodeBuild project"
  value       = module.cicd.codebuild_build_role_name
}

output "codebuild_plan_role_arn" {
  description = "ARN of the IAM role for the Plan Stage CodeBuild project"
  value       = module.cicd.codebuild_plan_role_arn
}

output "codebuild_plan_role_name" {
  description = "Name of the IAM role for the Plan Stage CodeBuild project"
  value       = module.cicd.codebuild_plan_role_name
}

output "codebuild_apply_role_arn" {
  description = "ARN of the IAM role for the Apply Stage CodeBuild project"
  value       = module.cicd.codebuild_apply_role_arn
}

output "codebuild_apply_role_name" {
  description = "Name of the IAM role for the Apply Stage CodeBuild project"
  value       = module.cicd.codebuild_apply_role_name
}

# --- Flink Application Outputs ---

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

# --- CodeBuild Project Outputs ---

output "codebuild_build_project_name" {
  description = "Name of the Build Stage CodeBuild project"
  value       = module.cicd.codebuild_build_project_name
}

output "codebuild_build_project_arn" {
  description = "ARN of the Build Stage CodeBuild project"
  value       = module.cicd.codebuild_build_project_arn
}

output "codebuild_plan_project_name" {
  description = "Name of the Plan Stage CodeBuild project"
  value       = module.cicd.codebuild_plan_project_name
}

output "codebuild_plan_project_arn" {
  description = "ARN of the Plan Stage CodeBuild project"
  value       = module.cicd.codebuild_plan_project_arn
}

output "codebuild_apply_project_name" {
  description = "Name of the Apply Stage CodeBuild project"
  value       = module.cicd.codebuild_apply_project_name
}

output "codebuild_apply_project_arn" {
  description = "ARN of the Apply Stage CodeBuild project"
  value       = module.cicd.codebuild_apply_project_arn
}

# --- CodePipeline Outputs ---

output "codepipeline_name" {
  description = "Name of the CI/CD CodePipeline"
  value       = module.cicd.codepipeline_name
}

output "codepipeline_arn" {
  description = "ARN of the CI/CD CodePipeline"
  value       = module.cicd.codepipeline_arn
}

output "codepipeline_role_arn" {
  description = "ARN of the IAM role used by CodePipeline"
  value       = module.cicd.codepipeline_role_arn
}

output "pipeline_artifacts_bucket_name" {
  description = "Name of the S3 bucket for pipeline artifacts"
  value       = module.cicd.pipeline_artifacts_bucket_name
}

output "pipeline_artifacts_bucket_arn" {
  description = "ARN of the S3 bucket for pipeline artifacts"
  value       = module.cicd.pipeline_artifacts_bucket_arn
}

output "github_codestar_connection_arn" {
  description = "ARN of the CodeConnections connection for GitHub"
  value       = module.cicd.github_codestar_connection_arn
}

output "github_codestar_connection_status" {
  description = "Status of the CodeConnections connection for GitHub (must be AVAILABLE after manual confirmation)"
  value       = module.cicd.github_codestar_connection_status
}
