# RDS Module - RDS PostgreSQL Instance, Parameter Group, Subnet Group,
# Enhanced Monitoring Role, RDS Proxy
#
# Requirements: 8.1-8.14

data "aws_caller_identity" "current" {}

# =============================================================================
# DB Subnet Group
# =============================================================================

resource "aws_db_subnet_group" "main" {
  name        = "flink-data-pipeline-${var.environment}"
  description = "Subnet group for the Flink Data Pipeline RDS instance"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name               = "flink-data-pipeline-${var.environment}-db-subnet-group"
    Environment        = var.environment
    Application        = "flink-data-pipeline"
    Owner              = "platform-engineering"
    CostCenter         = "data-pipeline"
    DataClassification = "CONFIDENTIAL"
  }
}

# =============================================================================
# Custom Parameter Group (force SSL)
# =============================================================================

resource "aws_db_parameter_group" "postgres" {
  name        = "flink-data-pipeline-${var.environment}-pg"
  family      = "postgres16"
  description = "Custom parameter group for Flink Data Pipeline RDS - enforces SSL"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = {
    Name               = "flink-data-pipeline-${var.environment}-pg"
    Environment        = var.environment
    Application        = "flink-data-pipeline"
    Owner              = "platform-engineering"
    CostCenter         = "data-pipeline"
    DataClassification = "CONFIDENTIAL"
  }
}

# =============================================================================
# IAM Role for Enhanced Monitoring
# =============================================================================

resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "flink-data-pipeline-${var.environment}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
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
    Name               = "flink-data-pipeline-${var.environment}-rds-monitoring-role"
    Environment        = var.environment
    Application        = "flink-data-pipeline"
    Owner              = "platform-engineering"
    CostCenter         = "data-pipeline"
    DataClassification = "INTERNAL"
  }
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# =============================================================================
# RDS PostgreSQL Instance
# =============================================================================

resource "aws_db_instance" "main" {
  identifier = "flink-data-pipeline-${var.environment}"

  # Engine configuration
  engine         = "postgres"
  engine_version = "16.4"

  # Instance class - memory-optimized (Requirement 8.1)
  instance_class = var.db_instance_class

  # Storage - gp3 with autoscaling (Requirement 8.3)
  allocated_storage     = 100
  max_allocated_storage = 500
  storage_type          = "gp3"

  # Database configuration
  db_name  = "flink_transactions"
  username = "flink_admin"
  password = var.db_master_password

  # High availability - Multi-AZ (Requirement 8.2)
  multi_az = true

  # Networking - private subnet, not publicly accessible (Requirement 8.5)
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_security_group_id]
  publicly_accessible    = false

  # Authentication - IAM auth enabled (Requirement 8.4)
  iam_database_authentication_enabled = true

  # Encryption at rest - KMS CMK (Requirement 8.7)
  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  # SSL enforcement via custom parameter group (Requirement 8.8)
  parameter_group_name = aws_db_parameter_group.postgres.name

  # Enhanced Monitoring (Requirement 8.11 / 14.2)
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_enhanced_monitoring.arn

  # Performance Insights (Requirement 8.11 / 14.3)
  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_key_arn

  # Automated backups - ≥7 day retention (Requirement 8.12)
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:30-sun:05:30"

  # Deletion protection (Requirement 8.13)
  deletion_protection = true

  # Prevent accidental destruction
  skip_final_snapshot       = false
  final_snapshot_identifier = "flink-data-pipeline-${var.environment}-final"
  copy_tags_to_snapshot     = true

  # Tags (Requirement 8.14)
  tags = {
    Name               = "flink-data-pipeline-${var.environment}"
    Environment        = var.environment
    Application        = "flink-data-pipeline"
    Owner              = "platform-engineering"
    CostCenter         = "data-pipeline"
    DataClassification = "CONFIDENTIAL"
  }
}

# =============================================================================
# RDS Proxy
# =============================================================================

# --- IAM Role for RDS Proxy (Secrets Manager access) ---

resource "aws_iam_role" "rds_proxy" {
  name = "flink-data-pipeline-${var.environment}-rds-proxy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
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
    Name               = "flink-data-pipeline-${var.environment}-rds-proxy-role"
    Environment        = var.environment
    Application        = "flink-data-pipeline"
    Owner              = "platform-engineering"
    CostCenter         = "data-pipeline"
    DataClassification = "INTERNAL"
  }
}

resource "aws_iam_role_policy" "rds_proxy_secrets" {
  name = "rds-proxy-secrets-access"
  role = aws_iam_role.rds_proxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.db_password_secret_arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = var.kms_key_arn
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

# --- RDS Proxy ---

resource "aws_db_proxy" "main" {
  name                   = "flink-data-pipeline-${var.environment}"
  debug_logging          = false
  engine_family          = "POSTGRESQL"
  idle_client_timeout    = 1800
  require_tls            = true
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_security_group_ids = [var.rds_security_group_id]
  vpc_subnet_ids         = var.private_subnet_ids

  auth {
    auth_scheme = "SECRETS"
    description = "RDS Proxy auth using Secrets Manager"
    iam_auth    = "REQUIRED"
    secret_arn  = var.db_password_secret_arn
  }

  tags = {
    Name               = "flink-data-pipeline-${var.environment}-rds-proxy"
    Environment        = var.environment
    Application        = "flink-data-pipeline"
    Owner              = "platform-engineering"
    CostCenter         = "data-pipeline"
    DataClassification = "CONFIDENTIAL"
  }
}

# --- RDS Proxy Default Target Group ---

resource "aws_db_proxy_default_target_group" "main" {
  db_proxy_name = aws_db_proxy.main.name

  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 100
    max_idle_connections_percent = 50
  }
}

# --- RDS Proxy Target (register the RDS instance) ---

resource "aws_db_proxy_target" "main" {
  db_proxy_name          = aws_db_proxy.main.name
  target_group_name      = aws_db_proxy_default_target_group.main.name
  db_instance_identifier = aws_db_instance.main.identifier
}
