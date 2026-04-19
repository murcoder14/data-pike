# CI/CD Module - CodeBuild, CodePipeline, IAM Roles
#
# CodeBuild projects (Build/Plan/Apply), CodePipeline, pipeline artifacts
# bucket, CodeStar connection, and all CI/CD IAM roles.
# Requirements: 9.1-9.4, 10.1-10.5, 12.5-12.7, 12.11

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.id

  terraform_state_bucket_name = replace(var.terraform_state_bucket_arn, "arn:aws:s3:::", "")
  terraform_lock_table_name   = split("/", var.terraform_lock_table_arn)[1]
}

# =============================================================================
# Build_Stage IAM Role
# =============================================================================

resource "aws_iam_role" "codebuild_build" {
  name = "${var.project_name}-${var.environment}-codebuild-build"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
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
    Name        = "${var.project_name}-${var.environment}-codebuild-build"
    Environment = var.environment
    Application = var.project_name
  }
}

# Build_Stage: S3 write to JAR bucket (upload FAT JAR)
resource "aws_iam_role_policy" "build_s3_jar" {
  name = "build-s3-jar-write"
  role = aws_iam_role.codebuild_build.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3JarBucketWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = [
          var.jar_bucket_arn,
          "${var.jar_bucket_arn}/*"
        ]
      }
    ]
  })
}

# Build_Stage: CloudWatch logs
resource "aws_iam_role_policy" "build_cloudwatch" {
  name = "build-cloudwatch-logging"
  role = aws_iam_role.codebuild_build.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          var.codebuild_build_log_group_arn,
          "${var.codebuild_build_log_group_arn}:*"
        ]
      }
    ]
  })
}

# Build_Stage: KMS access for encrypted S3 buckets
resource "aws_iam_role_policy" "build_kms" {
  name = "build-kms-access"
  role = aws_iam_role.codebuild_build.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_arn
      }
    ]
  })
}

# Build_Stage: CodeBuild permissions for build reports
resource "aws_iam_role_policy" "build_codebuild" {
  name = "build-codebuild-reports"
  role = aws_iam_role.codebuild_build.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CodeBuildReportAccess"
        Effect = "Allow"
        Action = [
          "codebuild:CreateReportGroup",
          "codebuild:CreateReport",
          "codebuild:UpdateReport",
          "codebuild:BatchPutTestCases",
          "codebuild:BatchPutCodeCoverages"
        ]
        Resource = "arn:aws:codebuild:${local.region}:${local.account_id}:report-group/${var.project_name}-${var.environment}-build-*"
      }
    ]
  })
}

# Build_Stage: pipeline artifacts bucket (CodePipeline passes source/output artifacts through here)
resource "aws_iam_role_policy" "build_s3_artifacts" {
  name = "build-s3-artifacts-readwrite"
  role = aws_iam_role.codebuild_build.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ArtifactsBucketReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::${var.pipeline_artifacts_bucket_name}",
          "arn:aws:s3:::${var.pipeline_artifacts_bucket_name}/*"
        ]
      }
    ]
  })
}

# =============================================================================
# Plan_Stage IAM Role
# =============================================================================

resource "aws_iam_role" "codebuild_plan" {
  name = "${var.project_name}-${var.environment}-codebuild-plan"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
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
    Name        = "${var.project_name}-${var.environment}-codebuild-plan"
    Environment = var.environment
    Application = var.project_name
  }
}

# Plan_Stage: S3 read/write on state bucket (read state + manage .tflock lockfile)
resource "aws_iam_role_policy" "plan_s3_state" {
  name = "plan-s3-state-readwrite"
  role = aws_iam_role.codebuild_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3StateReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          var.terraform_state_bucket_arn,
          "${var.terraform_state_bucket_arn}/*"
        ]
      }
    ]
  })
}

# Plan_Stage: DynamoDB for state lock
resource "aws_iam_role_policy" "plan_dynamodb_lock" {
  name = "plan-dynamodb-state-lock"
  role = aws_iam_role.codebuild_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBStateLock"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = var.terraform_lock_table_arn
      }
    ]
  })
}

