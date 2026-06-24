variable "environment" {
  description = "Environment name (staging, prod)"
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "private_dns_namespace" {
  description = "Private DNS namespace for Cloud Map (e.g., staging.internal.arclight-complex.net)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for Cloud Map namespace"
  type        = string
}
