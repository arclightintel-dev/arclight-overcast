# Staging environment — root module
#
# Composes all infrastructure modules for the staging environment.
# Identical topology to production, smaller instances (D-056 §12).
#
# Module composition order matches D-056 §9 boot sequence:
#   1. VPC + networking
#   2. RDS PostgreSQL
#   3. ECR repositories
#   4. Secrets Manager shells
#   5. ECS cluster + capacity providers
#   6. ALB + Route 53 + ACM
#   7. IAM roles (GitHub OIDC, task roles)
#   8. Observability (log groups, alarms)
#   9. ECS services (Core → ShuttleForge → Podbay)

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
      Environment = "staging"
      Project     = "arclight"
      ManagedBy   = "terraform"
    }
  }
}
