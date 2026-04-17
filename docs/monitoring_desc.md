# monitoring/main.tf — Line-by-Line Walkthrough

---

### Lines 1–5: Comments

```hcl
# Monitoring Module - CloudWatch Log Groups and Log Streams
#
# Log groups for the Flink application and each CodeBuild project
# (Build, Plan, Apply stages) to enable comprehensive monitoring.
# Requirements: 14.1, 14.4
```

This module creates the "log destinations" — the places where other services write their logs. CloudWatch is AWS's logging service. Think of a log group as a folder, and a log stream as a file inside that folder.

---

### Lines 11–23: Flink Log Group

```hcl
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
```

- `name = "/aws/kinesis-analytics/..."` — The log group path. The `/aws/kinesis-analytics/` prefix is an AWS convention for Managed Flink applications. AWS expects this naming pattern, so the Flink service knows where to write logs.
- `retention_in_days = var.log_retention_days` — How long logs are kept before CloudWatch automatically deletes them. This is a variable so you can set it differently per environment (e.g., 1 day in dev, 90 days in prod).
- `kms_key_id = var.cloudwatch_log_kms_key_arn` — Optional encryption. If a KMS key ARN is passed in, logs are encrypted at rest. If `null` is passed, CloudWatch uses its default encryption. This is controlled by the `enable_cloudwatch_logs_kms` variable in the root module.
- `tags` — Three tags for organization: a human-readable name, the environment, and the application name.

### Lines 24–27: Flink Log Stream

```hcl
resource "aws_cloudwatch_log_stream" "flink" {
  name           = "flink-application"
  log_group_name = aws_cloudwatch_log_group.flink.name
}
```

- `name = "flink-application"` — Creates a specific log stream inside the Flink log group. This is where the Flink app's actual log entries land.
- `log_group_name = aws_cloudwatch_log_group.flink.name` — Links this stream to the log group above. `.name` references the log group's name attribute.

Notice that only the Flink log group gets an explicit log stream. The CodeBuild log groups below don't — CodeBuild automatically creates its own log streams when a build runs.

---

### Lines 33–44: CodeBuild Build Log Group

```hcl
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
```

Same pattern as the Flink log group, but:
- `name = "/aws/codebuild/..."` — Uses the CodeBuild naming convention. When the Build CodeBuild project runs, it writes Maven compilation output here.
- Everything else (retention, KMS, tags) is identical in structure.

---

### Lines 50–61: CodeBuild Plan Log Group

```hcl
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
```

Same pattern again. This is where `terraform plan` output gets logged. When someone reviews the Approval stage in the pipeline, they look at these logs to see what changes Terraform is proposing.

**Why is it named `codebuild_plan` and not `terraform_plan`?** Because `terraform plan` doesn't run on its own — it runs inside a CodeBuild project. CodeBuild is the AWS service that actually executes the command. The log group belongs to that CodeBuild project, and CodeBuild requires the `/aws/codebuild/` path prefix. The name reflects which AWS service owns the logs (CodeBuild), while the suffix (`-plan`) reflects what the stage does (run Terraform plan).

---

### Lines 67–78: CodeBuild Apply Log Group

```hcl
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
```

Same pattern. This captures `terraform apply` output — the record of what infrastructure changes were actually made.

**Same naming logic as above** — `terraform apply` runs inside a CodeBuild project, so the log group is named after CodeBuild, not Terraform.

---

### Summary

This is the simplest module in the project. Four log groups (Flink, Build, Plan, Apply) plus one log stream. Every log group follows the same three-property pattern: name, retention, optional KMS encryption.

The key concept this module introduces: resources created in one module get referenced by other modules. The ARNs and names of these log groups are passed (via outputs) to the Flink module and CI/CD module, which use them to configure where their services write logs.


---

## Q&A

### Q: Why is the resource named `codebuild_plan` and `codebuild_apply` if it's Terraform plan and apply?

The names `codebuild_plan` and `codebuild_apply` reflect the AWS service that actually runs the commands, not the commands themselves. Terraform doesn't run by itself in the cloud — it runs inside CodeBuild projects. So the relationship is:

- CodeBuild is the execution environment (the "machine" that runs things)
- `terraform plan` and `terraform apply` are commands that run on that machine
- The logs belong to CodeBuild, and CodeBuild requires its log groups to use the `/aws/codebuild/` path prefix

So `codebuild_plan` means "the CodeBuild project whose job is to run `terraform plan`." It's named after the service that owns the logs, with a suffix describing the purpose.

### Q: When does CodeBuild trigger the terraform plan and apply? In which workflow?

It happens in the CI/CD pipeline (CodePipeline). Here's the sequence:

1. You push code to `main` on GitHub
2. CodePipeline detects the push and starts
3. Stage 1 (Source) — pulls the code from GitHub
4. Stage 2 (Build) — CodeBuild runs `mvn clean package` to compile the JAR
5. Stage 3 (Plan) — CodeBuild runs `terraform plan` to preview infrastructure changes
6. Stage 4 (Approval) — pipeline pauses, a human reviews and approves or rejects
7. Stage 5 (Apply) — CodeBuild runs `terraform apply` to make the approved changes

So CodeBuild is just the "runner" — CodePipeline is the orchestrator that decides when each CodeBuild project runs and in what order. The plan and apply CodeBuild projects only trigger as part of this pipeline, not on their own.

The full details of how this is wired are in `cicd/main.tf`, where the CodePipeline resource defines the stages and links each one to its CodeBuild project.
