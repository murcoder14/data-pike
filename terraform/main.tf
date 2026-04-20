# Flink Data Pipeline - Root Configuration
#
# Wires together all infrastructure modules.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# Monitoring Module
# =============================================================================

module "monitoring" {
  source                     = "./modules/monitoring"
  project_name               = var.project_name
  environment                = var.environment
  log_retention_days         = var.log_retention_days
  cloudwatch_log_kms_key_arn = var.enable_cloudwatch_logs_kms ? module.storage.kms_key_arn : null
}

# =============================================================================
# Storage Module
# =============================================================================

module "storage" {
  source                = "./modules/storage"
  project_name          = var.project_name
  environment           = var.environment
  iceberg_database_name = var.iceberg_database_name
  iceberg_table_name    = var.iceberg_table_name
  input_bucket_name     = var.input_bucket_name != "" ? var.input_bucket_name : "${var.project_name}-${var.environment}-input"
  iceberg_bucket_name   = var.iceberg_bucket_name != "" ? var.iceberg_bucket_name : "${var.project_name}-${var.environment}-iceberg"
  jar_bucket_name       = var.jar_bucket_name != "" ? var.jar_bucket_name : "${var.project_name}-${var.environment}-jar"
}

# =============================================================================
# Networking Module
# =============================================================================

module "networking" {
  source                     = "./modules/networking"
  project_name               = var.project_name
  environment                = var.environment
  vpc_cidr                   = var.vpc_cidr
  aws_region                 = var.aws_region
  log_retention_days         = var.log_retention_days
  cloudwatch_log_kms_key_arn = var.enable_cloudwatch_logs_kms ? module.storage.kms_key_arn : null
  enable_vpc_flow_logs       = var.enable_vpc_flow_logs
}

# =============================================================================
# Kinesis Module
# =============================================================================

module "kinesis" {
  source              = "./modules/kinesis"
  project_name        = var.project_name
  environment         = var.environment
  kinesis_shard_count = var.kinesis_shard_count
  kinesis_stream_name = var.kinesis_stream_name != "" ? var.kinesis_stream_name : "${var.project_name}-${var.environment}"
  kms_key_arn         = module.storage.kms_key_arn
  input_bucket_id     = module.storage.input_bucket_id
}

# =============================================================================
# Flink Module
# =============================================================================

module "flink" {
  source                  = "./modules/flink"
  providers = {
    aws = aws.no_tags
  }
  project_name            = var.project_name
  environment             = var.environment
  file_key                = var.file_key
  aws_region              = var.aws_region
  kms_key_arn             = module.storage.kms_key_arn
  kinesis_stream_arn      = module.kinesis.kinesis_stream_arn
  input_bucket_arn        = module.storage.input_bucket_arn
  iceberg_bucket_arn      = module.storage.iceberg_bucket_arn
  jar_bucket_arn          = module.storage.jar_bucket_arn
  flink_log_group_arn     = module.monitoring.flink_log_group_arn
  flink_log_stream_name   = module.monitoring.flink_log_stream_name
  private_subnet_ids      = module.networking.private_subnet_ids
  flink_security_group_id = module.networking.flink_security_group_id
  iceberg_warehouse_path  = module.storage.iceberg_warehouse_path
  iceberg_catalog_name    = var.iceberg_catalog_name
  iceberg_table_name      = "${var.iceberg_database_name}.${var.iceberg_table_name}"
  iceberg_database_name   = var.iceberg_database_name
}

# CI/CD module removed — retaining core data pipeline infrastructure only
