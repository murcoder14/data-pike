# Flink Data Pipeline - Root Configuration
#
# Wires together all infrastructure modules.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# Monitoring Module
# =============================================================================

module "monitoring" {
  source      = "./modules/monitoring"
  environment = var.environment
}

# =============================================================================
# Storage Module
# =============================================================================

module "storage" {
  source      = "./modules/storage"
  environment = var.environment
  aws_region  = var.aws_region
}

# =============================================================================
# Networking Module
# =============================================================================

module "networking" {
  source      = "./modules/networking"
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
  aws_region  = var.aws_region
}

# =============================================================================
# Kinesis Module
# =============================================================================

module "kinesis" {
  source              = "./modules/kinesis"
  environment         = var.environment
  kinesis_shard_count = var.kinesis_shard_count
  kms_key_arn         = module.storage.kms_key_arn
  input_bucket_id     = module.storage.input_bucket_id
}

# =============================================================================
# RDS Module
# =============================================================================

module "rds" {
  source                 = "./modules/rds"
  environment            = var.environment
  aws_region             = var.aws_region
  db_instance_class      = var.db_instance_class
  kms_key_arn            = module.storage.kms_key_arn
  db_master_password     = module.storage.db_master_password
  db_password_secret_arn = module.storage.db_password_secret_arn
  private_subnet_ids     = module.networking.private_subnet_ids
  rds_security_group_id  = module.networking.rds_security_group_id
}

# =============================================================================
# Flink Module
# =============================================================================

module "flink" {
  source                  = "./modules/flink"
  environment             = var.environment
  file_key                = var.file_key
  kms_key_arn             = module.storage.kms_key_arn
  kinesis_stream_arn      = module.kinesis.kinesis_stream_arn
  input_bucket_arn        = module.storage.input_bucket_arn
  iceberg_bucket_arn      = module.storage.iceberg_bucket_arn
  jar_bucket_arn          = module.storage.jar_bucket_arn
  flink_log_group_arn     = module.monitoring.flink_log_group_arn
  flink_log_group_name    = module.monitoring.flink_log_group_name
  flink_log_stream_name   = module.monitoring.flink_log_stream_name
  private_subnet_ids      = module.networking.private_subnet_ids
  flink_security_group_id = module.networking.flink_security_group_id
}

# =============================================================================
# CI/CD Module
# =============================================================================

module "cicd" {
  source                         = "./modules/cicd"
  environment                    = var.environment
  kms_key_arn                    = module.storage.kms_key_arn
  kms_alias_arn                  = module.storage.kms_alias_arn
  jar_bucket_arn                 = module.storage.jar_bucket_arn
  jar_bucket_id                  = module.storage.jar_bucket_id
  input_bucket_arn               = module.storage.input_bucket_arn
  iceberg_bucket_arn             = module.storage.iceberg_bucket_arn
  kinesis_stream_arn             = module.kinesis.kinesis_stream_arn
  codebuild_build_log_group_name = module.monitoring.codebuild_build_log_group_name
  codebuild_build_log_group_arn  = module.monitoring.codebuild_build_log_group_arn
  codebuild_plan_log_group_name  = module.monitoring.codebuild_plan_log_group_name
  codebuild_plan_log_group_arn   = module.monitoring.codebuild_plan_log_group_arn
  codebuild_apply_log_group_name = module.monitoring.codebuild_apply_log_group_name
  codebuild_apply_log_group_arn  = module.monitoring.codebuild_apply_log_group_arn
  flink_log_group_arn            = module.monitoring.flink_log_group_arn
  terraform_state_bucket_arn     = aws_s3_bucket.terraform_state.arn
  terraform_lock_table_arn       = aws_dynamodb_table.terraform_lock.arn
  github_repo                    = var.github_repo
  github_branch                  = var.github_branch
  file_key                       = var.file_key
}
