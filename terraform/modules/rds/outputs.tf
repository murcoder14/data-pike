# RDS Module - Outputs

output "rds_instance_id" {
  description = "Identifier of the RDS PostgreSQL instance"
  value       = aws_db_instance.main.id
}

output "rds_instance_arn" {
  description = "ARN of the RDS PostgreSQL instance"
  value       = aws_db_instance.main.arn
}

output "rds_instance_endpoint" {
  description = "Connection endpoint for the RDS PostgreSQL instance"
  value       = aws_db_instance.main.endpoint
}

output "rds_instance_address" {
  description = "Hostname of the RDS PostgreSQL instance"
  value       = aws_db_instance.main.address
}

output "rds_instance_port" {
  description = "Port of the RDS PostgreSQL instance"
  value       = aws_db_instance.main.port
}

output "rds_db_name" {
  description = "Name of the default database on the RDS instance"
  value       = aws_db_instance.main.db_name
}

output "rds_subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.main.name
}

output "rds_enhanced_monitoring_role_arn" {
  description = "ARN of the IAM role for RDS Enhanced Monitoring"
  value       = aws_iam_role.rds_enhanced_monitoring.arn
}

output "rds_proxy_arn" {
  description = "ARN of the RDS Proxy"
  value       = aws_db_proxy.main.arn
}

output "rds_proxy_endpoint" {
  description = "Connection endpoint for the RDS Proxy"
  value       = aws_db_proxy.main.endpoint
}

output "rds_proxy_name" {
  description = "Name of the RDS Proxy"
  value       = aws_db_proxy.main.name
}

output "rds_proxy_role_arn" {
  description = "ARN of the IAM role used by the RDS Proxy for Secrets Manager access"
  value       = aws_iam_role.rds_proxy.arn
}