# Plan_Stage: CloudWatch logs
resource "aws_iam_role_policy" "plan_cloudwatch" {
  name = "plan-cloudwatch-logging"
  role = aws_iam_role.codebuild_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          var.codebuild_plan_log_group_arn,
          "${var.codebuild_plan_log_group_arn}:*"
        ]
      }
    ]
  })
}

# Plan_Stage: AWS managed ReadOnlyAccess covers all Terraform provider read APIs
resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.codebuild_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Plan_Stage: KMS access for encrypted state
resource "aws_iam_role_policy" "plan_kms" {
  name = "plan-kms-access"
  role = aws_iam_role.codebuild_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_arn
      }
    ]
  })
}

# Plan_Stage: CodeBuild report permissions
resource "aws_iam_role_policy" "plan_codebuild" {
  name = "plan-codebuild-reports"
  role = aws_iam_role.codebuild_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CodeBuildReportAccess"
        Effect = "Allow"
        Action = [
          "codebuild:CreateReportGroup",
          "codebuild:CreateReport",
          "codebuild:UpdateReport",
          "codebuild:BatchPutTestCases",
          "codebuild:BatchPutCodeCoverages"
        ]
        Resource = "arn:aws:codebuild:${local.region}:${local.account_id}:report-group/${var.project_name}-${var.environment}-plan-*"
      }
    ]
  })
}

# Plan_Stage: pipeline artifacts bucket (reads source artifacts in, writes tfplan artifact out)
resource "aws_iam_role_policy" "plan_s3_artifacts" {
  name = "plan-s3-artifacts-readwrite"
  role = aws_iam_role.codebuild_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ArtifactsBucketReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::${var.pipeline_artifacts_bucket_name}",
          "arn:aws:s3:::${var.pipeline_artifacts_bucket_name}/*"
        ]
      }
    ]
  })
}

# =============================================================================
# Apply_Stage IAM Role
# =============================================================================

resource "aws_iam_role" "codebuild_apply" {
  name = "${var.project_name}-${var.environment}-codebuild-apply"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
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
    Name        = "${var.project_name}-${var.environment}-codebuild-apply"
    Environment = var.environment
    Application = var.project_name
  }
}

# Apply_Stage: S3 read/write on state bucket
resource "aws_iam_role_policy" "apply_s3_state" {
  name = "apply-s3-state-readwrite"
  role = aws_iam_role.codebuild_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3StateReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          var.terraform_state_bucket_arn,
          "${var.terraform_state_bucket_arn}/*"
        ]
      }
    ]
  })
}

# Apply_Stage: DynamoDB for state lock
resource "aws_iam_role_policy" "apply_dynamodb_lock" {
  name = "apply-dynamodb-state-lock"
  role = aws_iam_role.codebuild_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBStateLock"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = var.terraform_lock_table_arn
      }
    ]
  })
}

# Apply_Stage: CloudWatch logs
resource "aws_iam_role_policy" "apply_cloudwatch" {
  name = "apply-cloudwatch-logging"
  role = aws_iam_role.codebuild_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:TagResource",
          "logs:UntagResource",
          "logs:ListTagsForResource"
        ]
        Resource = [
          var.codebuild_apply_log_group_arn,
          "${var.codebuild_apply_log_group_arn}:*",
          var.flink_log_group_arn,
          "${var.flink_log_group_arn}:*",
          var.codebuild_build_log_group_arn,
          "${var.codebuild_build_log_group_arn}:*",
          var.codebuild_plan_log_group_arn,
          "${var.codebuild_plan_log_group_arn}:*"
        ]
      }
    ]
  })
}

