# Monitoring Module - CloudWatch Log Groups and Log Streams
#
# Log groups for the Flink application and each CodeBuild project
# (Build, Plan, Apply stages) to enable comprehensive monitoring.
# Requirements: 14.1, 14.4

# =============================================================================
# Flink Application Log Group (Requirement 14.1)
# =============================================================================

resource "aws_cloudwatch_log_group" "flink" {
  name              = "/aws/kinesis-analytics/flink-data-pipeline-${var.environment}"
  retention_in_days = 30

  tags = {
    Name        = "flink-data-pipeline-${var.environment}-flink-logs"
    Environment = var.environment
    Application = "flink-data-pipeline"
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
  name              = "/aws/codebuild/flink-data-pipeline-${var.environment}-build"
  retention_in_days = 30

  tags = {
    Name        = "flink-data-pipeline-${var.environment}-build-logs"
    Environment = var.environment
    Application = "flink-data-pipeline"
  }
}

# =============================================================================
# CodeBuild Plan Stage Log Group (Requirement 14.4)
# =============================================================================

resource "aws_cloudwatch_log_group" "codebuild_plan" {
  name              = "/aws/codebuild/flink-data-pipeline-${var.environment}-plan"
  retention_in_days = 30

  tags = {
    Name        = "flink-data-pipeline-${var.environment}-plan-logs"
    Environment = var.environment
    Application = "flink-data-pipeline"
  }
}

# =============================================================================
# CodeBuild Apply Stage Log Group (Requirement 14.4)
# =============================================================================

resource "aws_cloudwatch_log_group" "codebuild_apply" {
  name              = "/aws/codebuild/flink-data-pipeline-${var.environment}-apply"
  retention_in_days = 30

  tags = {
    Name        = "flink-data-pipeline-${var.environment}-apply-logs"
    Environment = var.environment
    Application = "flink-data-pipeline"
  }
}
