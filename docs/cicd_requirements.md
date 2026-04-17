# CDE Ignite - CI/CD Pipeline Requirements

This document captures the CI/CD pipeline requirements reverse-engineered from the current Terraform implementation. It is intended for handover to a DevOps team.

---

## 1. Pipeline Overview

1.1. A CodePipeline must be created that automates the build, infrastructure planning, approval, and deployment process.

1.2. The pipeline must be triggered by pushes to a configurable GitHub branch (default: `main`).

1.3. The pipeline must have five stages executed in order: Source → Build → Plan → Approval → Apply.

1.4. No infrastructure changes may be applied without explicit human approval.

---

## 2. Source Stage

2.1. A CodeConnections (v2) connection must be created to link AWS to the GitHub repository.

2.2. The connection provider type must be `GitHub`.

2.3. The source action must use the `CodeStarSourceConnection` provider to pull the full repository.

2.4. The source output artifact (`source_output`) must be passed to both the Build and Plan stages.

2.5. Note: The connection is created in `PENDING` status and requires a one-time manual authorization in the AWS console.

---

## 3. Build Stage

3.1. A CodeBuild project must be created for the Build stage using:
  - Compute: `BUILD_GENERAL1_MEDIUM`
  - Image: `aws/codebuild/amazonlinux2-x86_64-standard:5.0`
  - Runtime: Amazon Corretto 17 (Java 17)
  - Timeout: 30 minutes
  - Privileged mode: disabled

3.2. The build must execute `mvn clean package -DskipTests` to compile the Java application and produce a FAT JAR using the Maven Shade plugin.

3.3. The build must upload the JAR to the JAR Bucket at two locations:
  - The configured `file_key` path (the "latest" JAR)
  - A commit-tagged path: `jars/my-app-{commit_hash}.jar`

3.4. The JAR Bucket name and file key must be passed as environment variables (`JAR_BUCKET`, `FILE_KEY`).

3.5. Build logs must be written to the Build stage CloudWatch log group.

---

## 4. Plan Stage

4.1. A CodeBuild project must be created for the Plan stage using:
  - Compute: `BUILD_GENERAL1_SMALL`
  - Image: `aws/codebuild/amazonlinux2-x86_64-standard:5.0`
  - Timeout: 30 minutes
  - Privileged mode: disabled

4.2. The buildspec must download Terraform, verify its integrity using SHA-256 checksums, and install it.

4.3. The buildspec must run `terraform init` with the S3 backend configuration passed via environment variables (`TF_STATE_BUCKET`, `TF_STATE_KEY`, `TF_STATE_REGION`).

4.4. The buildspec must run `terraform plan -out=tfplan` to generate a binary plan file.

4.5. The buildspec must run `terraform show tfplan` to log a human-readable version of the plan.

4.6. The plan binary (`terraform/tfplan`) must be passed as an output artifact (`plan_output`) to the Apply stage.

4.7. Terraform variables must be passed via environment variables: `TF_VAR_file_key`, `TF_VAR_environment`, `TF_VAR_github_repo`, `TF_VAR_github_branch`.

4.8. Plan logs must be written to the Plan stage CloudWatch log group.

---

## 5. Approval Stage

5.1. A manual approval action must pause the pipeline between Plan and Apply.

5.2. The approval must include a custom message instructing the reviewer to check the Plan stage logs before approving.

5.3. Rejecting the approval must stop the pipeline entirely.

---

## 6. Apply Stage

6.1. A CodeBuild project must be created for the Apply stage using:
  - Compute: `BUILD_GENERAL1_SMALL`
  - Image: `aws/codebuild/amazonlinux2-x86_64-standard:5.0`
  - Timeout: 30 minutes
  - Privileged mode: disabled

6.2. The buildspec must download and verify Terraform (same SHA-256 process as Plan).

6.3. The buildspec must run `terraform init` with the S3 backend configuration.

6.4. The buildspec must run `terraform apply -auto-approve tfplan` using the pre-generated plan binary from the Plan stage. It must not generate a new plan.

6.5. Apply logs must be written to the Apply stage CloudWatch log group.

---

## 7. Pipeline Artifacts Bucket

7.1. An S3 bucket must be created for pipeline artifacts with a configurable name (default: `{project_name}-{environment}-pipeline-artifacts`).

7.2. The artifacts bucket must be encrypted at rest using the shared CMK.

7.3. The artifacts bucket must have versioning enabled.