# Apply_Stage: Full resource management for terraform apply
resource "aws_iam_role_policy" "apply_resource_management" {
  name = "apply-resource-management"
  role = aws_iam_role.codebuild_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketManagement"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:GetBucketAcl",
          "s3:GetEncryptionConfiguration",
          "s3:PutEncryptionConfiguration",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketNotification",
          "s3:PutBucketNotification",
          "s3:GetBucketTagging",
          "s3:PutBucketTagging",
          "s3:GetBucketLogging"
        ]
        Resource = [
          var.input_bucket_arn,
          "${var.input_bucket_arn}/*",
          var.iceberg_bucket_arn,
          "${var.iceberg_bucket_arn}/*",
          var.jar_bucket_arn,
          "${var.jar_bucket_arn}/*"
        ]
      },
      {
        Sid    = "KinesisManagement"
        Effect = "Allow"
        Action = [
          "kinesis:CreateStream",
          "kinesis:DeleteStream",
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:UpdateShardCount",
          "kinesis:StartStreamEncryption",
          "kinesis:StopStreamEncryption",
          "kinesis:AddTagsToStream",
          "kinesis:RemoveTagsFromStream",
          "kinesis:ListTagsForStream"
        ]
        Resource = var.kinesis_stream_arn
      },
      {
        Sid    = "RDSManagement"
        Effect = "Allow"
        Action = [
          "rds:CreateDBInstance",
          "rds:DeleteDBInstance",
          "rds:ModifyDBInstance",
          "rds:DescribeDBInstances",
          "rds:CreateDBProxy",
          "rds:DeleteDBProxy",
          "rds:ModifyDBProxy",
          "rds:DescribeDBProxies",
          "rds:RegisterDBProxyTargets",
          "rds:DeregisterDBProxyTargets",
          "rds:DescribeDBProxyTargets",
          "rds:DescribeDBProxyTargetGroups",
          "rds:ModifyDBProxyTargetGroup",
          "rds:CreateDBSubnetGroup",
          "rds:DeleteDBSubnetGroup",
          "rds:ModifyDBSubnetGroup",
          "rds:DescribeDBSubnetGroups",
          "rds:CreateDBParameterGroup",
          "rds:DeleteDBParameterGroup",
          "rds:ModifyDBParameterGroup",
          "rds:DescribeDBParameterGroups",
          "rds:DescribeDBParameters",
          "rds:AddTagsToResource",
          "rds:RemoveTagsFromResource",
          "rds:ListTagsForResource"
        ]
        Resource = [
          "arn:aws:rds:${local.region}:${local.account_id}:db:${var.project_name}-${var.environment}*",
          "arn:aws:rds:${local.region}:${local.account_id}:db-proxy:*",
          "arn:aws:rds:${local.region}:${local.account_id}:subgrp:${var.project_name}-${var.environment}-*",
          "arn:aws:rds:${local.region}:${local.account_id}:pg:${var.project_name}-${var.environment}-*"
        ]
      },
      {
        Sid    = "EC2NetworkManagement"
        Effect = "Allow"
        Action = [
          "ec2:CreateVpc",
          "ec2:DeleteVpc",
          "ec2:ModifyVpcAttribute",
          "ec2:DescribeVpcs",
          "ec2:CreateSubnet",
          "ec2:DeleteSubnet",
          "ec2:DescribeSubnets",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSecurityGroupRules",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:CreateVpcEndpoint",
          "ec2:DeleteVpcEndpoints",
          "ec2:ModifyVpcEndpoint",
          "ec2:DescribeVpcEndpoints",
          "ec2:CreateRouteTable",
          "ec2:DeleteRouteTable",
          "ec2:AssociateRouteTable",
          "ec2:DisassociateRouteTable",
          "ec2:DescribeRouteTables",
          "ec2:CreateRoute",
          "ec2:DeleteRoute",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribePrefixLists",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:DescribeTags",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeDhcpOptions"
        ]
        Resource = "arn:aws:ec2:${local.region}:${local.account_id}:*"
      },
      {
        Sid    = "IAMRoleManagement"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:UpdateRole",
          "iam:PassRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:ListInstanceProfilesForRole"
        ]
        Resource = [
          "arn:aws:iam::${local.account_id}:role/${var.project_name}-${var.environment}-*",
          "arn:aws:iam::${local.account_id}:policy/${var.project_name}-${var.environment}-*",
          "arn:aws:iam::${local.account_id}:instance-profile/${var.project_name}-${var.environment}-*"
        ]
      },
      {
        Sid    = "KMSManagement"
        Effect = "Allow"
        Action = [
          "kms:CreateKey",
          "kms:DescribeKey",
          "kms:GetKeyPolicy",
          "kms:GetKeyRotationStatus",
          "kms:EnableKeyRotation",
          "kms:PutKeyPolicy",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:CreateAlias",
          "kms:DeleteAlias",
          "kms:UpdateAlias",
          "kms:ListAliases",
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_arn
      },
      {
        Sid    = "KMSAliasManagement"
        Effect = "Allow"
        Action = [
          "kms:CreateAlias",
          "kms:DeleteAlias",
          "kms:UpdateAlias",
          "kms:ListAliases"
        ]
        Resource = var.kms_alias_arn
      },
      {
        Sid    = "SecretsManagerManagement"
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecret",
          "secretsmanager:TagResource",
          "secretsmanager:UntagResource",
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:PutResourcePolicy",
          "secretsmanager:DeleteResourcePolicy",
          "secretsmanager:RotateSecret"
        ]
        Resource = "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${var.project_name}-${var.environment}-*"
      },
      {
        Sid    = "EventBridgeManagement"
        Effect = "Allow"
        Action = [
          "events:PutRule",
          "events:DeleteRule",
          "events:DescribeRule",
          "events:EnableRule",
          "events:DisableRule",
          "events:PutTargets",
          "events:RemoveTargets",
          "events:ListTargetsByRule",
          "events:TagResource",
          "events:UntagResource",
          "events:ListTagsForResource"
        ]
        Resource = "arn:aws:events:${local.region}:${local.account_id}:rule/${var.project_name}-${var.environment}-*"
      },
      {
        Sid    = "KinesisAnalyticsManagement"
        Effect = "Allow"
        Action = [
          "kinesisanalyticsv2:CreateApplication",
          "kinesisanalyticsv2:DeleteApplication",
          "kinesisanalyticsv2:UpdateApplication",
          "kinesisanalyticsv2:DescribeApplication",
          "kinesisanalyticsv2:StartApplication",
          "kinesisanalyticsv2:StopApplication",
          "kinesisanalyticsv2:AddApplicationVpcConfiguration",
          "kinesisanalyticsv2:DeleteApplicationVpcConfiguration",
          "kinesisanalyticsv2:AddApplicationCloudWatchLoggingOption",
          "kinesisanalyticsv2:DeleteApplicationCloudWatchLoggingOption",
          "kinesisanalyticsv2:TagResource",
          "kinesisanalyticsv2:UntagResource",
          "kinesisanalyticsv2:ListTagsForResource"
        ]
        Resource = "arn:aws:kinesisanalytics:${local.region}:${local.account_id}:application/${var.project_name}-${var.environment}"
      },
      {
        Sid    = "DynamoDBManagement"
        Effect = "Allow"
        Action = [
          "dynamodb:CreateTable",
          "dynamodb:DeleteTable",
          "dynamodb:DescribeTable",
          "dynamodb:UpdateTable",
          "dynamodb:TagResource",
          "dynamodb:UntagResource",
          "dynamodb:ListTagsOfResource",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = var.terraform_lock_table_arn
      }
    ]
  })
}

