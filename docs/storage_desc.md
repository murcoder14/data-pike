# storage/main.tf — Line-by-Line Walkthrough

---

### Lines 1–3: Comments

```hcl
# Storage Module - KMS, S3 Buckets
#
# KMS Customer Managed Key and S3 buckets (Input, Iceberg, JAR).
```

This module creates the encryption key and all the data storage buckets.

---

### Lines 5–6: Data Sources

```hcl
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
```

These are data sources — they don't create anything. They look up information about the current AWS environment:
- `aws_caller_identity` — fetches the AWS account ID of whoever is running Terraform
- `aws_region` — fetches the current region (e.g., `us-east-1`)

These values are used later in the KMS key policy to scope permissions to this specific account and region.

---

### Lines 8–47: KMS Key Policy Document

```hcl
data "aws_iam_policy_document" "kms_encryption" {
```

This generates a JSON policy that will be attached to the KMS key. It has two statements:

#### Statement 1: Root Account Access (lines 9–21)

```hcl
  statement {
    sid    = "EnableRootPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }
```

- Grants the AWS account root user full control (`kms:*`) over this key.
- This is standard practice for KMS keys. Without this statement, the key could become unmanageable — if the creator's IAM user is deleted, nobody could administer the key.
- `root` here doesn't mean "the root login" — it means "any IAM principal in this account that has the appropriate IAM permissions." The KMS key policy and IAM policies work together.

#### Statement 2: CloudWatch Logs Access (lines 23–46)

```hcl
  statement {
    sid    = "AllowCloudWatchLogsUse"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.region}.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }
```

- Allows the CloudWatch Logs service to use this key for encrypting/decrypting log data.
- The `condition` restricts this: CloudWatch can only use the key when the encryption context matches log groups in this account and region. This prevents other accounts or services from using the key.
- `ReEncrypt*` and `GenerateDataKey*` use wildcards to cover variants like `ReEncryptFrom`, `ReEncryptTo`, `GenerateDataKeyWithoutPlaintext`, etc.

---

### Lines 52–62: KMS Key Resource

```hcl
resource "aws_kms_key" "encryption" {
  description             = "CMK for Flink Data Pipeline encryption at rest"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_encryption.json

  tags = {
    Name = "${var.project_name}-${var.environment}-cmk"
  }
}
```

- `deletion_window_in_days = 30` — If someone deletes this key, AWS waits 30 days before actually destroying it. During that window you can cancel the deletion. This is a safety net because deleting a KMS key makes all data encrypted with it permanently unreadable.
- `enable_key_rotation = true` — AWS automatically creates a new backing key every year. Old data stays readable (AWS keeps old key material), but new data uses the new key. This is a security best practice.
- `policy` — Attaches the policy document we defined above.

### Lines 64–67: KMS Alias

```hcl
resource "aws_kms_alias" "encryption" {
  name          = "alias/${var.project_name}-${var.environment}"
  target_key_id = aws_kms_key.encryption.key_id
}
```

- An alias is a friendly name for the key. Instead of referencing `arn:aws:kms:us-east-1:123456:key/abc-123-def`, other modules can use `alias/flink-data-pipeline-dev`.
- `target_key_id` — Points the alias at the key we just created.

---

### Lines 72–130: Input Bucket

This is the bucket where you upload files to be processed. You already know the S3 security pattern from `state.tf`, so I'll focus on what's different.

```hcl
resource "aws_s3_bucket" "input" {
  bucket = var.input_bucket_name
  ...
}
```

The bucket name comes from a variable instead of being constructed inline. The root module sets this to `{project}-{env}-input`.

#### Encryption (lines 88–97) — Different from state.tf

```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "input" {
  bucket = aws_s3_bucket.input.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.encryption.arn
    }
    bucket_key_enabled = true
  }
}
```

- `sse_algorithm = "aws:kms"` — Uses KMS encryption instead of AES-256. This gives you more control: you can audit who used the key, rotate it, and restrict access through key policies.
- `kms_master_key_id = aws_kms_key.encryption.arn` — Uses the CMK we created above, not an AWS-managed key.
- `bucket_key_enabled = true` — An optimization. Without this, every object upload makes a separate KMS API call. With bucket keys, S3 generates a short-lived key from the CMK and reuses it for multiple objects. Same security, fewer API calls, lower cost.

