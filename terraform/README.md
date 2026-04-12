# Flink Data Pipeline — Terraform Infrastructure

This directory contains the Terraform configuration for deploying the Flink Data Pipeline infrastructure on AWS.

## Architecture Overview

The infrastructure provisions a streaming data pipeline that ingests files from S3, routes notifications through EventBridge and Kinesis, processes them via Apache Flink on Managed Service for Flink, and writes output to Apache Iceberg tables. A CI/CD pipeline automates build, plan, approval, and deployment.

## Module Structure

```
terraform/
├── backend.tf                  # S3 remote state backend configuration
├── main.tf                     # Root module — wires all child modules together
├── outputs.tf                  # Root outputs
├── providers.tf                # Provider and version constraints
├── state.tf                    # State bucket and DynamoDB lock table
├── variables.tf                # Root input variables
├── terraform.tfvars.example    # Example variable values
├── terraform.tfvars.dev        # Dev environment variable values
├── scripts/                    # Helper scripts (bootstrap, deploy, smoke test)
└── modules/
    ├── monitoring/             # CloudWatch log groups (Flink, CodeBuild stages)
    ├── storage/                # KMS CMK, S3 buckets (Input, Iceberg, JAR), Glue Catalog
    ├── networking/             # VPC, private subnets, security groups, VPC endpoints
    ├── kinesis/                # Kinesis Data Stream, EventBridge rule/target
    ├── flink/                  # Managed Flink application, execution IAM role
    └── cicd/                   # CodeBuild projects, CodePipeline, CI/CD IAM roles
```

## Prerequisites

- **Terraform** >= 1.5.0, < 2.0.0
- **AWS CLI** configured with credentials that have sufficient permissions
- **AWS Account** with access to create the resources listed above
- **GitHub repository** containing the Flink application source code

## Deployment Steps

The commands in this README are the source of truth for deployment and verification.

Always run Terraform commands with explicit variable files for this project. Do not run `terraform apply` without `-var-file=terraform.tfvars.dev` (or the environment-specific equivalent), because required root variables have no defaults.

### 1. Bootstrap the State Backend (One-Time Setup)

Terraform needs an S3 bucket and DynamoDB table to store its state remotely. But those resources don't exist yet, and the backend config in `backend.tf` references them. This creates a chicken-and-egg problem.

The solution: temporarily use local state to create the backend resources, then migrate the local state into the newly created S3 backend.

You only need to do this once per AWS account/region.

```bash
cd terraform
```

Step 1a — Clean up any previous state and disable the S3 backend temporarily:

```bash
rm -rf .terraform .terraform.tfstate
mv backend.tf backend.tf.disabled
```

Step 1b — Initialize Terraform with local state (no backend):

```bash
terraform init -reconfigure -backend=false -input=false
```

Step 1c — Create only the state bucket and lock table in AWS:

```bash
terraform apply -input=false -auto-approve -var-file=terraform.tfvars.dev \
  -target=aws_s3_bucket.terraform_state \
  -target=aws_s3_bucket_versioning.terraform_state \
  -target=aws_s3_bucket_server_side_encryption_configuration.terraform_state \
  -target=aws_s3_bucket_public_access_block.terraform_state \
  -target=aws_dynamodb_table.terraform_lock
```

Step 1d — Re-enable the backend and migrate local state into S3:

```bash
mv backend.tf.disabled backend.tf

# Extract project_name from your tfvars to build the bucket name
PROJECT_NAME=$(grep -E '^project_name\s*=' terraform.tfvars.dev \
  | sed -E 's/^[^=]+=\s*"(.*)"\s*$/\1/' | tail -1)

terraform init -migrate-state -force-copy -input=false \
  -backend-config="bucket=${PROJECT_NAME}-tf-state" \
  -backend-config="key=${PROJECT_NAME}/dev/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="use_lockfile=true" \
  -backend-config="encrypt=true"
```

Step 1e — Verify everything works with the remote backend:

```bash
terraform plan -input=false -var-file=terraform.tfvars.dev
```

From this point on, all state is stored in S3 with DynamoDB locking. You never need to repeat this step.

### 2. Configure Variables

Use environment-specific tfvars files. For dev, edit `terraform.tfvars.dev` (or copy from `terraform.tfvars.example`):

```bash
cp terraform.tfvars.example terraform.tfvars.dev
```

Edit `terraform.tfvars.dev`:

