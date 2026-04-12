# Monitoring Module - CloudWatch Log Groups and Log Streams
#
# Log groups for the Flink application and each CodeBuild project
# (Build, Plan, Apply stages) to enable comprehensive monitoring.
# Requirements: 14.1, 14.4

# =============================================================================
# Flink Application Log Group (Requirement 14.1)
# =============================================================================

resource "aws_cloudwatch_log_group" "flink" {
  name              = "/aws/kinesis-analytics/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.cloudwatch_log_kms_key_arn

  tags = {
    Name        = "${var.project_name}-${var.environment}-flink-logs"
    Environment = var.environment
    Application = var.project_name
  }
}

resource "aws_cloudwatch_log_stream" "flink" {
  name           = "flink-application"
  log_group_name = aws_cloudwatch_log_group.flink.name
}

# =============================================================================
# CodeBuild Build Stage Log Group (Requirement 14.4)
# =============================================================================

resource "aws_cloudwatch_log_group" "codebuild_build" {
  name              = "/aws/codebuild/${var.project_name}-${var.environment}-build"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.cloudwatch_log_kms_key_arn

  tags = {
    Name        = "${var.project_name}-${var.environment}-build-logs"
    Environment = var.environment
    Application = var.project_name
  }
}

# =============================================================================
# CodeBuild Plan Stage Log Group (Requirement 14.4)
# =============================================================================

resource "aws_cloudwatch_log_group" "codebuild_plan" {
  name              = "/aws/codebuild/${var.project_name}-${var.environment}-plan"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.cloudwatch_log_kms_key_arn

  tags = {
    Name        = "${var.project_name}-${var.environment}-plan-logs"
    Environment = var.environment
    Application = var.project_name
  }
}

# =============================================================================
# CodeBuild Apply Stage Log Group (Requirement 14.4)
# =============================================================================

resource "aws_cloudwatch_log_group" "codebuild_apply" {
  name              = "/aws/codebuild/${var.project_name}-${var.environment}-apply"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.cloudwatch_log_kms_key_arn

  tags = {
    Name        = "${var.project_name}-${var.environment}-apply-logs"
    Environment = var.environment
    Application = var.project_name
  }
}
