# terraform/state.tf — Line-by-Line Walkthrough

---

### Lines 1–4: Comments

```hcl
# Terraform State Management Resources
#
# S3 bucket for remote state storage and DynamoDB table for state locking.
# These resources are referenced by the backend configuration in backend.tf.
```

Just documentation. Terraform ignores lines starting with `#`. These explain that this file creates two things: a place to store Terraform's state file, and a lock to prevent two people from modifying state at the same time.

---

### Lines 8–18: The S3 State Bucket

```hcl
resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.project_name}-tf-state"

  tags = {
    Name = "${var.project_name}-tf-state"
  }

  lifecycle {
    prevent_destroy = true
  }
}
```

- `resource "aws_s3_bucket" "terraform_state"` — This tells Terraform: "Create an S3 bucket. I'll refer to it as `terraform_state` in other parts of the code."
- `bucket = "${var.project_name}-tf-state"` — The actual bucket name in AWS. `var.project_name` is a variable (e.g., `flink-data-pipeline`), so the bucket becomes something like `flink-data-pipeline-tf-state`.
- `tags` — Key-value metadata attached to the bucket. Tags don't affect behavior — they're for organization, billing, and finding resources in the AWS console.
- `lifecycle { prevent_destroy = true }` — A safety net. If someone runs `terraform destroy`, Terraform will refuse to delete this bucket and throw an error instead. You'd have to remove this line first. This protects the state file from accidental deletion.

---

### Lines 20–26: Versioning

```hcl
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}
```

- `bucket = aws_s3_bucket.terraform_state.id` — This links to the bucket created above. `.id` is the bucket's identifier that AWS assigned.
- `status = "Enabled"` — Every time a file is overwritten, S3 keeps the previous version. So if the state file gets corrupted, you can roll back to a previous version. This is critical for state files.

---

### Lines 28–36: Encryption at Rest

```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
```

- `sse_algorithm = "AES256"` — Every object stored in this bucket is automatically encrypted using AES-256 (AWS-managed keys). This is the simplest encryption option — AWS manages the keys for you. The other project buckets use KMS (customer-managed keys) for more control, but for the state bucket, AES-256 is sufficient.

---

### Lines 38–45: Block Public Access

```hcl
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

Four separate settings, all set to `true`. This is defense in depth:

- `block_public_acls` — Rejects any attempt to add a public ACL (access control list) to the bucket or its objects.
- `block_public_policy` — Rejects any bucket policy that would grant public access.
- `ignore_public_acls` — Even if a public ACL somehow exists, S3 ignores it.
- `restrict_public_buckets` — Restricts access to the bucket to only authorized users, even if the policy says otherwise.

The idea: even if someone makes a mistake in a policy, these four guards prevent the bucket from ever being publicly accessible.

---

### Lines 47–68: TLS-Only Bucket Policy

```hcl
data "aws_iam_policy_document" "terraform_state_tls_only" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}
```

This is a `data` block, not a `resource`. It doesn't create anything in AWS — it generates a JSON policy document that gets used below.

- `sid = "DenyInsecureTransport"` — A human-readable label for this policy statement.
- `effect = "Deny"` — This is a deny rule (blocks access).
- `principals { type = "*", identifiers = ["*"] }` — Applies to everyone (all users, all services).
- `actions = ["s3:*"]` — Covers every possible S3 action (read, write, delete, list, etc.).
- `resources` — Applies to the bucket itself and everything inside it (`/*`).
- `condition` — The key part: `aws:SecureTransport = false` means "if the request was NOT made over HTTPS." So this policy says: "Deny all S3 actions from anyone if they're using plain HTTP instead of HTTPS."

```hcl
resource "aws_s3_bucket_policy" "terraform_state_tls_only" {
  bucket = aws_s3_bucket.terraform_state.id
  policy = data.aws_iam_policy_document.terraform_state_tls_only.json
}
```

This attaches the policy document above to the bucket. Now the bucket enforces HTTPS for all requests.

---

### Lines 72–85: DynamoDB Lock Table

```hcl
resource "aws_dynamodb_table" "terraform_lock" {
  name         = "${var.project_name}-tf-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "${var.project_name}-tf-lock"
  }
}
```

- `name` — The table name in AWS, e.g., `flink-data-pipeline-tf-lock`.
- `billing_mode = "PAY_PER_REQUEST"` — You only pay when the table is actually used. Since it's only accessed during `terraform plan` and `terraform apply`, this is much cheaper than provisioned capacity.
- `hash_key = "LockID"` — The primary key column. Terraform writes a lock entry here when it starts an operation and deletes it when done.
- `attribute { name = "LockID", type = "S" }` — Defines the column: `LockID` is a string (`S`).

How locking works: when you run `terraform apply`, Terraform writes a row to this table with a unique lock ID. If someone else tries to run `terraform apply` at the same time, they'll see the lock exists and wait (or fail). When the first operation finishes, the lock row is deleted.

---

## Summary

Two resources (bucket + table), plus security hardening on the bucket. This same S3 security pattern (versioning → encryption → public access block → TLS policy) repeats in every other module.
