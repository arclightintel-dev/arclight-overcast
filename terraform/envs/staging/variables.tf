variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Platform domain name"
  type        = string
  default     = "arclight-complex.net"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "staging"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

variable "core_desired_count" {
  description = "Core ECS service desired task count"
  type        = number
  default     = 1
}

variable "nerfherder_desired_count" {
  description = "Nerfherder ECS service desired task count (a singleton; 0 after the N-G4 soak, 2026-11-11, until SF Stage C)"
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 1], var.nerfherder_desired_count)
    error_message = "Nerfherder is a singleton (stop before start): desired count must be 0 or 1."
  }
}

variable "shuttleforge_policy_enabled" {
  description = "Bind the reviewed policy secret to ShuttleForge (true only once the shell holds a value, DR-16)"
  type        = bool
  default     = false
}

variable "shuttleforge_desired_count" {
  description = "ShuttleForge ECS service desired task count (1 since the first digest deploy, SF.11 A5 2026-11-10; a singleton, never above 1)"
  type        = number
  default     = 1

  validation {
    condition     = contains([0, 1], var.shuttleforge_desired_count)
    error_message = "ShuttleForge is a singleton (stop before start): desired count must be 0 or 1."
  }
}

variable "alarm_email" {
  description = "Email for CloudWatch alarm notifications (CI: repository secret ALARM_EMAIL)"
  type        = string
  sensitive   = true

  # A missing CI secret would otherwise plan a replacement shown only as "(sensitive value)".
  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alarm_email))
    error_message = "alarm_email must be an email address (CI: set the ALARM_EMAIL repository secret)."
  }
}

variable "github_org" {
  description = "GitHub owner of the repositories (a missing default caused DR-8)"
  type        = string
  default     = "arclightintel-dev"
}

variable "github_repos" {
  description = "GitHub repos allowed to deploy via OIDC"
  type        = list(string)
  default     = []
}

variable "core_image_tag" {
  description = "Core container image tag, e.g. v1-abc1234 (CI: repository variable CORE_IMAGE_TAG, updated after each Core deploy)"
  type        = string

  validation {
    condition     = can(regex("^v[0-9]+-[0-9a-f]{7,40}$", var.core_image_tag))
    error_message = "core_image_tag must look like v<n>-<git sha> (CI: set the CORE_IMAGE_TAG repository variable)."
  }
}

################################################################################
# Bandersnatch (bandersnatch.tf). The hostname, mail addresses and wording are never committed:
# they come from the gitignored terraform.tfvars. Nothing but the ECR repository and push role
# exists until bandersnatch_enabled is true.
################################################################################

variable "bandersnatch_enabled" {
  description = "Create the Bandersnatch substrate (tables, bucket, roles, ALB rule, service)"
  type        = bool
  default     = false
}

variable "bandersnatch_desired_count" {
  description = "Bandersnatch ECS service desired task count (0 except while a share is live)"
  type        = number
  default     = 0
}

variable "bandersnatch_image" {
  description = "Bandersnatch image as repository@sha256:digest; empty registers a digest that cannot exist"
  type        = string
  default     = ""
}

variable "bandersnatch_mail_mode" {
  description = "Mail path: graph (Microsoft 365; grants 443 to the internet). ses is not wired yet: it needs the SES email interface endpoint first"
  type        = string
  default     = "graph"

  validation {
    condition     = var.bandersnatch_mail_mode == "graph"
    error_message = "bandersnatch_mail_mode must be graph. The ses path has no network route until the SES email interface endpoint is added."
  }
}

variable "bandersnatch_public_host" {
  description = "Public hostname of the page, no scheme (terraform.tfvars only)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "bandersnatch_graph_tenant_id" {
  description = "Entra tenant of the sending application (graph mode)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "bandersnatch_graph_client_id" {
  description = "Entra application (client) id used for Graph sendMail (graph mode)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "bandersnatch_mail_from" {
  description = "Sender address"
  type        = string
  default     = ""
  sensitive   = true
}

variable "bandersnatch_mail_from_name" {
  description = "Sender display name"
  type        = string
  default     = ""
  sensitive   = true
}

variable "bandersnatch_mail_reply_to" {
  description = "Reply-To address"
  type        = string
  default     = ""
  sensitive   = true
}

variable "bandersnatch_mail_subject" {
  description = "Neutral subject line"
  type        = string
  default     = ""
  sensitive   = true
}

variable "bandersnatch_page_title" {
  description = "Neutral page title"
  type        = string
  default     = ""
  sensitive   = true
}