```hcl
project_name        = "flink-data-pipeline"
environment         = "dev"
aws_region          = "us-east-1"
vpc_cidr            = "10.0.0.0/16"
kinesis_shard_count = 1
github_repo         = "your-org/your-repo"
github_branch       = "main"
file_key            = "jars/my-app-latest.jar"
```

| Variable | Required | Default | Description |
|---|---|---|---|
| `project_name` | No | `flink-data-pipeline` | Prefix for all resource names |
| `environment` | No | `dev` | Deployment environment (`dev`, `staging`, `prod`) |
| `aws_region` | No | `us-east-1` | AWS region for all resources |
| `vpc_cidr` | No | `10.0.0.0/16` | CIDR block for the VPC |
| `kinesis_shard_count` | No | `1` | Number of Kinesis stream shards (1–500) |
| `kinesis_stream_name` | No | `${project_name}-${environment}` | Custom Kinesis stream name |
| `input_bucket_name` | No | `${project_name}-${environment}-input` | Custom S3 Input Bucket name |
| `iceberg_bucket_name` | No | `${project_name}-${environment}-iceberg` | Custom S3 Iceberg Bucket name |
| `jar_bucket_name` | No | `${project_name}-${environment}-jar` | Custom S3 JAR Bucket name |
| `pipeline_artifacts_bucket_name` | No | `${project_name}-${environment}-pipeline-artifacts` | Custom pipeline artifacts bucket name |
| `iceberg_database_name` | No | `flink_pipeline` | Glue Catalog database name |
| `iceberg_table_name` | No | `processed_data` | Iceberg table name |
| `iceberg_catalog_name` | No | `glue_catalog` | Iceberg catalog name for Flink |
| `log_retention_days` | No | `1` | CloudWatch log retention in days |
| `enable_cloudwatch_logs_kms` | No | `false` | Enable KMS encryption on CloudWatch log groups |
| `enable_vpc_flow_logs` | No | `false` | Enable VPC flow logs (recommended true in prod) |
| `github_repo` | **Yes** | — | GitHub repository in `owner/repo` format |
| `github_branch` | No | `main` | Branch that triggers the CI/CD pipeline |
| `file_key` | **Yes** | — | S3 key for the FAT JAR (must end in `.jar`) |

### 3. Plan and Apply (Dev, Staged)

Because the Flink application creation validates that the JAR already exists in S3,
deploy dev in two phases.

Phase A: create storage first so the JAR bucket exists.

```bash
terraform apply -input=false -auto-approve -var-file=terraform.tfvars.dev -target=module.storage
```

Build and upload the JAR to the configured `file_key`:

```bash
cd ..
mvn clean package -DskipTests
cd terraform
JAR_FILE=$(find ../target -maxdepth 1 -name '*.jar' -not -name 'original-*' | head -1)
FILE_KEY=$(grep -E '^file_key\s*=' terraform.tfvars.dev | sed -E 's/^[^=]+=\s*"(.*)"\s*$/\1/' | tail -1)
aws s3 cp "$JAR_FILE" "s3://$(terraform output -raw jar_bucket_name)/$FILE_KEY"
```

Phase B: apply the full stack.

```bash
terraform plan -input=false -var-file=terraform.tfvars.dev -out=tfplan
```

Review the plan output carefully, then apply:

```bash
terraform apply -input=false tfplan
```

### 4. Post-Deployment Checks

After `terraform apply` completes:

1. **Confirm the CodeConnections connection.** The GitHub connection is created in `PENDING` status. Go to the AWS Console → Developer Tools → Settings → Connections, find the connection, and complete the GitHub authorization handshake.

2. **Verify the Flink application starts.** Check the Managed Service for Apache Flink console to confirm the application transitions to `RUNNING` status.

## Deploying to Multiple Environments

Create a `.tfvars` file per environment (e.g., `terraform.tfvars.dev`, `terraform.tfvars.staging`, `terraform.tfvars.prod`):

```bash
# Dev
terraform plan -input=false -var-file=terraform.tfvars.dev -out=tfplan
terraform apply -input=false tfplan

# Staging
terraform plan -input=false -var-file=terraform.tfvars.staging -out=tfplan
terraform apply -input=false tfplan

# Production
terraform plan -input=false -var-file=terraform.tfvars.prod -out=tfplan
terraform apply -input=false tfplan
```

Each environment should use its own S3 backend key or workspace to isolate state.

Example backend reconfigure per environment:

```bash
terraform init -reconfigure \
  -backend-config="bucket=<project_name>-tf-state" \
  -backend-config="key=<project_name>/dev/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="use_lockfile=true" \
  -backend-config="encrypt=true"
```

