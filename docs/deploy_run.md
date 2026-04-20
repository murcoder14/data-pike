# Deploying Data Pike to AWS

This guide covers provisioning the AWS infrastructure and deploying the Flink application using Terraform. All deployments are performed via local CLI — there is no automated CI/CD pipeline.

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured with credentials that can create VPCs, S3, Kinesis, Flink, IAM, Glue, KMS, CloudWatch, and DynamoDB resources
- Java 17+, Maven 3.8+

---

## Step 1 — Configure variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars.dev
```

Edit `terraform.tfvars.dev`. The one field with no default that must be set:

```hcl
file_key = "jars/data-pike-1.0-SNAPSHOT.jar"   # S3 key the JAR will be uploaded to
```

Adjust `project_name`, `environment`, and `aws_region` as needed. All other variables have defaults. See [terraform/README.md](../terraform/README.md) for the full variable reference.

---

## Step 2 — Bootstrap the remote state backend (one-time per account/region)

```bash
cd terraform
./scripts/bootstrap-state-backend.sh terraform.tfvars.dev
```

Creates the S3 state bucket and DynamoDB lock table, then migrates local state into S3. Only needs to be done once per AWS account and region.

---

## Step 3 — Deploy storage first (so the JAR bucket exists)

```bash
cd terraform
terraform apply -input=false -auto-approve \
  -var-file=terraform.tfvars.dev \
  -target=module.storage
```

---

## Step 4 — Build and upload the JAR

```bash
cd ..
mvn clean package -DskipTests

JAR_BUCKET=$(cd terraform && terraform output -raw jar_bucket_name)
FILE_KEY=$(grep -E '^file_key\s*=' terraform/terraform.tfvars.dev | sed -E 's/^[^=]+=\s*"(.*)"\s*$/\1/' | tail -1)
JAR_FILE=$(find target -maxdepth 1 -name '*.jar' -not -name 'original-*' | head -1)

aws s3 cp "$JAR_FILE" "s3://${JAR_BUCKET}/${FILE_KEY}"
```

---

## Step 5 — Apply the full stack

```bash
cd terraform
terraform plan -input=false -var-file=terraform.tfvars.dev -out=tfplan
terraform apply -input=false tfplan
```

---

## Step 6 — Verify the Flink application is running

```bash
FLINK_APP=$(cd terraform && terraform output -raw flink_application_name)

aws kinesisanalyticsv2 describe-application \
  --application-name "$FLINK_APP" \
  --query 'ApplicationDetail.ApplicationStatus' \
  --output text
```

Expected output: `RUNNING`. If it shows `READY`, start it manually:

```bash
aws kinesisanalyticsv2 start-application \
  --application-name "$FLINK_APP" \
  --run-configuration '{}'
```

---

## Step 7 — Smoke test

Upload the bundled test files to the S3 input bucket to trigger the pipeline end-to-end:

```bash
cd terraform
INPUT_BUCKET=$(terraform output -raw input_bucket_name)
FLINK_LOG_GROUP=$(terraform output -raw flink_log_group_name)

aws s3 cp ../src/test/resources/weather_data.json s3://${INPUT_BUCKET}/smoke/weather_data.json
aws s3 cp ../src/test/resources/weather_data.xml  s3://${INPUT_BUCKET}/smoke/weather_data.xml
aws s3 cp ../src/test/resources/weather_data.csv  s3://${INPUT_BUCKET}/smoke/weather_data.csv
aws s3 cp ../src/test/resources/weather_data.tsv  s3://${INPUT_BUCKET}/smoke/weather_data.tsv

aws logs tail "$FLINK_LOG_GROUP" --since 10m --follow
```

Then query the Iceberg table in **Athena** (engine v3):

```sql
SELECT * FROM "flink_pipeline"."temperature" ORDER BY date;
```

---

## Shortcut: one-shot dev deploy + smoke

Steps 3–6 are automated by the helper script:

```bash
cd terraform
./scripts/dev-deploy-and-smoke.sh
```

---

## Deploying to additional environments (staging / prod)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars.prod
# Edit terraform.tfvars.prod — set environment = "prod" and tighten settings as needed

terraform init -reconfigure \
  -backend-config="bucket=<project_name>-tf-state" \
  -backend-config="key=<project_name>/prod/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="use_lockfile=true" \
  -backend-config="encrypt=true"

terraform plan -input=false -var-file=terraform.tfvars.prod -out=tfplan
terraform apply -input=false tfplan
```

Each environment uses an isolated state key in the same S3 backend bucket.

---

## Tearing down infrastructure

```bash
cd terraform
terraform destroy -input=false -var-file=terraform.tfvars.dev
```

For a full account-level cleanup in dev/test (use with caution — destructive):

```bash
cloud-nuke aws --region us-east-1 --dry-run   # preview first
cloud-nuke aws --region us-east-1
```

See [terraform/README.md](../terraform/README.md) for state cleanup steps after using cloud-nuke.
