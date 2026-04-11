# Terraform State Management Resources
#
# S3 bucket for remote state storage and DynamoDB table for state locking.
# These resources are referenced by the backend configuration in backend.tf.

# --- S3 State Bucket ---

resource "aws_s3_bucket" "terraform_state" {
  bucket = "flink-data-pipeline-tf-state"

  tags = {
    Name = "flink-data-pipeline-tf-state"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- DynamoDB Lock Table ---

resource "aws_dynamodb_table" "terraform_lock" {
  name         = "flink-data-pipeline-tf-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "flink-data-pipeline-tf-lock"
  }
}
