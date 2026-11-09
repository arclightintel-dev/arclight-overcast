output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "Private app subnet IDs"
  value       = module.vpc.private_app_subnet_ids
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.alb_dns_name
}

output "sg_dbbootstrap_id" {
  description = "DB bootstrap security group ID"
  value       = module.vpc.sg_dbbootstrap_id
}

output "sg_core_id" {
  description = "Core security group ID"
  value       = module.vpc.sg_core_id
}
