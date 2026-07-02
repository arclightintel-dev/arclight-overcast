variable "environment" {
  description = "Environment name (staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "domain_name" {
  description = "Platform domain name (e.g., arclight-complex.net)"
  type        = string
}

variable "public_domain" {
  description = "Full public domain for service URLs (e.g., staging.arclight-complex.net or arclight-complex.net)"
  type        = string
}

variable "private_dns_namespace" {
  description = "Private DNS namespace (e.g., staging.internal.arclight-complex.net)"
  type        = string
}

variable "ecr_repository_arns" {
  description = "Map of ECR repository name to ARN (for execution role pull permissions)"
  type        = map(string)
}
