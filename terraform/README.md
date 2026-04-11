# Flink Data Pipeline — Terraform Infrastructure

This directory contains the Terraform configuration for deploying the Flink Data Pipeline infrastructure on AWS.

## Architecture Overview

The infrastructure provisions a streaming data pipeline that ingests files from S3, routes notifications through EventBridge and Kinesis, processes them via Apache Flink on Managed Service for Flink, writes output to Apache Iceberg tables, and logs transactions to RDS PostgreSQL. A CI/CD pipeline automates build, plan, approval, and deployment.

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
└── modules/
    ├── monitoring/             # CloudWatch log groups (Flink, CodeBuild stages)
    ├── storage/                # KMS CMK, Secrets Manager, S3 buckets (Input, Iceberg, JAR)
    ├── networking/             # VPC, private subnets, security groups, VPC endpoints
    ├── kinesis/                # Kinesis Data Stream, EventBridge rule/target
    ├── rds/                    # RDS PostgreSQL, RDS Proxy, parameter group
    ├── flink/                  # Managed Flink application, execution IAM role
    └── cicd/                   # CodeBuild projects, CodePipeline, CI/CD IAM roles
```

## Prerequisites

- **Terraform** >= 1.5.0, < 2.0.0
- **AWS CLI** configured with credentials that have sufficient permissions
- **AWS Account** with access to create the resources listed above
- **GitHub repository** containing the Flink application source code

## Deployment Steps

### 1. Bootstrap the State Backend

The Terraform state bucket and DynamoDB lock table are defined in `state.tf` but are also referenced by `backend.tf`. You need to bootstrap them first.

Comment out the backend block temporarily:

```bash
# In backend.tf, comment out the entire terraform { backend "s3" { ... } } block
```

Then create the state resources:

```bash
cd terraform
terraform init
terraform apply -target=aws_s3_bucket.terraform_state \
                -target=aws_s3_bucket_versioning.terraform_state \
                -target=aws_s3_bucket_server_side_encryption_configuration.terraform_state \
                -target=aws_s3_bucket_public_access_block.terraform_state \
                -target=aws_dynamodb_table.terraform_lock
```

Once the state bucket and lock table exist, uncomment the backend block and migrate:

```bash
terraform init -migrate-state
```

### 2. Configure Variables

Copy the example file and fill in your values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
environment         = "dev"
aws_region          = "us-east-1"
vpc_cidr            = "10.0.0.0/16"
db_instance_class   = "db.r6g.large"
kinesis_shard_count = 1
github_repo         = "your-org/your-repo"
github_branch       = "main"
file_key            = "jars/my-app-latest.jar"
```

| Variable | Required | Default | Description |
|---|---|---|---|
| `environment` | No | `dev` | Deployment environment (`dev`, `staging`, `prod`) |
| `aws_region` | No | `us-east-1` | AWS region for all resources |
| `vpc_cidr` | No | `10.0.0.0/16` | CIDR block for the VPC |
| `db_instance_class` | No | `db.r6g.large` | RDS instance class (`db.r6g.*` or `db.r7g.*`) |
| `kinesis_shard_count` | No | `1` | Number of Kinesis stream shards (1–500) |
| `github_repo` | **Yes** | — | GitHub repository in `owner/repo` format |
| `github_branch` | No | `main` | Branch that triggers the CI/CD pipeline |
| `file_key` | **Yes** | — | S3 key for the FAT JAR (must end in `.jar`) |

### 3. Plan and Apply

```bash
terraform plan -out=tfplan
```

Review the plan output carefully, then apply:

```bash
terraform apply tfplan
```

### 4. Post-Deployment Steps

After `terraform apply` completes:

1. **Confirm the CodeConnections connection.** The GitHub connection is created in `PENDING` status. Go to the AWS Console → Developer Tools → Settings → Connections, find the connection, and complete the GitHub authorization handshake.

2. **Run the SQL migration.** Connect to the RDS instance via the RDS Proxy endpoint and execute the schema migration:

   ```bash
   psql -h <rds_proxy_endpoint> -U flink_admin -d flink_transactions -f ../sql/V1__create_transactions_table.sql
   ```

   The proxy endpoint is available in the Terraform output `rds_proxy_endpoint`.

3. **Upload the initial FAT JAR.** Build the Java application and upload the JAR to the JAR bucket:

   ```bash
   mvn clean package -DskipTests
   aws s3 cp target/data-pike-1.0-SNAPSHOT.jar s3://<jar_bucket_name>/jars/my-app-initial.jar
   ```

   Then update `file_key` in your `terraform.tfvars` to match and re-apply.

4. **Verify the Flink application starts.** Check the Managed Service for Apache Flink console to confirm the application transitions to `RUNNING` status.

## Deploying to Multiple Environments

Use separate `.tfvars` files per environment:

```bash
# Dev
terraform plan -var-file=environments/dev.tfvars -out=tfplan
terraform apply tfplan

# Staging
terraform plan -var-file=environments/staging.tfvars -out=tfplan
terraform apply tfplan

# Production
terraform plan -var-file=environments/prod.tfvars -out=tfplan
terraform apply tfplan
```

Each environment should use its own S3 backend key or workspace to isolate state.

## Destroying Infrastructure

To tear down all resources:

```bash
# Deletion protection is enabled on RDS — disable it first
aws rds modify-db-instance \
  --db-instance-identifier flink-data-pipeline-<environment> \
  --no-deletion-protection

terraform destroy
```

> **Warning:** The state bucket has `prevent_destroy = true`. To remove it, you must first remove that lifecycle rule from `state.tf` and re-apply, then destroy.

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
terraform output rds_proxy_endpoint       # JDBC connection endpoint
terraform output flink_application_name   # Flink app name in the console
terraform output kinesis_stream_name      # Kinesis stream to monitor
terraform output input_bucket_name        # Drop files here to trigger processing
terraform output jar_bucket_name          # FAT JAR upload destination
terraform output codepipeline_name        # CI/CD pipeline name
```