# Apply_Stage: CodeBuild report permissions
resource "aws_iam_role_policy" "apply_codebuild" {
  name = "apply-codebuild-reports"
  role = aws_iam_role.codebuild_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CodeBuildReportAccess"
        Effect = "Allow"
        Action = [
          "codebuild:CreateReportGroup",
          "codebuild:CreateReport",
          "codebuild:UpdateReport",
          "codebuild:BatchPutTestCases",
          "codebuild:BatchPutCodeCoverages"
        ]
        Resource = "arn:aws:codebuild:${local.region}:${local.account_id}:report-group/${var.project_name}-${var.environment}-apply-*"
      }
    ]
  })
}

# Apply_Stage: pipeline artifacts bucket (reads build artifacts passed by CodePipeline)
resource "aws_iam_role_policy" "apply_s3_artifacts" {
  name = "apply-s3-artifacts-read"
  role = aws_iam_role.codebuild_apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ArtifactsBucketRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::${var.pipeline_artifacts_bucket_name}",
          "arn:aws:s3:::${var.pipeline_artifacts_bucket_name}/*"
        ]
      }
    ]
  })
}

# =============================================================================
# Build_Stage CodeBuild Project (Requirements 9.1, 9.2, 9.3, 9.4)
# =============================================================================

resource "aws_codebuild_project" "build" {
  name          = "${var.project_name}-${var.environment}-build"
  description   = "Build Stage: Maven compile + Shade plugin to produce FAT JAR, upload to JAR bucket"
  service_role  = aws_iam_role.codebuild_build.arn
  build_timeout = 30

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_MEDIUM"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false

    environment_variable {
      name  = "JAR_BUCKET"
      value = var.jar_bucket_id
    }

    environment_variable {
      name  = "FILE_KEY"
      value = var.file_key
    }
  }

  source {
    type      = "GITHUB"
    location  = "https://github.com/${var.github_repo}.git"
    buildspec = <<-BUILDSPEC
      version: 0.2
      phases:
        install:
          runtime-versions:
            java: corretto17
          commands:
            - java -version
            - mvn --version
        build:
          commands:
            - echo "Building FAT JAR with Maven Shade plugin..."
            - mvn clean package -DskipTests
        post_build:
          commands:
            - echo "Uploading FAT JAR to S3..."
            - export COMMIT_HASH=$${CODEBUILD_RESOLVED_SOURCE_VERSION}
            - export JAR_FILE=$(find target -name "*.jar" -not -name "original-*" | head -1)
            - aws s3 cp $${JAR_FILE} s3://$${JAR_BUCKET}/$${FILE_KEY}
            - aws s3 cp $${JAR_FILE} s3://$${JAR_BUCKET}/jars/my-app-$${COMMIT_HASH}.jar
            - echo "Uploaded $${FILE_KEY} and jars/my-app-$${COMMIT_HASH}.jar to $${JAR_BUCKET}"
    BUILDSPEC
  }

  logs_config {
    cloudwatch_logs {
      group_name = var.codebuild_build_log_group_name
      status     = "ENABLED"
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-build"
    Environment = var.environment
    Application = var.project_name
  }
}

