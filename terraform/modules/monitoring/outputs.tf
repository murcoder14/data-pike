# Monitoring Module - Outputs

output "flink_log_group_name" {
  description = "Name of the CloudWatch log group for the Flink application"
  value       = aws_cloudwatch_log_group.flink.name
}

output "flink_log_group_arn" {
  description = "ARN of the CloudWatch log group for the Flink application"
  value       = aws_cloudwatch_log_group.flink.arn
}

output "flink_log_stream_name" {
  description = "Name of the Flink application log stream"
  value       = aws_cloudwatch_log_stream.flink.name
}
