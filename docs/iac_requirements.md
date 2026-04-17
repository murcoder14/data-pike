# CDE Ignite - AWS Cloud Infrastructure Requirements

This document captures the infrastructure requirements reverse-engineered from the current Terraform implementation. It is intended for handover to a DevOps team.

---

## 1. General

1.1. All infrastructure must be defined as code using Terraform (>= 1.5.0, < 2.0.0).

1.2. All resources must be prefixed with `{project_name}-{environment}` for naming consistency.

1.3. All resources must be tagged with `Environment`, `Application`, and `ManagedBy` tags.

1.4. The solution must support multiple environments (`dev`, `staging`, `prod`) using environment-specific variable files.

1.5. The AWS provider version must be pinned to `~> 6.40` (hashicorp/aws).

---

## 2. Terraform State Management

2.1. Terraform state must be stored remotely in an S3 bucket named `{project_name}-tf-state`.

2.2. State locking must be implemented using a DynamoDB table named `{project_name}-tf-lock` with a `LockID` string hash key and pay-per-request billing.

2.3. The state bucket must have `prevent_destroy = true` to protect against accidental deletion.

2.4. The state bucket must have versioning enabled for state recovery.

2.5. The state bucket must be encrypted at rest using AES-256 (SSE-S3).

2.6. The state bucket must block all public access (all four public access block settings enabled).

2.7. The state bucket must enforce TLS-only access via a bucket policy that denies requests where `aws:SecureTransport` is `false`.

---

## 3. Encryption (KMS)

3.1. A single Customer Managed Key (CMK) must be created to encrypt all data at rest across the project.

3.2. The CMK must have automatic key rotation enabled.

3.3. The CMK must have a 30-day deletion window.

3.4. The CMK key policy must grant full access to the AWS account root principal.

3.5. The CMK key policy must allow the CloudWatch Logs service to use the key for encrypting/decrypting log data, scoped to log groups in the current account and region.

3.6. A KMS alias must be created in the format `alias/{project_name}-{environment}`.

---

## 4. Storage (S3 Buckets)

4.1. Three S3 buckets must be created:
  - Input Bucket (`{project_name}-{environment}-input`) — for uploading files to be processed
  - Iceberg Bucket (`{project_name}-{environment}-iceberg`) — for storing processed output data
  - JAR Bucket (`{project_name}-{environment}-jar`) — for storing the compiled application code

4.2. All three buckets must be encrypted at rest using the shared CMK with `aws:kms` SSE algorithm.

4.3. All three buckets must have S3 Bucket Keys enabled to reduce KMS API call costs.

4.4. All three buckets must have versioning enabled.

4.5. All three buckets must block all public access (all four public access block settings enabled).

4.6. All three buckets must enforce TLS-only access via a bucket policy that denies requests where `aws:SecureTransport` is `false`.

4.7. The Input Bucket must have EventBridge notifications enabled so that S3 object-created events are sent to EventBridge.

4.8. Bucket names must be configurable via variables, with defaults derived from `{project_name}-{environment}-{purpose}`.

---

## 5. Data Catalog (Glue)

5.1. A Glue Catalog database must be created with a configurable name (default: `flink_pipeline`).

5.2. A Glue Catalog table must be created as an Iceberg v2 external table with `metadata_operation = "CREATE"`.

5.3. The table must define the following schema: `date` (string), `max_temp` (int), `max_temp_city` (string), `min_temp` (int), `min_temp_city` (string).

5.4. The table's storage location must point to `s3://{iceberg_bucket}/warehouse/{database_name}/{table_name}`.

---

## 6. Event Routing (EventBridge + Kinesis)

6.1. A Kinesis Data Stream must be created with configurable shard count (default: 1, range: 1–500), provisioned mode, and 24-hour retention.

6.2. The Kinesis stream must be encrypted using the shared CMK.

6.3. An EventBridge rule must capture `Object Created` events from the Input Bucket only.

6.4. An EventBridge target must route matched events to the Kinesis stream, using the S3 object key (`$.detail.object.key`) as the partition key.

6.5. An IAM role must be created for EventBridge with permissions limited to `kinesis:PutRecord` and `kinesis:PutRecords` on the specific stream only.

