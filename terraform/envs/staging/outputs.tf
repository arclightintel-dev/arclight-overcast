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

output "sg_podbay_controller_id" {
  description = "Podbay controller security group ID"
  value       = module.vpc.sg_podbay_controller_id
}

output "sg_podbay_workspace_id" {
  description = "Podbay workspace security group ID"
  value       = module.vpc.sg_podbay_workspace_id
}

output "podbay_workspace_task_family" {
  description = "Podbay workspace task definition family"
  value       = aws_ecs_task_definition.podbay_workspace.family
}

output "podbay_ec2_capacity_provider_name" {
  description = "Podbay EC2 capacity provider name (use in RunTask capacityProviderStrategy)"
  value       = module.ec2_capacity.capacity_provider_name
}

output "podbay_export_bucket_name" {
  description = "Podbay S3 export bucket name"
  value       = aws_s3_bucket.podbay_exports.id
}

output "podbay_task_role_arn" {
  description = "Podbay controller task role ARN"
  value       = aws_iam_role.podbay_task_role.arn
}

output "turn_endpoint" {
  description = "TURN server public IP (EIP)"
  value       = module.coturn.turn_endpoint
}
