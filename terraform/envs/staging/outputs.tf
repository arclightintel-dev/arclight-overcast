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

output "ecr_repository_urls" {
  description = "ECR repository URLs"
  value       = module.ecr.repository_urls
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs_cluster.cluster_name
}

output "sg_dbbootstrap_id" {
  description = "DB bootstrap security group ID"
  value       = module.vpc.sg_dbbootstrap_id
}

output "overcast_terraform_role_arn" {
  description = "IAM role ARN for Overcast Terraform deploys"
  value       = module.iam_github_oidc.overcast_terraform_role_arn
}

output "ecr_push_role_arns" {
  description = "Per-service ECR push role ARNs"
  value       = module.iam_github_oidc.ecr_push_role_arns
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

output "sg_core_id" {
  description = "Core security group ID"
  value       = module.vpc.sg_core_id
}

output "core_service_name" {
  description = "Core ECS service name"
  value       = module.core_service.service_name
}

output "core_task_definition_family" {
  description = "Core task definition family"
  value       = module.core_service.task_definition_family
}

output "bandersnatch_table_prefix" {
  description = "Bandersnatch DynamoDB table name prefix (null until enabled)"
  value       = local.bsn_enabled ? local.bsn_table_prefix : null
}

output "bandersnatch_bucket" {
  description = "Bandersnatch payload bucket name (null until enabled)"
  value       = one(aws_s3_bucket.bandersnatch[*].bucket)
}

output "bandersnatch_log_group" {
  description = "Bandersnatch log group name (null until enabled)"
  value       = one(aws_cloudwatch_log_group.bandersnatch[*].name)
}

output "bandersnatch_origin_secret_arn" {
  description = "Bandersnatch origin-secret shell ARN (null until enabled)"
  value       = one(aws_secretsmanager_secret.bsn_origin_secret[*].arn)
}

output "bandersnatch_graph_client_secret_arn" {
  description = "Bandersnatch Graph client-secret shell ARN (null until enabled)"
  value       = one(aws_secretsmanager_secret.bsn_graph_client_secret[*].arn)
}

output "bandersnatch_target_group_arn" {
  description = "Bandersnatch target group ARN (null until enabled)"
  value       = one(aws_lb_target_group.bandersnatch[*].arn)
}
