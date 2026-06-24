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
