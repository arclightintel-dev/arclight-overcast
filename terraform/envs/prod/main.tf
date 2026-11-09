terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
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

data "aws_caller_identity" "current" {}

################################################################################
# Scope (O-016, docs/proposals/prod-substrate-reduction.md)
#
# v1 has no production environment (owner). This root keeps only what Backstage (O-012,
# terraform/envs/backstage) runs on: the VPC with its NAT and endpoints, the ALB with its
# listeners, and the alarm topic. The RDS instance, ECS cluster, service secrets, roles and the
# dbbootstrap tasks were removed 2026-11; the final RDS snapshot is arclight-prod-final-fcf44ee8.
# A production deployment after v1 starts from D-056 again, not from this root's history.
################################################################################

data "aws_acm_certificate" "prod" {
  domain      = "*.${var.domain_name}"
  statuses    = ["ISSUED"]
  most_recent = true
}

module "vpc" {
  source = "../../modules/vpc"

  environment              = var.environment
  vpc_cidr                 = var.vpc_cidr
  public_subnet_cidrs      = ["10.1.1.0/24", "10.1.2.0/24"]
  private_app_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]
  private_db_subnet_cidrs  = ["10.1.20.0/24", "10.1.21.0/24"]

  # O-012/OW-6 (owner, 2026-10-21): one AZ, the private app subnet the Backstage host
  # uses. A second AZ is added when a prod workload needs it.
  extra_interface_endpoints               = ["secretsmanager", "ssm", "ssmmessages", "ec2messages", "monitoring"]
  extra_interface_endpoint_subnet_indexes = [0] # us-east-1a, private app 10.1.10.0/24
}

module "alb" {
  source = "../../modules/alb"

  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  certificate_arn   = data.aws_acm_certificate.prod.arn
  domain_name       = var.domain_name

  allowed_ingress_cidrs      = var.cloudflare_ipv4_cidrs
  allowed_ingress_ipv6_cidrs = var.cloudflare_ipv6_cidrs

  # No module services in prod: Backstage brings its own target group and listener rule.
  services                   = {}
  service_security_group_ids = {}
}

module "observability" {
  source = "../../modules/observability"

  environment    = var.environment
  aws_account_id = data.aws_caller_identity.current.account_id
  aws_region     = var.aws_region
  alarm_email    = var.alarm_email
  alb_arn_suffix = module.alb.alb_arn_suffix
  # Both names are unused with the alarms below off; the module requires them.
  rds_instance_id       = "arclight-${var.environment}"
  ecs_cluster_name      = "arclight-${var.environment}"
  create_cloudtrail     = false
  create_budget         = false
  create_service_alarms = false
  create_rds_alarms     = false
}
