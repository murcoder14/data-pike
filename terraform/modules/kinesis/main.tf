# Kinesis Module - Kinesis Data Stream and EventBridge
#
# Kinesis Data Stream for file notification messages and EventBridge
# rule/target routing S3 object-created events to Kinesis.
# Requirements: 4.1, 4.2, 4.3, 5.1, 5.2, 5.3

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# Kinesis Data Stream
# =============================================================================

resource "aws_kinesis_stream" "main" {
  name             = var.kinesis_stream_name
  shard_count      = var.kinesis_shard_count
  retention_period = 24

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  encryption_type = "KMS"
  kms_key_id      = var.kms_key_arn

  tags = {
    Name        = "${var.project_name}-${var.environment}"
    Environment = var.environment
  }
}

# =============================================================================
# EventBridge Rule
# =============================================================================

resource "aws_cloudwatch_event_rule" "s3_object_created" {
  name        = "${var.project_name}-${var.environment}-s3-object-created"
  description = "Captures S3 object-created events from the Input Bucket and routes to Kinesis"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [var.input_bucket_id]
      }
    }
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-s3-object-created"
    Environment = var.environment
  }
}

# =============================================================================
# EventBridge Target - Kinesis Data Stream
# =============================================================================

resource "aws_cloudwatch_event_target" "kinesis" {
  rule      = aws_cloudwatch_event_rule.s3_object_created.name
  target_id = "kinesis-stream"
  arn       = aws_kinesis_stream.main.arn
  role_arn  = aws_iam_role.eventbridge_kinesis.arn

  kinesis_target {
    partition_key_path = "$.detail.object.key"
  }
}

# =============================================================================
# IAM Role for EventBridge to put records into Kinesis
# =============================================================================

data "aws_iam_policy_document" "eventbridge_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/*"]
    }
  }
}

data "aws_iam_policy_document" "eventbridge_kinesis" {
  statement {
    effect = "Allow"
    actions = [
      "kinesis:PutRecord",
      "kinesis:PutRecords",
    ]
    resources = [aws_kinesis_stream.main.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
    ]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role" "eventbridge_kinesis" {
  name               = "${var.project_name}-${var.environment}-eventbridge-kinesis"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_assume_role.json

  tags = {
    Name        = "${var.project_name}-${var.environment}-eventbridge-kinesis"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "eventbridge_kinesis" {
  name   = "kinesis-put-records"
  role   = aws_iam_role.eventbridge_kinesis.id
  policy = data.aws_iam_policy_document.eventbridge_kinesis.json
}
