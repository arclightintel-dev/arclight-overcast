variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Platform domain name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.1.0.0/16"
}

variable "alarm_email" {
  description = "Email for CloudWatch alarm notifications (the topic Backstage's alarms use)"
  type        = string
}

variable "cloudflare_ipv4_cidrs" {
  description = "Cloudflare IPv4 CIDR ranges for ALB ingress restriction"
  type        = list(string)
}

variable "cloudflare_ipv6_cidrs" {
  description = "Cloudflare IPv6 CIDR ranges for ALB ingress restriction"
  type        = list(string)
}