# =============================================================================
# Plan_Stage CodeBuild Project (Requirements 10.1, 10.2)
# =============================================================================

resource "aws_codebuild_project" "plan" {
  name          = "${var.project_name}-${var.environment}-plan"
  description   = "Plan Stage: Run terraform plan detecting file_key variable change, output plan binary"
  service_role  = aws_iam_role.codebuild_plan.arn
  build_timeout = 30

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false

    environment_variable {
      name  = "TF_VAR_file_key"
      value = var.file_key
    }

    environment_variable {
      name  = "TF_VAR_project_name"
      value = var.project_name
    }

    environment_variable {
      name  = "TF_VAR_environment"
      value = var.environment
    }

    environment_variable {
      # Kinesis ARN format: arn:aws:kinesis:region:account:stream/stream-name
      name  = "TF_VAR_kinesis_stream_name"
      value = split("/", var.kinesis_stream_arn)[1]
    }

    environment_variable {
      # S3 ARN format: arn:aws:s3:::bucket-name
      name  = "TF_VAR_input_bucket_name"
      value = split(":::", var.input_bucket_arn)[1]
    }

    environment_variable {
      name  = "TF_VAR_iceberg_bucket_name"
      value = split(":::", var.iceberg_bucket_arn)[1]
    }

    environment_variable {
      name  = "TF_VAR_jar_bucket_name"
      value = var.jar_bucket_id
    }

    environment_variable {
      name  = "TF_VAR_pipeline_artifacts_bucket_name"
      value = var.pipeline_artifacts_bucket_name
    }

    environment_variable {
      name  = "TF_VAR_iceberg_database_name"
      value = var.iceberg_database_name
    }

    environment_variable {
      name  = "TF_VAR_iceberg_table_name"
      value = var.iceberg_table_name
    }

    environment_variable {
      name  = "TF_VAR_github_repo"
      value = var.github_repo
    }

    environment_variable {
      name  = "TF_VAR_github_branch"
      value = var.github_branch
    }

    environment_variable {
      name  = "TF_STATE_BUCKET"
      value = local.terraform_state_bucket_name
    }

    environment_variable {
      name  = "TF_LOCK_TABLE"
      value = local.terraform_lock_table_name
    }

    environment_variable {
      name  = "TF_STATE_KEY"
      value = "${var.project_name}/${var.environment}/terraform.tfstate"
    }

    environment_variable {
      name  = "TF_STATE_REGION"
      value = local.region
    }
  }

  source {
    type      = "GITHUB"
    location  = "https://github.com/${var.github_repo}.git"
    buildspec = <<-BUILDSPEC
      version: 0.2
      phases:
        install:
          commands:
            - echo "Installing Terraform..."
            - export TF_VERSION=1.14.8
            - export TF_ZIP=terraform_$${TF_VERSION}_linux_amd64.zip
            - curl -fsSLO https://releases.hashicorp.com/terraform/$${TF_VERSION}/$${TF_ZIP}
            - curl -fsSLO https://releases.hashicorp.com/terraform/$${TF_VERSION}/terraform_$${TF_VERSION}_SHA256SUMS
            - grep " $${TF_ZIP}\$" terraform_$${TF_VERSION}_SHA256SUMS > terraform_SHA256SUMS_linux_amd64
            - sha256sum -c terraform_SHA256SUMS_linux_amd64
            - unzip -o $${TF_ZIP} -d /usr/local/bin/
            - terraform --version
        pre_build:
          commands:
            - echo "Initializing Terraform..."
            - cd terraform
            - terraform init -input=false -backend-config="bucket=$${TF_STATE_BUCKET}" -backend-config="key=$${TF_STATE_KEY}" -backend-config="region=$${TF_STATE_REGION}" -backend-config="use_lockfile=true" -backend-config="encrypt=true"
        build:
          commands:
            - echo "Running terraform plan with file_key=$TF_VAR_file_key..."
            - terraform plan -input=false -out=tfplan
            - PLAN_SUMMARY=$(terraform show -no-color tfplan | awk '/^Plan:/{print; exit}')
            - if [[ -z "$${PLAN_SUMMARY}" ]]; then echo "ERROR - could not parse plan summary"; exit 1; fi
            - echo "$${PLAN_SUMMARY}"
            - DESTROY_COUNT=$(echo "$${PLAN_SUMMARY}" | sed -E 's/.* ([0-9]+) to destroy.*/\1/')
            - if [[ "$${DESTROY_COUNT}" -gt 0 ]]; then echo "ERROR - plan includes $${DESTROY_COUNT} destroy actions"; exit 1; fi
            - echo "Plan complete. Details logged above."
            - echo "Generating human-readable plan output..."
            - terraform show tfplan
      artifacts:
        files:
          - terraform/tfplan
        discard-paths: no
    BUILDSPEC
  }

  logs_config {
    cloudwatch_logs {
      group_name = var.codebuild_plan_log_group_name
      status     = "ENABLED"
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-plan"
    Environment = var.environment
    Application = var.project_name
  }
}