#### Versioning, Public Access Block, TLS Policy

Same pattern as `state.tf` — identical structure, just referencing `aws_s3_bucket.input` instead of `aws_s3_bucket.terraform_state`.

#### EventBridge Notification (lines 128–131) — New

```hcl
resource "aws_s3_bucket_notification" "input" {
  bucket      = aws_s3_bucket.input.id
  eventbridge = true
}
```

- `eventbridge = true` — Tells S3 to send events to EventBridge whenever objects are created, deleted, etc. This is the trigger for the entire pipeline. Without this line, uploading a file would do nothing.
- Only the Input Bucket has this. The Iceberg and JAR buckets don't need it because nothing needs to react to files landing there.

---

### Lines 136–199: Iceberg Bucket

```hcl
resource "aws_s3_bucket" "iceberg" {
  bucket = var.iceberg_bucket_name
  ...
}
```

Identical security pattern to the Input Bucket (KMS encryption, versioning, public access block, TLS policy). No EventBridge notification — nothing needs to react when Flink writes results here.

This bucket stores the actual data files that make up the Iceberg table (Parquet files, metadata files, etc.).

---

### Lines 204–267: JAR Bucket

```hcl
resource "aws_s3_bucket" "jar" {
  bucket = var.jar_bucket_name
  ...
}
```

Again, identical security pattern. This bucket stores the compiled application code (FAT JAR). The CI/CD pipeline uploads new JARs here, and the Flink application loads its code from here at startup.

---

### Lines 272–289: Glue Catalog Database

```hcl
resource "aws_glue_catalog_database" "iceberg" {
  name = var.iceberg_database_name

  description = "Glue Catalog database for Flink Data Pipeline Iceberg tables"

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.iceberg_database_name}"
    Environment = var.environment
    Application = var.project_name
  }
}
```

- AWS Glue Catalog is a metadata service — it stores information about your data (what tables exist, what columns they have, where the data files live) but not the data itself.
- A Glue database is like a schema in a traditional database — it's a container that groups related tables together.
- `name = var.iceberg_database_name` — defaults to `flink_pipeline`.

---

### Lines 291–340: Glue Catalog Table

```hcl
resource "aws_glue_catalog_table" "iceberg" {
  database_name = aws_glue_catalog_database.iceberg.name
  name          = var.iceberg_table_name
  description   = "Iceberg temperature summary table (min/max city temperatures by date)"

  table_type = "EXTERNAL_TABLE"
```

- `database_name` — Places this table inside the database we just created.
- `table_type = "EXTERNAL_TABLE"` — The data lives in S3, not inside Glue itself. Glue just knows where to find it.

```hcl
  parameters = {
    "format-version" = "2"
  }

  open_table_format_input {
    iceberg_input {
      metadata_operation = "CREATE"
      version            = "2"
    }
  }
```

- `format-version = "2"` — Uses Iceberg table format v2, which supports features like row-level deletes and merge-on-read.
- `metadata_operation = "CREATE"` — Tells Glue to initialize the Iceberg metadata when the table is first created.

```hcl
  storage_descriptor {
    location = "s3://${aws_s3_bucket.iceberg.id}/warehouse/${var.iceberg_database_name}/${var.iceberg_table_name}"

    columns {
      name = "date"
      type = "string"
    }

    columns {
      name = "max_temp"
      type = "int"
    }

    columns {
      name = "max_temp_city"
      type = "string"
    }

    columns {
      name = "min_temp"
      type = "int"
    }

    columns {
      name = "min_temp_city"
      type = "string"
    }
  }
```

- `location` — The S3 path where Iceberg stores its data files. Points into the Iceberg bucket under a `warehouse/` prefix.
- `columns` — Defines the table schema. Five columns:
  - `date` (string) — the observation date
  - `max_temp` (int) — highest temperature recorded that day
  - `max_temp_city` (string) — which city had the highest temperature
  - `min_temp` (int) — lowest temperature recorded that day
  - `min_temp_city` (string) — which city had the lowest temperature

