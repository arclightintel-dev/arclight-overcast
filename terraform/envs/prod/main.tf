# Production environment — root module
#
# Same topology as staging, larger instances.
# See staging/main.tf for composition notes.

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "prod"
      Project     = "arclight"
      ManagedBy   = "terraform"
    }
  }
}
