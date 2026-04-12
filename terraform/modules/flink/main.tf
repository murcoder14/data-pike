# Flink Module - Flink Application and Execution IAM Role
#
# Managed Service for Apache Flink application and its dedicated IAM role.
# Requirements: 6.1-6.5, 12.1-12.4, 12.9, 12.10

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.id
  iceberg_table_resource_name = element(split(".", var.iceberg_table_name), length(split(".", var.iceberg_table_name)) - 1)
}

# =============================================================================
# Flink Execution Role (Requirement 12.1)
# =============================================================================

resource "aws_iam_role" "flink_execution" {
  name = "${var.project_name}-${var.environment}-flink-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "kinesisanalytics.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-flink-execution"
    Environment = var.environment
    Application = var.project_name
  }
}

# =============================================================================
# Kinesis Permissions (Requirement 12.2)
# =============================================================================

resource "aws_iam_role_policy" "flink_kinesis" {
  name = "flink-kinesis-access"
  role = aws_iam_role.flink_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KinesisReadAccess"
        Effect = "Allow"
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:ListShards"
        ]
        Resource = var.kinesis_stream_arn
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = local.region
          }
        }
      },
      {
        Sid    = "KinesisSubscribeToShard"
        Effect = "Allow"
        Action = [
          "kinesis:SubscribeToShard",
          "kinesis:DescribeStreamSummary"
        ]
        Resource = var.kinesis_stream_arn
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = local.region
          }
        }
      },
      {
        Sid    = "KinesisListStreams"
        Effect = "Allow"
        Action = [
          "kinesis:ListStreams"
        ]
        Resource = "arn:aws:kinesis:${local.region}:${local.account_id}:stream/*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = local.region
          }
        }
      }
    ]
  })
}

# =============================================================================
# S3 Permissions — Input Bucket Read (Requirement 12.3)
# =============================================================================

resource "aws_iam_role_policy" "flink_s3_input" {
  name = "flink-s3-input-read"
  role = aws_iam_role.flink_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3InputBucketRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          var.input_bucket_arn,
          "${var.input_bucket_arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = local.region
          }
        }
      }
    ]
  })
}

# =============================================================================
# S3 Permissions — Iceberg Bucket Write (Requirement 12.3)
# =============================================================================

resource "aws_iam_role_policy" "flink_s3_iceberg" {
  name = "flink-s3-iceberg-write"
  role = aws_iam_role.flink_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3IcebergBucketWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.iceberg_bucket_arn,
          "${var.iceberg_bucket_arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = local.region
          }
        }
      }
    ]
  })
}

# =============================================================================
# S3 Permissions — JAR Bucket Read (Requirement 12.4)
# =============================================================================

resource "aws_iam_role_policy" "flink_s3_jar" {
  name = "flink-s3-jar-read"
  role = aws_iam_role.flink_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3JarBucketRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          var.jar_bucket_arn,
          "${var.jar_bucket_arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = local.region
          }
        }
      }
    ]
  })
}

# =============================================================================
# CloudWatch Logging Permissions (Requirement 12.9)
# =============================================================================

resource "aws_iam_role_policy" "flink_cloudwatch" {
  name = "flink-cloudwatch-logging"
  role = aws_iam_role.flink_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogGroupAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          var.flink_log_group_arn,
          "${var.flink_log_group_arn}:*"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

# =============================================================================
# KMS Decrypt Permission (for encrypted Kinesis, S3, and CloudWatch)
# =============================================================================

resource "aws_iam_role_policy" "flink_kms" {
  name = "flink-kms-decrypt"
  role = aws_iam_role.flink_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KMSDecryptAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_arn
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = local.region
          }
        }
      }
    ]
  })
}

# =============================================================================
# Glue Catalog Permissions (for Iceberg table metadata)
# =============================================================================