This is the output of the entire pipeline — weather observations go in, temperature summaries come out.

---

### Summary

This module creates:
- 1 KMS key (shared encryption for everything) + 1 alias
- 3 S3 buckets (Input, Iceberg, JAR) each with identical security hardening
- 1 Glue database + 1 Glue table (metadata catalog for the output data)

The key new concepts compared to `state.tf`:
- KMS customer-managed keys vs. AES-256
- Bucket keys for cost optimization
- EventBridge notifications (only on the Input Bucket)
- Glue Catalog for table metadata
- Data sources (`aws_caller_identity`, `aws_region`) for looking up account info

---

## Q&A

### Q: Are we creating a Customer Managed Key in this module? If yes, what is the motivation?

Yes. The `aws_kms_key "encryption"` resource on line 52 creates a Customer Managed Key (CMK). Here's why, compared to the alternatives:

AWS gives you three encryption options for S3:
- SSE-S3 (AES-256) — AWS owns and manages the key entirely. You can't control who uses it, audit its usage, or revoke access. This is what `state.tf` uses.
- AWS Managed KMS Key — AWS creates a KMS key for you per service. You get CloudTrail audit logs but can't customize the key policy or share it across services.
- Customer Managed Key (CMK) — You create and own the key. Full control.

This project uses a CMK because:

1. One key encrypts everything — S3 buckets, Kinesis stream, and optionally CloudWatch logs all share the same CMK. With AWS-managed keys, each service gets its own key, and you can't use a Kinesis key to decrypt S3 data or vice versa.

2. Access control through key policy — the key policy defines exactly who can use the key. If you want to revoke Flink's ability to read encrypted data, you remove it from the key policy. With AWS-managed keys, anyone with S3 permissions can decrypt.

3. Audit trail — every use of a CMK (encrypt, decrypt, generate data key) is logged in CloudTrail. You can see exactly which service, role, and API call used the key and when.

4. Automatic rotation — `enable_key_rotation = true` rotates the backing key material annually. Old data stays readable, new data uses the new key. AWS-managed keys also rotate, but you can't control the schedule.

5. Deletion protection — `deletion_window_in_days = 30` gives a 30-day recovery window. Deleting a KMS key makes all data encrypted with it permanently unreadable, so this buffer is critical.

The tradeoff is cost — CMKs cost $1/month plus per-API-call charges, while AES-256 is free. That's why `state.tf` uses AES-256 for the state bucket (low-risk, low-volume) while the data pipeline buckets use the CMK (higher security requirements).


### Q: What does `sid = "AllowCloudWatchLogsUse"` mean?

`sid` stands for Statement ID. It's just a human-readable label for that specific policy statement — like a comment, but one that shows up in the actual JSON policy in AWS.

It has no effect on what the policy does. AWS doesn't use it for evaluation. It's there so when you're reading a policy with 5 or 10 statements, you can quickly tell which one does what. In this case, `"AllowCloudWatchLogsUse"` tells you "this statement is the one that lets CloudWatch Logs use the key."

You could name it `"banana"` and it would work the same way — but that wouldn't help anyone reading it.

### Q: Which part of the block tells "the CloudWatch Logs service to use this key for encrypting/decrypting log data"?

Two parts work together:

```hcl
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.region}.amazonaws.com"]
    }
```

This is the "who" — it says the CloudWatch Logs service (e.g., `logs.us-east-1.amazonaws.com`) is the principal being granted access.

```hcl
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
```

This is the "what" — the specific KMS operations CloudWatch is allowed to perform. `Encrypt` and `GenerateDataKey*` for writing encrypted logs, `Decrypt` for reading them back.

Then the `condition` block narrows the "when" — CloudWatch can only use the key when the request is associated with a log group in this specific account and region. Without that condition, any CloudWatch Logs service in any account could potentially use the key.

So: `principals` picks the service, `actions` picks the operations, `condition` restricts the scope.
