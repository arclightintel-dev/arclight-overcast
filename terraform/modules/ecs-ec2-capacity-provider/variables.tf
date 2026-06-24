variable "environment" {
  description = "Environment name (staging, prod)"
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private app subnet IDs for EC2 instances"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "desired_capacity" {
  description = "ASG desired capacity"
  type        = number
  default     = 0
}

variable "min_size" {
  description = "ASG minimum size"
  type        = number
  default     = 0
}

variable "max_size" {
  description = "ASG maximum size"
  type        = number
  default     = 2
}
