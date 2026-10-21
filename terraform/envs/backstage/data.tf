# Prod objects this root attaches to. Security groups and subnets are found by Name tag:
# the prod modules create security groups with name_prefix, so their names are not stable.

data "aws_caller_identity" "current" {}

data "aws_vpc" "prod" {
  tags = { Name = "arclight-${var.environment}" }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.prod.id]
  }
  filter {
    name   = "tag:Name"
    values = ["arclight-${var.environment}-public-*"]
  }
}

data "aws_subnet" "public" {
  for_each = toset(data.aws_subnets.public.ids)
  id       = each.value
}

data "aws_subnet" "host" {
  vpc_id = data.aws_vpc.prod.id
  filter {
    name   = "tag:Name"
    values = ["arclight-${var.environment}-private-app-${var.host_az}"]
  }
}

data "aws_lb" "prod" {
  name = "arclight-${var.environment}"
}

data "aws_lb_listener" "https" {
  load_balancer_arn = data.aws_lb.prod.arn
  port              = 443
}

data "aws_security_group" "alb" {
  vpc_id = data.aws_vpc.prod.id
  filter {
    name   = "tag:Name"
    values = ["arclight-${var.environment}-alb"]
  }
}

data "aws_security_group" "vpce" {
  vpc_id = data.aws_vpc.prod.id
  filter {
    name   = "tag:Name"
    values = ["arclight-${var.environment}-vpce"]
  }
}

data "aws_vpc_endpoint" "s3" {
  vpc_id       = data.aws_vpc.prod.id
  service_name = "com.amazonaws.${var.aws_region}.s3"
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_sns_topic" "alarms" {
  name = "arclight-${var.environment}-alarms"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  name        = "arclight-backstage-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id
  public_host = "${var.hostname}.${var.domain_name}"
  ssm_prefix  = "/arclight/backstage/${var.environment}"

  # The ALB's nodes live in the public subnets; Backstage trusts forwarded headers only
  # from these (PODBAY_TRUSTED_PROXIES).
  alb_subnet_cidrs = sort([for s in data.aws_subnet.public : s.cidr_block])

  log_groups = {
    for c in ["app", "engine", "litestream", "portal"] : c => "/arclight/backstage/${var.environment}/${c}"
  }
}
