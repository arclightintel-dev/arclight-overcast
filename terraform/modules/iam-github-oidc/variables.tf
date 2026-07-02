variable "environment" {
  description = "Environment name (staging, prod)"
  type        = string
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
}

variable "github_repos" {
  description = "GitHub repos allowed to deploy via OIDC"
  type        = list(string)
}

variable "ecr_repository_arns" {
  description = "Map of ECR repository name to ARN"
  type        = map(string)
}

variable "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  type        = string
}

variable "terraform_state_bucket_arn" {
  description = "Terraform state S3 bucket ARN"
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

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false for prod (provider already exists from staging)."
  type        = bool
  default     = true
}

variable "oidc_provider_arn" {
  description = "Existing OIDC provider ARN. Required when create_oidc_provider = false."
  type        = string
  default     = null

  validation {
    condition     = var.create_oidc_provider || var.oidc_provider_arn != null
    error_message = "oidc_provider_arn is required when create_oidc_provider is false."
  }
}