# =============================================================================
# Apply_Stage CodeBuild Project (Requirement 10.4)
# =============================================================================

resource "aws_codebuild_project" "apply" {
  name          = "${var.project_name}-${var.environment}-apply"
  description   = "Apply Stage: Run terraform apply using pre-generated plan binary from Plan stage"
  service_role  = aws_iam_role.codebuild_apply.arn
  build_timeout = 30

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false

    environment_variable {
      name  = "TF_VAR_file_key"
      value = var.file_key
    }

    environment_variable {
      name  = "TF_VAR_project_name"
      value = var.project_name
    }

    environment_variable {
      name  = "TF_VAR_environment"
      value = var.environment
    }

    environment_variable {
      name  = "TF_STATE_BUCKET"
      value = local.terraform_state_bucket_name
    }

    environment_variable {
      name  = "TF_LOCK_TABLE"
      value = local.terraform_lock_table_name
    }

    environment_variable {
      name  = "TF_STATE_KEY"
      value = "${var.project_name}/${var.environment}/terraform.tfstate"
    }

    environment_variable {
      name  = "TF_STATE_REGION"
      value = local.region
    }
  }

  source {
    type      = "GITHUB"
    location  = "https://github.com/${var.github_repo}.git"
    buildspec = <<-BUILDSPEC
      version: 0.2
      phases:
        install:
          commands:
            - echo "Installing Terraform..."
            - export TF_VERSION=1.14.8
            - export TF_ZIP=terraform_$${TF_VERSION}_linux_amd64.zip
            - curl -fsSLO https://releases.hashicorp.com/terraform/$${TF_VERSION}/$${TF_ZIP}
            - curl -fsSLO https://releases.hashicorp.com/terraform/$${TF_VERSION}/terraform_$${TF_VERSION}_SHA256SUMS
            - grep " $${TF_ZIP}\$" terraform_$${TF_VERSION}_SHA256SUMS > terraform_SHA256SUMS_linux_amd64
            - sha256sum -c terraform_SHA256SUMS_linux_amd64
            - unzip -o $${TF_ZIP} -d /usr/local/bin/
            - terraform --version
        pre_build:
          commands:
            - echo "Initializing Terraform..."
            - cd terraform
            - cp $CODEBUILD_SRC_DIR_plan_output/terraform/tfplan ./tfplan
            - terraform init -input=false -backend-config="bucket=$${TF_STATE_BUCKET}" -backend-config="key=$${TF_STATE_KEY}" -backend-config="region=$${TF_STATE_REGION}" -backend-config="use_lockfile=true" -backend-config="encrypt=true"
        build:
          commands:
            - PLAN_SUMMARY=$(terraform show -no-color tfplan | awk '/^Plan:/{print; exit}')
            - if [[ -z "$${PLAN_SUMMARY}" ]]; then echo "ERROR - could not parse plan summary"; exit 1; fi
            - echo "Plan summary - $${PLAN_SUMMARY}"
            - DESTROY_COUNT=$(echo "$${PLAN_SUMMARY}" | sed -E 's/.* ([0-9]+) to destroy.*/\1/')
            - if [[ "$${DESTROY_COUNT}" -gt 0 ]]; then echo "ERROR - plan includes $${DESTROY_COUNT} destroy actions"; exit 1; fi
            - echo "Applying Terraform plan..."
            - terraform apply -input=false -auto-approve tfplan
            - echo "Terraform apply complete."
    BUILDSPEC
  }

  logs_config {
    cloudwatch_logs {
      group_name = var.codebuild_apply_log_group_name
      status     = "ENABLED"
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-apply"
    Environment = var.environment
    Application = var.project_name
  }
}

