variable "environment" {
  description = "Environment name (staging, prod)"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for private app subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_db_subnet_cidrs" {
  description = "CIDR blocks for private DB subnets"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "extra_interface_endpoints" {
  description = "Additional interface endpoint service suffixes (for example \"ssm\"), created in the existing pattern: private DNS, the vpce security group"
  type        = list(string)
  default     = []
}

variable "extra_interface_endpoint_subnet_indexes" {
  description = "Indexes into the private app subnets (and var.azs) for the additional interface endpoints; null places them in every private app subnet like the existing endpoints"
  type        = list(number)
  default     = null
}
