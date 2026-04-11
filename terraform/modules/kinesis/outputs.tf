# Kinesis Module - Outputs

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  value       = aws_kinesis_stream.main.arn
}

output "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream"
  value       = aws_kinesis_stream.main.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for S3 object-created events"
  value       = aws_cloudwatch_event_rule.s3_object_created.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for S3 object-created events"
  value       = aws_cloudwatch_event_rule.s3_object_created.name
}

output "eventbridge_kinesis_role_arn" {
  description = "ARN of the IAM role used by EventBridge to put records into Kinesis"
  value       = aws_iam_role.eventbridge_kinesis.arn
}