# =============================================================================
# S3 Bucket for Pipeline Artifacts
# =============================================================================

resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket = var.pipeline_artifacts_bucket_name

  tags = {
    Name        = var.pipeline_artifacts_bucket_name
    Environment = var.environment
    Application = var.project_name
  }
}

resource "aws_s3_bucket_versioning" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "pipeline_artifacts_tls_only" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.pipeline_artifacts.arn,
      "${aws_s3_bucket.pipeline_artifacts.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "pipeline_artifacts_tls_only" {
  bucket = aws_s3_bucket.pipeline_artifacts.id
  policy = data.aws_iam_policy_document.pipeline_artifacts_tls_only.json
}

# =============================================================================
# CodeConnections Connection for GitHub v2 Source
# =============================================================================

resource "aws_codeconnections_connection" "github" {
  name          = "${var.project_name}-${var.environment}-github"
  provider_type = "GitHub"

  tags = {
    Name        = "${var.project_name}-${var.environment}-github"
    Environment = var.environment
    Application = var.project_name
  }
}

# =============================================================================
# IAM Role for CodePipeline
# =============================================================================

resource "aws_iam_role" "codepipeline" {
  name = "${var.project_name}-${var.environment}-codepipeline"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
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
    Name        = "${var.project_name}-${var.environment}-codepipeline"
    Environment = var.environment
    Application = var.project_name
  }
}

