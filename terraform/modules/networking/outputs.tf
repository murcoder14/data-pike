# Networking Module - Outputs

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidr_blocks" {
  description = "CIDR blocks of the private subnets"
  value       = aws_subnet.private[*].cidr_block
}

output "flink_security_group_id" {
  description = "ID of the Flink application security group"
  value       = aws_security_group.flink.id
}

output "endpoint_security_group_id" {
  description = "ID of the security group attached to interface endpoints"
  value       = aws_security_group.endpoints.id
}

output "s3_vpc_endpoint_id" {
  description = "ID of the S3 gateway VPC endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "kinesis_vpc_endpoint_id" {
  description = "ID of the Kinesis interface VPC endpoint"
  value       = aws_vpc_endpoint.kinesis.id
}

output "logs_vpc_endpoint_id" {
  description = "ID of the CloudWatch Logs interface VPC endpoint"
  value       = aws_vpc_endpoint.logs.id
}

output "glue_vpc_endpoint_id" {
  description = "ID of the Glue interface VPC endpoint"
  value       = aws_vpc_endpoint.glue.id
}

output "kms_vpc_endpoint_id" {
  description = "ID of the KMS interface VPC endpoint"
  value       = aws_vpc_endpoint.kms.id
}

output "sts_vpc_endpoint_id" {
  description = "ID of the STS interface VPC endpoint"
  value       = aws_vpc_endpoint.sts.id
}

output "private_route_table_id" {
  description = "ID of the private subnet route table"
  value       = aws_route_table.private.id
}

output "vpc_flow_log_id" {
  description = "ID of the VPC flow log"
  value       = var.enable_vpc_flow_logs ? aws_flow_log.vpc[0].id : null
}

output "vpc_flow_log_group_name" {
  description = "Name of the VPC flow log CloudWatch log group"
  value       = var.enable_vpc_flow_logs ? aws_cloudwatch_log_group.vpc_flow_logs[0].name : null
}