## Dev Smoke Test (JSON + XML)

After deploying dev infrastructure and confirming the Flink app is RUNNING:

```bash
cd terraform
INPUT_BUCKET=$(terraform output -raw input_bucket_name)
FLINK_APP_NAME=$(terraform output -raw flink_application_name)
FLINK_LOG_GROUP=$(terraform output -raw flink_log_group_name)
GLUE_DB=$(terraform output -raw glue_database_name)
GLUE_TABLE=$(terraform output -raw glue_table_name)

aws s3 cp ../src/test/resources/weather_data.json s3://${INPUT_BUCKET}/smoke/weather_data.json
aws s3 cp ../src/test/resources/weather_data.xml s3://${INPUT_BUCKET}/smoke/weather_data.xml

aws kinesisanalyticsv2 describe-application --application-name "$FLINK_APP_NAME" --query 'ApplicationDetail.ApplicationStatus' --output text
aws logs tail "$FLINK_LOG_GROUP" --since 20m --follow
```

This uploads:
- `src/test/resources/weather_data.json`
- `src/test/resources/weather_data.xml`

Then query the Iceberg table using Athena engine 3:

```sql
SELECT *
FROM "<glue_database_name>"."<glue_table_name>"
ORDER BY date;
```

## Destroying Infrastructure

### Option 1: Terraform Destroy

```bash
terraform destroy -input=false -var-file=terraform.tfvars.dev
```

This works for most cases but can sometimes fail on resources with dependencies, deletion protection, or eventual consistency issues (e.g., Flink applications with pending tag cleanup).

### Option 2: cloud-nuke (Recommended for Full Cleanup)

When `terraform destroy` doesn't fully clean up, use [cloud-nuke](https://github.com/gruntwork-io/cloud-nuke) to delete all remaining AWS resources.

Install:

```bash
brew install cloud-nuke    # macOS/Linux
# or download from https://github.com/gruntwork-io/cloud-nuke/releases
```

Preview what would be deleted:

```bash
cloud-nuke aws --region us-east-1 --dry-run
```

Delete all resources in the region:

```bash
cloud-nuke aws --region us-east-1
```

Or target specific resource types:

```bash
cloud-nuke aws --region us-east-1 \
  --resource-type kinesis-stream \
  --resource-type s3 \
  --resource-type vpc \
  --resource-type kinesisanalyticsv2
```

> **Warning:** cloud-nuke is destructive. Only use it in dev/test accounts, never in production.

### Cleaning Up Terraform State After cloud-nuke

After using cloud-nuke, Terraform state will be out of sync with AWS (state references resources that no longer exist). You must reset the state before redeploying:

```bash
# Option A: Delete local state artifacts (if using local backend for bootstrap)
rm -f terraform.tfstate terraform.tfstate.backup .terraform.tfstate
rm -rf .terraform

# Option B: If using S3 backend, empty and delete the state bucket
aws s3 rm s3://<project_name>-tf-state --recursive
aws s3 rb s3://<project_name>-tf-state
aws dynamodb delete-table --table-name <project_name>-tf-lock

# Re-initialize in local mode for bootstrap-style operations
terraform init -reconfigure -backend=false
```

Also clean up any local plan files:

```bash
rm -f tfplan
```

After cleanup, you can redeploy from scratch by following the deployment steps from Step 1.

## CI/CD Pipeline Flow

Once the CodeConnections connection is confirmed and the pipeline triggers:

1. **Source** — Pulls code from GitHub on push to the configured branch
2. **Build** — Compiles the Java application with Maven, produces a FAT JAR, uploads to the JAR bucket
3. **Plan** — Runs `terraform plan` detecting the `file_key` variable change
4. **Approval** — Pauses for manual human review of the plan
5. **Apply** — Runs `terraform apply` with the approved plan, which triggers an `UpdateApplication` on the Flink app

## Useful Outputs

After applying, key outputs include:

```bash
terraform output flink_application_name   # Flink app name in the console
terraform output kinesis_stream_name      # Kinesis stream to monitor
terraform output input_bucket_name        # Drop files here to trigger processing
terraform output iceberg_bucket_name      # Iceberg table storage
terraform output jar_bucket_name          # FAT JAR upload destination
terraform output iceberg_warehouse_path   # Iceberg warehouse S3 path
terraform output glue_database_name       # Glue Catalog database
terraform output codepipeline_name        # CI/CD pipeline name
```
