variable "environment" {
  description = "Environment name (staging, prod)"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "alarm_email" {
  description = "Email for alarm notifications"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 30
}

variable "cloudtrail_retention_days" {
  description = "CloudTrail S3 log retention in days"
  type        = number
  default     = 90
}

variable "budget_limit_monthly" {
  description = "Monthly budget limit in USD"
  type        = string
  default     = "500"
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix for CloudWatch metrics"
  type        = string
}

variable "rds_instance_id" {
  description = "RDS instance identifier for CloudWatch metrics"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name for CloudWatch metrics"
  type        = string
}

variable "create_cloudtrail" {
  description = "Create CloudTrail trail and S3 bucket. False for prod (staging owns the account trail)."
  type        = bool
  default     = true
}

variable "create_budget" {
  description = "Create budget alarm. False for prod (staging owns the account budget)."
  type        = bool
  default     = true
}

variable "create_service_alarms" {
  description = "Create ECS service-level alarms. False for empty substrate (no services running)."
  type        = bool
  default     = true
}
