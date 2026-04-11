# Flink Module - Outputs

output "flink_execution_role_arn" {
  description = "ARN of the IAM role for the Flink application"
  value       = aws_iam_role.flink_execution.arn
}

output "flink_execution_role_name" {
  description = "Name of the IAM role for the Flink application"
  value       = aws_iam_role.flink_execution.name
}

output "flink_application_name" {
  description = "Name of the Managed Service for Apache Flink application"
  value       = aws_kinesisanalyticsv2_application.flink.name
}

output "flink_application_arn" {
  description = "ARN of the Managed Service for Apache Flink application"
  value       = aws_kinesisanalyticsv2_application.flink.arn
}

output "flink_application_id" {
  description = "Identifier of the Managed Service for Apache Flink application"
  value       = aws_kinesisanalyticsv2_application.flink.id
}

output "flink_application_status" {
  description = "Status of the Managed Service for Apache Flink application"
  value       = aws_kinesisanalyticsv2_application.flink.status
}

output "flink_application_version_id" {
  description = "Current version of the Managed Service for Apache Flink application"
  value       = aws_kinesisanalyticsv2_application.flink.version_id
}
