# CI/CD Module - Outputs

output "codebuild_build_role_arn" {
  description = "ARN of the IAM role for the Build Stage CodeBuild project"
  value       = aws_iam_role.codebuild_build.arn
}

output "codebuild_build_role_name" {
  description = "Name of the IAM role for the Build Stage CodeBuild project"
  value       = aws_iam_role.codebuild_build.name
}

output "codebuild_plan_role_arn" {
  description = "ARN of the IAM role for the Plan Stage CodeBuild project"
  value       = aws_iam_role.codebuild_plan.arn
}

output "codebuild_plan_role_name" {
  description = "Name of the IAM role for the Plan Stage CodeBuild project"
  value       = aws_iam_role.codebuild_plan.name
}

output "codebuild_apply_role_arn" {
  description = "ARN of the IAM role for the Apply Stage CodeBuild project"
  value       = aws_iam_role.codebuild_apply.arn
}

output "codebuild_apply_role_name" {
  description = "Name of the IAM role for the Apply Stage CodeBuild project"
  value       = aws_iam_role.codebuild_apply.name
}

output "codebuild_build_project_name" {
  description = "Name of the Build Stage CodeBuild project"
  value       = aws_codebuild_project.build.name
}

output "codebuild_build_project_arn" {
  description = "ARN of the Build Stage CodeBuild project"
  value       = aws_codebuild_project.build.arn
}

output "codebuild_plan_project_name" {
  description = "Name of the Plan Stage CodeBuild project"
  value       = aws_codebuild_project.plan.name
}

output "codebuild_plan_project_arn" {
  description = "ARN of the Plan Stage CodeBuild project"
  value       = aws_codebuild_project.plan.arn
}

output "codebuild_apply_project_name" {
  description = "Name of the Apply Stage CodeBuild project"
  value       = aws_codebuild_project.apply.name
}

output "codebuild_apply_project_arn" {
  description = "ARN of the Apply Stage CodeBuild project"
  value       = aws_codebuild_project.apply.arn
}

output "codepipeline_name" {
  description = "Name of the CI/CD CodePipeline"
  value       = aws_codepipeline.main.name
}

output "codepipeline_arn" {
  description = "ARN of the CI/CD CodePipeline"
  value       = aws_codepipeline.main.arn
}

output "codepipeline_role_arn" {
  description = "ARN of the IAM role used by CodePipeline"
  value       = aws_iam_role.codepipeline.arn
}

output "pipeline_artifacts_bucket_name" {
  description = "Name of the S3 bucket for pipeline artifacts"
  value       = aws_s3_bucket.pipeline_artifacts.id
}

output "pipeline_artifacts_bucket_arn" {
  description = "ARN of the S3 bucket for pipeline artifacts"
  value       = aws_s3_bucket.pipeline_artifacts.arn
}

output "github_codestar_connection_arn" {
  description = "ARN of the CodeConnections connection for GitHub"
  value       = aws_codeconnections_connection.github.arn
}

output "github_codestar_connection_status" {
  description = "Status of the CodeConnections connection for GitHub"
  value       = aws_codeconnections_connection.github.connection_status
}