7.4. The artifacts bucket must block all public access.

7.5. The artifacts bucket must enforce TLS-only access via bucket policy.

7.6. The pipeline's artifact store must use this bucket with KMS encryption.

---

## 8. IAM Roles — Separation of Duties

Each pipeline component must have its own IAM role following the principle of least privilege. No role may have more permissions than its stage requires.

### 8.1. CodePipeline Role

8.1.1. Assumable by `codepipeline.amazonaws.com` with `aws:SourceAccount` condition.

8.1.2. Permissions:
  - S3: Read/write on the pipeline artifacts bucket only (GetObject, GetObjectVersion, GetBucketVersioning, PutObject, PutObjectAcl, ListBucket)
  - CodeConnections: `UseConnection` on the specific GitHub connection
  - CodeBuild: `BatchGetBuilds`, `StartBuild` on the three CodeBuild projects only
  - KMS: Decrypt, DescribeKey, GenerateDataKey on the shared CMK

### 8.2. Build Stage Role

8.2.1. Assumable by `codebuild.amazonaws.com` with `aws:SourceAccount` condition.

8.2.2. Permissions:
  - S3: Read/write on the JAR Bucket only (PutObject, GetObject, GetBucketLocation, ListBucket)
  - CloudWatch: Log writing on the Build log group only
  - KMS: Decrypt, DescribeKey, GenerateDataKey on the shared CMK
  - CodeBuild: Report permissions (CreateReportGroup, CreateReport, UpdateReport, BatchPutTestCases, BatchPutCodeCoverages) scoped to `{project}-{env}-build-*` report groups

8.2.3. Must NOT have access to infrastructure resources, Terraform state, or any bucket other than the JAR Bucket.

### 8.3. Plan Stage Role

8.3.1. Assumable by `codebuild.amazonaws.com` with `aws:SourceAccount` condition.

8.3.2. Permissions:
  - S3 State: Read-only on the Terraform state bucket (GetObject, GetObjectVersion, ListBucket, GetBucketLocation)
  - DynamoDB: State lock operations (GetItem, PutItem, DeleteItem, DescribeTable) on the lock table
  - CloudWatch: Log writing on the Plan log group only
  - KMS: Decrypt, DescribeKey, GenerateDataKey on the shared CMK
  - Read-only access to all project infrastructure for `terraform plan`:
    - S3: Bucket metadata on Input, Iceberg, JAR buckets
    - Kinesis: DescribeStream, DescribeStreamSummary, ListTagsForStream
    - EC2: Describe VPCs, subnets, security groups, endpoints, route tables, network interfaces, prefix lists
    - IAM: GetRole, GetRolePolicy, ListRolePolicies, ListAttachedRolePolicies, GetPolicy, GetPolicyVersion — scoped to `{project}-{env}-*`
    - KMS: DescribeKey, GetKeyPolicy, GetKeyRotationStatus, ListAliases
    - CloudWatch: DescribeLogGroups, ListTagsForResource on all four log groups
    - Secrets Manager: DescribeSecret, GetResourcePolicy — scoped to `{project}-{env}-*`
    - EventBridge: DescribeRule, ListTargetsByRule, ListTagsForResource — scoped to `{project}-{env}-*`
    - Kinesis Analytics V2: DescribeApplication, ListTagsForResource on the Flink application
    - DynamoDB: DescribeTable, ListTagsOfResource on the lock table
  - CodeBuild: Report permissions scoped to `{project}-{env}-plan-*`

8.3.3. Must NOT have write access to any infrastructure resource. Read-only for planning purposes.

### 8.4. Apply Stage Role

8.4.1. Assumable by `codebuild.amazonaws.com` with `aws:SourceAccount` condition.

8.4.2. Permissions:
  - S3 State: Read/write on the Terraform state bucket
  - DynamoDB: State lock operations on the lock table
  - CloudWatch: Full log management (create, delete, configure retention, tag) on all four log groups
  - Full resource management scoped to project resources:
    - S3: Full bucket lifecycle on Input, Iceberg, JAR buckets
    - Kinesis: Full stream lifecycle on the specific stream
    - EC2/VPC: Full VPC lifecycle (VPCs, subnets, security groups, route tables, endpoints, tags)
    - IAM: Full role lifecycle — scoped to `{project}-{env}-*` roles, policies, and instance profiles
    - KMS: Full key management on the shared CMK and its alias
    - Secrets Manager: Full secret lifecycle — scoped to `{project}-{env}-*`
    - EventBridge: Full rule lifecycle — scoped to `{project}-{env}-*`
    - Kinesis Analytics V2: Full application lifecycle on the specific Flink application
    - DynamoDB: Full table lifecycle on the lock table
    - RDS: Full DB lifecycle — scoped to `{project}-{env}*` resources
  - CodeBuild: Report permissions scoped to `{project}-{env}-apply-*`

