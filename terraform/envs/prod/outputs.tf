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

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.instance_endpoint
  sensitive   = true
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs_cluster.cluster_name
}

output "sg_dbbootstrap_id" {
  description = "DB bootstrap security group ID"
  value       = module.vpc.sg_dbbootstrap_id
}

output "sg_core_id" {
  description = "Core security group ID"
  value       = module.vpc.sg_core_id
}

output "overcast_terraform_role_arn" {
  description = "IAM role ARN for Overcast Terraform deploys"
  value       = module.iam_github_oidc.overcast_terraform_role_arn
}

output "cloud_map_namespace_id" {
  description = "Cloud Map private DNS namespace ID"
  value       = module.ecs_cluster.cloud_map_namespace_id
}

output "rds_master_user_secret_arn" {
  description = "ARN of RDS-managed master user secret"
  value       = module.rds.master_user_secret_arn
  sensitive   = true
}
