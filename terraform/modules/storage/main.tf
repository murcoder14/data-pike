# Storage Module - KMS, S3 Buckets
#
# KMS Customer Managed Key and S3 buckets (Input, Iceberg, JAR).

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "kms_encryption" {
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
}

# =============================================================================
# KMS Customer Managed Key
# =============================================================================

resource "aws_kms_key" "encryption" {
  description             = "CMK for Flink Data Pipeline encryption at rest"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_encryption.json

  tags = {
    Name = "${var.project_name}-${var.environment}-cmk"
  }
}

resource "aws_kms_alias" "encryption" {
  name          = "alias/${var.project_name}-${var.environment}"
  target_key_id = aws_kms_key.encryption.key_id
}

# =============================================================================
# Input Bucket
# =============================================================================

resource "aws_s3_bucket" "input" {
  bucket = var.input_bucket_name

  tags = {
    Name = var.input_bucket_name
  }
}

resource "aws_s3_bucket_versioning" "input" {
  bucket = aws_s3_bucket.input.id

  versioning_configuration {
    status = "Enabled"
  }
}

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

resource "aws_s3_bucket_public_access_block" "input" {
  bucket = aws_s3_bucket.input.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "input_tls_only" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.input.arn,
      "${aws_s3_bucket.input.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "input_tls_only" {
  bucket = aws_s3_bucket.input.id
  policy = data.aws_iam_policy_document.input_tls_only.json
}

# EventBridge notifications on the Input Bucket (Requirement 1.2)
resource "aws_s3_bucket_notification" "input" {
  bucket      = aws_s3_bucket.input.id
  eventbridge = true
}

# =============================================================================
# Iceberg Bucket
# =============================================================================

resource "aws_s3_bucket" "iceberg" {
  bucket = var.iceberg_bucket_name

  tags = {
    Name = var.iceberg_bucket_name
  }
}

resource "aws_s3_bucket_versioning" "iceberg" {
  bucket = aws_s3_bucket.iceberg.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "iceberg" {
  bucket = aws_s3_bucket.iceberg.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.encryption.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "iceberg" {
  bucket = aws_s3_bucket.iceberg.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "iceberg_tls_only" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.iceberg.arn,
      "${aws_s3_bucket.iceberg.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "iceberg_tls_only" {
  bucket = aws_s3_bucket.iceberg.id
  policy = data.aws_iam_policy_document.iceberg_tls_only.json
}

# =============================================================================
# JAR Bucket
# =============================================================================

resource "aws_s3_bucket" "jar" {
  bucket = var.jar_bucket_name

  tags = {
    Name = var.jar_bucket_name
  }
}

resource "aws_s3_bucket_versioning" "jar" {
  bucket = aws_s3_bucket.jar.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "jar" {
  bucket = aws_s3_bucket.jar.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.encryption.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "jar" {
  bucket = aws_s3_bucket.jar.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "jar_tls_only" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.jar.arn,
      "${aws_s3_bucket.jar.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "jar_tls_only" {
  bucket = aws_s3_bucket.jar.id
  policy = data.aws_iam_policy_document.jar_tls_only.json
}

# =============================================================================
# Glue Catalog Database and Iceberg Table
# =============================================================================

resource "aws_glue_catalog_database" "iceberg" {
  name = var.iceberg_database_name

  description = "Glue Catalog database for Flink Data Pipeline Iceberg tables"

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.iceberg_database_name}"
    Environment = var.environment
    Application = var.project_name
  }
}

resource "aws_glue_catalog_table" "iceberg" {
  database_name = aws_glue_catalog_database.iceberg.name
  name          = var.iceberg_table_name
  description   = "Iceberg temperature summary table (min/max city temperatures by date)"

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "format-version" = "2"
  }

  open_table_format_input {
    iceberg_input {
      metadata_operation = "CREATE"
      version            = "2"
    }
  }

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
}
