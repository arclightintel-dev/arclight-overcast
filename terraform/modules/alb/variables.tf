variable "environment" {
  description = "Environment name (staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB"
  type        = list(string)
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS"
  type        = string
}

variable "domain_name" {
  description = "Domain for host-based routing (e.g., staging.arclight-complex.net)"
  type        = string
}

variable "allowed_ingress_cidrs" {
  description = "IPv4 CIDR blocks allowed to reach ALB (default: open)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_ingress_ipv6_cidrs" {
  description = "IPv6 CIDR blocks allowed to reach ALB (default: none)"
  type        = list(string)
  default     = []
}

variable "service_security_group_ids" {
  description = "Map of service name to security group ID for ALB egress rules"
  type        = map(string)
}

variable "services" {
  description = "Map of service name to config"
  type = map(object({
    port              = number
    health_check_path = string
  }))
  default = {
    core = {
      port              = 8000
      health_check_path = "/ready"
    }
    shuttleforge = {
      port              = 9000
      health_check_path = "/ready"
    }
    podbay = {
      port              = 8099
      health_check_path = "/health"
    }
  }
}