resource "aws_iam_role_policy" "flink_glue" {
  name = "flink-glue-catalog"
  role = aws_iam_role.flink_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GlueCatalogReadWriteMetadata"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetTableVersion",
          "glue:GetTableVersions",
          "glue:UpdateTable",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchGetPartition"
        ]
        Resource = [
          "arn:aws:glue:${local.region}:${local.account_id}:catalog",
          "arn:aws:glue:${local.region}:${local.account_id}:database/${var.iceberg_database_name}",
          "arn:aws:glue:${local.region}:${local.account_id}:table/${var.iceberg_database_name}/${local.iceberg_table_resource_name}"
        ]
      }
    ]
  })
}

# =============================================================================
# VPC Networking Permissions (for ENI management in VPC-deployed Flink)
# =============================================================================

resource "aws_iam_role_policy" "flink_vpc" {
  name = "flink-vpc-networking"
  role = aws_iam_role.flink_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VPCDescribeAccess"
        Effect = "Allow"
        Action = [
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeDhcpOptions"
        ]
        # EC2 Describe actions require Resource "*" — they do not support resource-level permissions
        Resource = "*"
      },
      {
        Sid    = "VPCNetworkInterfaceCreate"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface"
        ]
        Resource = [
          "arn:aws:ec2:${local.region}:${local.account_id}:network-interface/*",
          "arn:aws:ec2:${local.region}:${local.account_id}:security-group/${var.flink_security_group_id}",
          "arn:aws:ec2:${local.region}:${local.account_id}:subnet/*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = local.region
          }
        }
      },
      {
        Sid    = "VPCNetworkInterfaceDelete"
        Effect = "Allow"
        Action = [
          "ec2:DeleteNetworkInterface",
          "ec2:CreateNetworkInterfacePermission"
        ]
        Resource = "arn:aws:ec2:${local.region}:${local.account_id}:network-interface/*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = local.region
          }
        }
      }
    ]
  })
}

# =============================================================================
# Flink Application Resource
# =============================================================================

resource "aws_kinesisanalyticsv2_application" "flink" {
  name                   = "${var.project_name}-${var.environment}"
  runtime_environment    = "FLINK-2_2"
  service_execution_role = aws_iam_role.flink_execution.arn

  lifecycle {
    # Prevent accidental destroy/recreate in normal applies.
    prevent_destroy = true
  }

  # Streaming mode (Requirement 6.2)
  application_mode = "STREAMING"

  application_configuration {

    # FAT JAR from JAR Bucket (Requirement 6.3)
    application_code_configuration {
      code_content {
        s3_content_location {
          bucket_arn = var.jar_bucket_arn
          file_key   = var.file_key
        }
      }
      code_content_type = "ZIPFILE"
    }

    # Flink runtime configuration (Requirement 6.5)
    flink_application_configuration {
      checkpoint_configuration {
        configuration_type = "DEFAULT"
      }

      monitoring_configuration {
        configuration_type = "CUSTOM"
        log_level          = "INFO"
        metrics_level      = "APPLICATION"
      }

      parallelism_configuration {
        configuration_type   = "CUSTOM"
        auto_scaling_enabled = true
        parallelism          = 1
        parallelism_per_kpu  = 1
      }
    }

    # VPC configuration (Requirement 13.1, 13.2)
    vpc_configuration {
      subnet_ids         = var.private_subnet_ids
      security_group_ids = [var.flink_security_group_id]
    }

    # Runtime properties passed to the application via KinesisAnalyticsRuntime
    environment_properties {
      property_group {
        property_group_id = "KinesisSource"
        property_map = {
          "stream.arn" = var.kinesis_stream_arn
          "aws.region" = var.aws_region
        }
      }

      property_group {
        property_group_id = "IcebergSink"
        property_map = {
          "warehouse.path" = var.iceberg_warehouse_path
          "catalog.name"   = var.iceberg_catalog_name
          "table.name"     = var.iceberg_table_name
        }
      }
    }
  }

  # CloudWatch logging (Requirement 14.1)
  cloudwatch_logging_options {
    log_stream_arn = "${var.flink_log_group_arn}:log-stream:${var.flink_log_stream_name}"
  }

  # Continuously running streaming application (Requirement 6.2)
  start_application = true

}