8.4.3. This role only executes after human approval in the Approval stage.

---

## 9. Security Requirements

9.1. Each pipeline stage must have its own IAM role — no shared roles between stages.

9.2. All IAM roles must use `aws:SourceAccount` conditions in their assume role policies to prevent cross-account confused deputy attacks.

9.3. All IAM permissions must be scoped to specific resources (no `*` wildcards except where AWS requires it, e.g., EC2 Describe actions).

9.4. All IAM resource scoping must use the `{project_name}-{environment}-` prefix to prevent access to resources outside this project.

9.5. Pipeline artifacts must be encrypted with the shared CMK.

9.6. All CodeBuild logs must be written to dedicated CloudWatch log groups.

9.7. Terraform must be downloaded with SHA-256 checksum verification in both Plan and Apply stages.

9.8. The Apply stage must only execute a pre-generated plan — it must not run `terraform plan` itself.

---

## 10. Deletion Behavior

10.1. The CodePipeline and all CodeBuild projects must be destroyed during `terraform destroy` (no `prevent_destroy`).

10.2. The pipeline artifacts bucket must be destroyed during `terraform destroy`.

10.3. The CodeConnections GitHub connection must be destroyed during `terraform destroy`.

10.4. All CI/CD IAM roles and policies must be destroyed during `terraform destroy`.


---

## 11. Flink Application Lifecycle — Pipeline Operations

These requirements address post-deployment verification and failure recovery within the CI/CD pipeline, based on the [AWS deep dive on Managed Flink application lifecycle (Part 1)](https://aws.amazon.com/blogs/big-data/deep-dive-into-the-amazon-managed-service-for-apache-flink-application-lifecycle-part-1/) and [Part 2](https://aws.amazon.com/blogs/big-data/deep-dive-into-the-amazon-managed-service-for-apache-flink-application-lifecycle-part-2/).

### Post-Deploy Health Check

11.1. After the Apply stage completes, the pipeline must include a health check step that verifies the Flink application is actually healthy and processing data — not just in `RUNNING` status.

11.2. The health check must poll the `DescribeApplication` API to confirm the application status returns to `RUNNING` within a configurable timeout (recommended: 10–15 minutes, accounting for snapshot restore time).

11.3. The health check must monitor the `fullRestarts` CloudWatch metric to detect if the application enters a fail-and-restart loop after the update.

11.4. The health check timeout must be configurable and should account for the full update operation duration (cluster provisioning + snapshot + restart + state restore).

11.5. If the health check detects a failure (application not `RUNNING` within timeout, or fail-and-restart loop detected), the pipeline must trigger the rollback procedure (see 11.6).

### Automated Rollback

11.6. The pipeline must support automated rollback when a deployment fails the health check. The rollback must use the `RollbackApplication` API action, which restores the previous configuration version and restarts from the snapshot taken before the faulty change was deployed.

11.7. If `RollbackApplication` fails (e.g., the application is in a state that doesn't support rollback), the pipeline must fall back to force-stopping the application using `StopApplication` with `Force=true`, then alert the operations team for manual intervention.

11.8. After a rollback (automatic or manual), the pipeline must report the failure and rollback status clearly in the pipeline execution output and CloudWatch logs.

### Force-Stop Handling

11.9. The pipeline must support force-stopping the Flink application as a last resort when graceful stop and rollback both fail.

11.10. After a force-stop, the pipeline must not automatically restart the application. A human must review the failure, fix the issue, and manually restart — optionally from a scheduled snapshot.

11.11. Force-stop events must trigger an SNS notification to the operations team.

### JAR Retention

11.12. The Build stage must continue uploading commit-tagged JARs (`jars/my-app-{commit_hash}.jar`) in addition to the latest JAR. This ensures previous code versions remain available in S3 for rollback operations that use `UpdateApplication` with an older configuration.

11.13. A JAR retention policy should be defined (e.g., retain the last 10 commit-tagged JARs) to prevent unbounded storage growth. This can be implemented via S3 lifecycle rules on the JAR Bucket.
