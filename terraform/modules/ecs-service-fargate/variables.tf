variable "service_name" {
  description = "Service name (e.g., core, shuttleforge)"
  type        = string
}

variable "environment" {
  description = "Environment name (staging, prod)"
  type        = string
}

variable "cluster_id" {
  description = "ECS cluster ID"
  type        = string
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "subnet_ids" {
  description = "Private app subnet IDs"
  type        = list(string)
}

variable "security_group_id" {
  description = "Pre-existing service security group ID (from VPC module)"
  type        = string
}

variable "alb_security_group_id" {
  description = "ALB security group ID (for ingress rule source)"
  type        = string
}

variable "rds_security_group_id" {
  description = "RDS security group ID (for egress rule target). Null if service has no DB."
  type        = string
  default     = null
}

variable "container_port" {
  description = "Container port"
  type        = number
}

variable "desired_count" {
  description = "Desired task count"
  type        = number
  default     = 1
}

variable "cpu" {
  description = "Task CPU units"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Task memory (MB)"
  type        = number
  default     = 512
}

variable "execution_role_arn" {
  description = "ECS execution role ARN (from secrets module)"
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role ARN. Null if service makes no AWS API calls at runtime."
  type        = string
  default     = null
}

variable "cloud_map_namespace_id" {
  description = "Cloud Map private DNS namespace ID"
  type        = string
}

variable "target_group_arn" {
  description = "ALB target group ARN. Null for internal-only services."
  type        = string
  default     = null
}

variable "task_definition_template" {
  description = "Path to containerDefinitions .json.tpl file"
  type        = string
}

variable "template_variables" {
  description = "Variables for templatefile() rendering"
  type        = map(string)
}

variable "health_check_grace_period_seconds" {
  description = "Seconds ALB waits before judging health during startup"
  type        = number
  default     = 120
}
