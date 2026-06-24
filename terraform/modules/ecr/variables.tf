variable "environment" {
  description = "Environment name (staging, prod)"
  type        = string
}

variable "repository_names" {
  description = "List of ECR repository names"
  type        = list(string)
  default = [
    "arclight/core",
    "arclight/shuttleforge",
    "arclight/podbay",
    "arclight/podbay-workspace-browser",
    "arclight/nerfherder",
    "arclight/dbbootstrap",
  ]
}

variable "max_tagged_image_count" {
  description = "Maximum number of tagged images to retain"
  type        = number
  default     = 10
}

variable "untagged_expiry_days" {
  description = "Days before untagged images expire"
  type        = number
  default     = 7
}
