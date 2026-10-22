# Every value here is non-secret and committed as a default, so the root plans and applies
# without a tfvars file. Override with -var or a gitignored terraform.tfvars only for a
# deliberate change (for example maintenance_egress on an instance replacement).

variable "environment" {
  description = "Environment of the prod VPC and ALB this root attaches to, and the Backstage name suffix"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Platform domain (Cloudflare zone; the prod ALB carries its wildcard certificate)"
  type        = string
  default     = "arclight-complex.net"
}

variable "hostname" {
  description = "Backstage host label under domain_name"
  type        = string
  default     = "backstage"
}

variable "github_org" {
  description = "GitHub owner of the Overcast and Backstage repositories"
  type        = string
  default     = "arclightintel-dev"
}

variable "backstage_repository" {
  description = "Backstage repository name (legacy name podbay); its main branch may push images"
  type        = string
  default     = "podbay"
}

variable "backstage_oidc_client_id" {
  description = "Entra application (client) ID of arclight-backstage (O-014; a public identifier)"
  type        = string
  default     = "3c25e40a-07ca-4a4a-8491-1506fee590b8"
}

variable "host_az" {
  description = "Availability zone of the host; must match the prod interface endpoints (OW-6, us-east-1a)"
  type        = string
  default     = "us-east-1a"
}

variable "instance_type" {
  description = "Host instance type (owner OW-2: t3.xlarge, Portal cap 3)"
  type        = string
  default     = "t3.xlarge"
}

variable "root_volume_size_gb" {
  description = "Root volume size (OS, Docker images)"
  type        = number
  default     = 30
}

variable "data_volume_size_gb" {
  description = "Data volume size at /srv/backstage (corpus 12.7 GB on 2026-10-21, growing up to about 1.1 GB a month)"
  type        = number
  default     = 100
}

variable "portal_subnet" {
  description = "Subnet of the backstage-portal Docker bridge (outside the VPC and Docker's default pools)"
  type        = string
  default     = "10.255.0.0/24"
}

variable "bridge_ifname" {
  description = "Linux interface name of the backstage-portal bridge, named by the firewall"
  type        = string
  default     = "br-bkstgportal"

  validation {
    condition     = length(var.bridge_ifname) <= 15
    error_message = "Linux interface names are at most 15 characters."
  }
}

variable "proxy_endpoints" {
  description = "Proxy endpoints (ip:port) the host and Portal containers may reach (OW-1: three fixed proxy-cheap endpoints). Adding one is a Terraform change the owner applies; the host reads the list at run time, so the instance is not replaced."
  type        = list(string)
  default     = ["103.115.16.128:41620", "103.115.16.145:42017", "103.115.16.29:49964"]

  validation {
    condition     = alltrue([for ep in var.proxy_endpoints : can(regex("^(\\d{1,3}\\.){3}\\d{1,3}:\\d{1,5}$", ep))])
    error_message = "Each proxy endpoint is ip:port."
  }
}

variable "entra_cidrs" {
  description = "Microsoft Entra sign-in addresses (Microsoft 365 endpoint set 56, login.microsoftonline.com; fetched 2026-10-21). The deploy fails if the host resolves the name outside this list."
  type        = list(string)
  default     = ["20.20.32.0/19", "20.190.128.0/18", "20.231.128.0/19", "40.126.0.0/18"]
}

variable "anthropic_cidrs" {
  description = "Anthropic API inbound range (published, fetched 2026-10-21). The deploy fails if the host resolves api.anthropic.com outside this list."
  type        = list(string)
  default     = ["160.79.104.0/23"]
}

variable "maintenance_egress" {
  description = "Open 80/443 to anywhere for package installation. Must be true on any apply that creates or replaces the instance (first boot installs Docker); false otherwise (OW-7)."
  type        = bool
  default     = false
}

variable "busy_grace_seconds" {
  description = "Seconds after boot during which the host always counts as busy (keeps a fresh start from stopping at once)"
  type        = number
  default     = 3600
}

variable "idle_stop_enabled" {
  description = "Whether the idle alarm stops the instance (false keeps it running, for example during migration week)"
  type        = bool
  default     = true
}

variable "idle_stop_minutes" {
  description = "Consecutive idle minutes before the host stops"
  type        = number
  default     = 30
}

variable "scheduled_start_enabled" {
  description = "Whether the morning schedule starts the instance"
  type        = bool
  default     = true
}

variable "start_schedule" {
  description = "EventBridge Scheduler expression for the morning start"
  type        = string
  default     = "cron(0 7 ? * MON-FRI *)"
}

variable "start_timezone" {
  description = "Time zone of start_schedule"
  type        = string
  default     = "America/New_York"
}

variable "listener_rule_priority" {
  description = "Priority of the backstage host rule on the prod HTTPS listener (prod's rules use 2-6, auto-assigned)"
  type        = number
  default     = 100
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the four Backstage log groups"
  type        = number
  default     = 30
}

variable "backup_retention_days" {
  description = "Weekly EBS snapshot retention (O-012 item 5)"
  type        = number
  default     = 30
}
