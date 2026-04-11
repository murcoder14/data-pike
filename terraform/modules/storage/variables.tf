# Storage Module - Input Variables

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  nullable    = false
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  nullable    = false
}