# CodePipeline: S3 artifact bucket access
resource "aws_iam_role_policy" "codepipeline_s3" {
  name = "codepipeline-s3-artifacts"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ArtifactAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.pipeline_artifacts.arn,
          "${aws_s3_bucket.pipeline_artifacts.arn}/*"
        ]
      }
    ]
  })
}

# CodePipeline: CodeConnections access for GitHub source
resource "aws_iam_role_policy" "codepipeline_codeconnections" {
  name = "codepipeline-codeconnections"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CodeConnectionsAccess"
        Effect = "Allow"
        Action = [
          "codeconnections:UseConnection",
          "codestar-connections:UseConnection"
        ]
        Resource = aws_codeconnections_connection.github.arn
      }
    ]
  })
}

# CodePipeline: CodeBuild access to start builds
resource "aws_iam_role_policy" "codepipeline_codebuild" {
  name = "codepipeline-codebuild-access"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CodeBuildAccess"
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = [
          aws_codebuild_project.build.arn,
          aws_codebuild_project.plan.arn,
          aws_codebuild_project.apply.arn
        ]
      }
    ]
  })
}

# CodePipeline: KMS access for encrypted artifacts
resource "aws_iam_role_policy" "codepipeline_kms" {
  name = "codepipeline-kms-access"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_arn
      }
    ]
  })
}

# =============================================================================
# CodePipeline Resource
# =============================================================================

resource "aws_codepipeline" "main" {
  name     = "${var.project_name}-${var.environment}"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.id
    type     = "S3"

    encryption_key {
      id   = var.kms_key_arn
      type = "KMS"
    }
  }

  # Stage 1: Source - GitHub (main branch) via CodeConnections v2
  stage {
    name = "Source"

    action {
      name             = "GitHub_Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codeconnections_connection.github.arn
        FullRepositoryId = var.github_repo
        BranchName       = var.github_branch
      }
    }
  }

  # Stage 2: Build - Maven compile + Shade plugin → FAT JAR
  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]

      configuration = {
        ProjectName = aws_codebuild_project.build.name
      }
    }
  }

  # Stage 3: Plan - terraform plan detecting file_key variable change
  stage {
    name = "Plan"

    action {
      name             = "Terraform_Plan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["plan_output"]

      configuration = {
        ProjectName = aws_codebuild_project.plan.name
      }
    }
  }

  # Stage 4: Approval - Manual approval pauses pipeline for human review
  # Rejection stops the pipeline (Requirement 10.5)
  stage {
    name = "Approval"

    action {
      name     = "Manual_Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        CustomData = "Review the Terraform plan output in the Plan stage CodeBuild logs before approving. Rejecting will stop the pipeline."
      }
    }
  }

  # Stage 5: Apply - terraform apply using pre-generated plan binary
  stage {
    name = "Apply"

    action {
      name             = "Terraform_Apply"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output", "plan_output"]

      configuration = {
        ProjectName   = aws_codebuild_project.apply.name
        PrimarySource = "source_output"
      }
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}"
    Environment = var.environment
    Application = var.project_name
  }
}
