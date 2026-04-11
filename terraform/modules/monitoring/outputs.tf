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

output "codebuild_build_log_group_name" {
  description = "Name of the CloudWatch log group for the Build Stage CodeBuild project"
  value       = aws_cloudwatch_log_group.codebuild_build.name
}

output "codebuild_build_log_group_arn" {
  description = "ARN of the CloudWatch log group for the Build Stage CodeBuild project"
  value       = aws_cloudwatch_log_group.codebuild_build.arn
}

output "codebuild_plan_log_group_name" {
  description = "Name of the CloudWatch log group for the Plan Stage CodeBuild project"
  value       = aws_cloudwatch_log_group.codebuild_plan.name
}

output "codebuild_plan_log_group_arn" {
  description = "ARN of the CloudWatch log group for the Plan Stage CodeBuild project"
  value       = aws_cloudwatch_log_group.codebuild_plan.arn
}

output "codebuild_apply_log_group_name" {
  description = "Name of the CloudWatch log group for the Apply Stage CodeBuild project"
  value       = aws_cloudwatch_log_group.codebuild_apply.name
}

output "codebuild_apply_log_group_arn" {
  description = "ARN of the CloudWatch log group for the Apply Stage CodeBuild project"
  value       = aws_cloudwatch_log_group.codebuild_apply.arn
}
