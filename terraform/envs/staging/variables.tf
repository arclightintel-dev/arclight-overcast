variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Platform domain name"
  type        = string
  default     = "arclight-complex.net"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "staging"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

variable "core_desired_count" {
  description = "Core ECS service desired task count"
  type        = number
  default     = 1
}

variable "shuttleforge_desired_count" {
  description = "ShuttleForge ECS service desired task count"
  type        = number
  default     = 1
}

variable "alarm_email" {
  description = "Email for CloudWatch alarm notifications (CI: repository secret ALARM_EMAIL)"
  type        = string
  sensitive   = true
}

variable "github_org" {
  description = "GitHub owner of the repositories (a missing default caused DR-8)"
  type        = string
  default     = "arclightintel-dev"
}

variable "github_repos" {
  description = "GitHub repos allowed to deploy via OIDC"
  type        = list(string)
  default     = []
}

variable "core_image_tag" {
  description = "Core container image tag, e.g. v1-abc1234 (CI: repository variable CORE_IMAGE_TAG, updated after each Core deploy)"
  type        = string
}