6.6. The EventBridge IAM role's assume role policy must include an `aws:SourceAccount` condition to prevent cross-account confused deputy attacks.

---

## 7. Flink Application

7.1. A Managed Service for Apache Flink application must be created using the `aws_kinesisanalyticsv2_application` resource type (Kinesis Analytics V2 API).

7.2. The application must use runtime environment `FLINK-2_2` in `STREAMING` mode.

7.3. The application code must be loaded from the JAR Bucket at a configurable S3 key (`file_key`), with content type `ZIPFILE`.

7.4. Checkpointing must use the `DEFAULT` configuration type.

7.5. Monitoring must be configured with `CUSTOM` type, `INFO` log level, and `APPLICATION` metrics level.

7.6. Parallelism must be configured with `CUSTOM` type, auto-scaling enabled, initial parallelism of 1, and 1 parallelism per KPU.

7.7. The application must be deployed into private subnets with the Flink security group attached.

7.8. Runtime properties must be passed via environment property groups:
  - `KinesisSource` group: `stream.arn`, `aws.region`
  - `IcebergSink` group: `warehouse.path`, `catalog.name`, `table.name`

7.9. CloudWatch logging must be configured to write to a specific log stream within the Flink log group.

7.10. The application must be set to `start_application = true` (continuously running).

7.11. The application must have `prevent_destroy = true` to protect against accidental deletion.

---

## 8. Flink Execution IAM Role

8.1. A dedicated IAM execution role must be created for the Flink application, assumable only by `kinesisanalytics.amazonaws.com` with an `aws:SourceAccount` condition.

8.2. The role must have read access to the Kinesis stream (GetRecords, GetShardIterator, DescribeStream, ListShards, SubscribeToShard, DescribeStreamSummary), conditioned on `aws:RequestedRegion`.

8.3. The role must have read access to the Input Bucket (GetObject, GetObjectVersion, ListBucket).

8.4. The role must have read/write access to the Iceberg Bucket (GetObject, GetObjectVersion, PutObject, DeleteObject, ListBucket).

8.5. The role must have read access to the JAR Bucket (GetObject, GetObjectVersion, ListBucket).

8.6. The role must have CloudWatch logging permissions (CreateLogStream, PutLogEvents, DescribeLogGroups, DescribeLogStreams) scoped to the Flink log group, conditioned on `aws:SourceAccount`.

8.7. The role must have KMS permissions (Decrypt, DescribeKey, GenerateDataKey) on the shared CMK, conditioned on `aws:RequestedRegion`.

8.8. The role must have Glue Catalog permissions (GetDatabase, GetDatabases, GetTable, GetTables, GetTableVersion, GetTableVersions, UpdateTable, GetPartition, GetPartitions, BatchGetPartition) scoped to the specific catalog, database, and table.

8.9. The role must have VPC networking permissions:
  - EC2 Describe actions (DescribeNetworkInterfaces, DescribeSecurityGroups, DescribeSubnets, DescribeVpcs, DescribeDhcpOptions) on all resources (required by AWS)
  - CreateNetworkInterface scoped to network interfaces, the Flink security group, and subnets
  - DeleteNetworkInterface and CreateNetworkInterfacePermission scoped to network interfaces

---

## 9. Networking

9.1. A VPC must be created with a configurable CIDR block (default: `10.0.0.0/16`), DNS support enabled, and DNS hostnames enabled.

9.2. Two private subnets must be created in different availability zones for high availability, carved from the VPC CIDR using `/24` blocks.

9.3. A route table must be created and associated with both private subnets. The route table must have no route to an internet gateway.

9.4. A Flink security group must be created with the following egress rules only:
  - DNS (UDP port 53) to the VPC resolver IP
  - DNS (TCP port 53) to the VPC resolver IP
  - HTTPS (TCP port 443) to the S3 prefix list
  - HTTPS (TCP port 443) to the endpoints security group

9.5. An endpoints security group must be created with a single ingress rule: HTTPS (TCP port 443) from the Flink security group.

9.6. Six VPC endpoints must be created:
  - S3 (Gateway type, attached to the private route table)
  - Kinesis Streams (Interface type)
  - CloudWatch Logs (Interface type)
  - Glue (Interface type)
  - KMS (Interface type)
  - STS (Interface type)

