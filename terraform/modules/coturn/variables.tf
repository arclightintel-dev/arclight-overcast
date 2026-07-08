variable "environment" {
  description = "Environment name (staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Public subnet ID for coturn instance"
  type        = string
}

variable "turn_secret_arn" {
  description = "ARN of the TURN shared secret in Secrets Manager"
  type        = string
}

variable "realm" {
  description = "TURN realm (e.g., staging.arclight-complex.net)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
