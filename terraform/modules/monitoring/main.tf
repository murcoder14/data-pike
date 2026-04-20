# Monitoring Module - CloudWatch Log Group and Log Stream for the Flink application
#
# Requirements: 14.1

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