9.7. All interface endpoints must be placed in both private subnets, attached to the endpoints security group, and have private DNS enabled.

9.8. VPC flow logs must be optionally configurable (default: disabled in dev, recommended enabled in prod), recording all traffic types to a dedicated CloudWatch log group with its own IAM role.

---

## 10. Monitoring

10.1. Four CloudWatch log groups must be created:
  - Flink application logs: `/aws/kinesis-analytics/{project_name}-{environment}`
  - CodeBuild Build logs: `/aws/codebuild/{project_name}-{environment}-build`
  - CodeBuild Plan logs: `/aws/codebuild/{project_name}-{environment}-plan`
  - CodeBuild Apply logs: `/aws/codebuild/{project_name}-{environment}-apply`

10.2. A log stream named `flink-application` must be created within the Flink log group.

10.3. All log groups must have configurable retention (default: 1 day).

10.4. All log groups must support optional KMS encryption using the shared CMK (default: disabled in dev).

---

## 11. Configurable Parameters

The following parameters must be configurable via Terraform variables:

| Parameter | Default | Validation |
|---|---|---|
| `project_name` | `flink-data-pipeline` | Required, non-null |
| `environment` | `dev` | Must be `dev`, `staging`, or `prod` |
| `aws_region` | `us-east-1` | Must match AWS region format |
| `vpc_cidr` | `10.0.0.0/16` | Must be valid CIDR |
| `kinesis_shard_count` | `1` | 1–500 |
| `github_repo` | (required) | Must be `owner/repo` format |
| `github_branch` | `main` | Non-null |
| `file_key` | (required) | Must end with `.jar` |
| `iceberg_database_name` | `flink_pipeline` | Non-null |
| `iceberg_table_name` | `processed_data` | Non-null |
| `iceberg_catalog_name` | `glue_catalog` | Non-null |
| `log_retention_days` | `1` | >= 1 |
| `enable_cloudwatch_logs_kms` | `false` | Boolean |
| `enable_vpc_flow_logs` | `false` | Boolean |
| Bucket names (input, iceberg, jar, pipeline artifacts) | Derived from project/env | Non-null, overridable |


---

## 12. Flink Application Lifecycle and Resilience

These requirements address the Flink application lifecycle, failure recovery, and operational monitoring as described in the [AWS deep dive on Managed Flink application lifecycle (Part 1)](https://aws.amazon.com/blogs/big-data/deep-dive-into-the-amazon-managed-service-for-apache-flink-application-lifecycle-part-1/) and [Part 2](https://aws.amazon.com/blogs/big-data/deep-dive-into-the-amazon-managed-service-for-apache-flink-application-lifecycle-part-2/).

### Snapshots

12.1. Snapshots must be explicitly enabled on the Flink application configuration. Snapshots preserve application state during stop, update, and scaling operations, preventing data loss.

12.2. The application must be configured to restore from the latest snapshot by default when restarted after a stop or update.

12.3. Scheduled snapshots must be implemented for production applications (e.g., via EventBridge scheduled rule + Lambda or Step Functions calling `CreateApplicationSnapshot`). This provides recovery points in case a force-stop is required and no automatic snapshot was taken.

12.4. The snapshot schedule interval must be configurable (recommended: every 15–30 minutes for production).

### System Rollback

12.5. The system rollback feature must be enabled on the Flink application configuration. When enabled, the service automatically detects when the application fails to restart after a change or enters a fail-and-restart loop, and reverts to the previous configuration version and snapshot.

### CloudWatch Alarms

12.6. A CloudWatch alarm must be created on the `fullRestarts` metric for the Flink application, using a `DIFF` math expression to detect when the metric keeps increasing over a configurable period (recommended: 5 minutes).

12.7. The alarm must trigger an SNS notification to alert the operations team when the application is stuck in a fail-and-restart loop.

12.8. The alarm evaluation period and threshold must be configurable to avoid false positives from transient restarts (e.g., during maintenance patching).

### JAR Versioning

12.9. The JAR Bucket must retain previous versions of the application code package. S3 versioning (already enabled) satisfies this requirement. This ensures that rollback operations can access the code package associated with a previous configuration version.
