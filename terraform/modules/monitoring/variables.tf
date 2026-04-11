# Monitoring Module - Input Variables

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  nullable    = false
}
