variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Platform domain name (e.g., arclight.example.com)"
  type        = string
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

variable "podbay_desired_count" {
  description = "Podbay controller ECS service desired task count"
  type        = number
  default     = 1
}

variable "podbay_ec2_instance_type" {
  description = "EC2 instance type for Podbay capacity provider"
  type        = string
  default     = "t3.medium"
}

variable "podbay_ec2_desired_capacity" {
  description = "Desired number of EC2 instances for Podbay"
  type        = number
  default     = 0
}

variable "alarm_email" {
  description = "Email for CloudWatch alarm notifications"
  type        = string
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
}

variable "github_repos" {
  description = "GitHub repos allowed to deploy via OIDC"
  type        = list(string)
  default     = []
}
