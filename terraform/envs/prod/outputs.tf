output "vpc_id" {
  description = "VPC ID"
  value       = "" # module.vpc.vpc_id
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = "" # module.alb.alb_dns_name
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = "" # module.rds.instance_endpoint
  sensitive   = true
}

output "ecr_repository_urls" {
  description = "ECR repository URLs"
  value       = {} # module.ecr.repository_urls
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = "" # module.ecs_cluster.cluster_name
}

output "route53_name_servers" {
  description = "Route 53 NS records (add to registrar for delegation)"
  value       = [] # module.route53.name_servers
}

output "github_deploy_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC"
  value       = "" # module.iam_github_oidc.deploy_role_arn
}
