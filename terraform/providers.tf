terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.40"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Application = var.project_name
      ManagedBy   = "terraform"
    }
  }
}

# Use this provider for resources that must be created without tags first.
provider "aws" {
  alias  = "no_tags"
  region = var.aws_region
}
