# Networking Module - Input Variables

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  nullable    = false
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  nullable    = false

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be a valid CIDR block."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  nullable    = false
}
