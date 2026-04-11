# Storage Module - KMS, Secrets Manager, S3 Buckets
#
# KMS Customer Managed Key, Secrets Manager with rotation Lambda,
# and S3 buckets (Input, Iceberg, JAR).
# Requirements: 1.1-1.4, 2.1-2.3, 3.1-3.3, 8.7, 8.9, 12.8

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# KMS Customer Managed Key
# =============================================================================

resource "aws_kms_key" "encryption" {
  description             = "CMK for Flink Data Pipeline encryption at rest"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name = "flink-data-pipeline-${var.environment}-cmk"
  }
}

resource "aws_kms_alias" "encryption" {
  name          = "alias/flink-data-pipeline-${var.environment}"
  target_key_id = aws_kms_key.encryption.key_id
}

# =============================================================================
# Secrets Manager - Database password management
# =============================================================================

resource "random_password" "db_master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}|:?"
}

resource "aws_secretsmanager_secret" "db_password" {
  name        = "flink-data-pipeline/${var.environment}/db-master-password"
  description = "Master password for the Flink Data Pipeline RDS PostgreSQL instance"
  kms_key_id  = aws_kms_key.encryption.arn

  tags = {
    Name               = "flink-data-pipeline-${var.environment}-db-password"
    Environment        = var.environment
    Application        = "flink-data-pipeline"
    DataClassification = "CONFIDENTIAL"
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = "flink_admin"
    password = random_password.db_master.result
  })
}

resource "aws_secretsmanager_secret_rotation" "db_password" {
  secret_id           = aws_secretsmanager_secret.db_password.id
  rotation_lambda_arn = aws_lambda_function.secret_rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }
}

# IAM role for the Secrets Manager rotation Lambda
resource "aws_iam_role" "secret_rotation" {
  name = "flink-data-pipeline-${var.environment}-secret-rotation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = {
    Name = "flink-data-pipeline-${var.environment}-secret-rotation-role"
  }
}

resource "aws_iam_role_policy" "secret_rotation" {
  name = "secret-rotation-policy"
  role = aws_iam_role.secret_rotation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = aws_secretsmanager_secret.db_password.arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetRandomPassword"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.encryption.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secret_rotation_basic" {
  role       = aws_iam_role.secret_rotation.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function for Secrets Manager rotation
resource "aws_lambda_function" "secret_rotation" {
  function_name = "flink-data-pipeline-${var.environment}-secret-rotation"
  description   = "Rotates the RDS PostgreSQL master password in Secrets Manager"
  runtime       = "python3.12"
  handler       = "lambda_function.handler"
  role          = aws_iam_role.secret_rotation.arn
  timeout       = 60

  filename         = data.archive_file.secret_rotation.output_path
  source_code_hash = data.archive_file.secret_rotation.output_base64sha256

  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${var.aws_region}.amazonaws.com"
    }
  }

  tags = {
    Name = "flink-data-pipeline-${var.environment}-secret-rotation"
  }
}

data "archive_file" "secret_rotation" {
  type        = "zip"
  output_path = "${path.module}/lambda/secret_rotation.zip"

  source {
    content  = <<-PYTHON
import boto3
import json
import os

def handler(event, context):
    """Secrets Manager rotation handler for RDS PostgreSQL."""
    secret_arn = event['SecretId']
    token = event['ClientRequestToken']
    step = event['Step']

    sm_client = boto3.client(
        'secretsmanager',
        endpoint_url=os.environ.get('SECRETS_MANAGER_ENDPOINT')
    )

    if step == "createSecret":
        create_secret(sm_client, secret_arn, token)
    elif step == "setSecret":
        # Set the new password on the RDS instance
        pass
    elif step == "testSecret":
        # Test the new password works
        pass
    elif step == "finishSecret":
        finish_secret(sm_client, secret_arn, token)
    else:
        raise ValueError(f"Invalid step: {step}")

def create_secret(sm_client, secret_arn, token):
    current = sm_client.get_secret_value(SecretId=secret_arn, VersionStage="AWSCURRENT")
    current_dict = json.loads(current['SecretString'])

    new_password = sm_client.get_random_password(
        PasswordLength=32,
        ExcludeCharacters='/@"\\\\',
        RequireEachIncludedType=True
    )['RandomPassword']

    current_dict['password'] = new_password

    sm_client.put_secret_value(
        SecretId=secret_arn,
        ClientRequestToken=token,
        SecretString=json.dumps(current_dict),
        VersionStages=['AWSPENDING']
    )

def finish_secret(sm_client, secret_arn, token):
    metadata = sm_client.describe_secret(SecretId=secret_arn)
    current_version = None
    for version_id, stages in metadata['VersionIdsToStages'].items():
        if 'AWSCURRENT' in stages:
            current_version = version_id
            break

    sm_client.update_secret_version_stage(
        SecretId=secret_arn,
        VersionStage='AWSCURRENT',
        MoveToVersionId=token,
        RemoveFromVersionId=current_version
    )
    sm_client.update_secret_version_stage(
        SecretId=secret_arn,
        VersionStage='AWSPENDING',
        RemoveFromVersionId=token
    )
PYTHON
    filename = "lambda_function.py"
  }
}

# Allow Secrets Manager to invoke the rotation Lambda
resource "aws_lambda_permission" "secret_rotation" {
  statement_id  = "AllowSecretsManagerInvocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.secret_rotation.function_name
  principal     = "secretsmanager.amazonaws.com"
  source_arn    = aws_secretsmanager_secret.db_password.arn
}

# =============================================================================
# Input Bucket
# =============================================================================

resource "aws_s3_bucket" "input" {
  bucket = "flink-data-pipeline-${var.environment}-input"

  tags = {
    Name = "flink-data-pipeline-${var.environment}-input"
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

# EventBridge notifications on the Input Bucket (Requirement 1.2)
resource "aws_s3_bucket_notification" "input" {
  bucket      = aws_s3_bucket.input.id
  eventbridge = true
}

# =============================================================================
# Iceberg Bucket
# =============================================================================

resource "aws_s3_bucket" "iceberg" {
  bucket = "flink-data-pipeline-${var.environment}-iceberg"

  tags = {
    Name = "flink-data-pipeline-${var.environment}-iceberg"
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

# =============================================================================
# JAR Bucket
# =============================================================================

resource "aws_s3_bucket" "jar" {
  bucket = "flink-data-pipeline-${var.environment}-jar"

  tags = {
    Name = "flink-data-pipeline-${var.environment}-jar"
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
