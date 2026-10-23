output "public_host" {
  description = "Backstage hostname (proxied Cloudflare CNAME to alb_dns_name)"
  value       = local.public_host
}

output "alb_dns_name" {
  description = "Prod ALB DNS name, the Cloudflare CNAME target"
  value       = data.aws_lb.prod.dns_name
}

output "instance_id" {
  description = "Backstage host instance ID"
  value       = aws_instance.host.id
}

output "host_security_group_id" {
  description = "Backstage host security group"
  value       = aws_security_group.host.id
}

output "target_group_arn" {
  description = "Backstage target group on the prod ALB"
  value       = aws_lb_target_group.host.arn
}

output "ecr_repository_urls" {
  description = "Backstage ECR repositories"
  value       = module.ecr.repository_urls
}

output "bucket_names" {
  description = "Migration, Litestream and deploy-bundle buckets"
  value       = { for k, b in aws_s3_bucket.this : k => b.bucket }
}

output "secret_names" {
  description = "Secret shells the owner fills (values never in Terraform)"
  value       = [for s in aws_secretsmanager_secret.this : s.name]
}

output "ssm_parameter_prefix" {
  description = "SSM Parameter Store prefix the host reads at run time"
  value       = local.ssm_prefix
}

output "log_groups" {
  description = "CloudWatch log groups by container role"
  value       = local.log_groups
}

output "alb_subnet_cidrs" {
  description = "Subnets of the prod ALB's nodes (Backstage PODBAY_TRUSTED_PROXIES, with 127.0.0.1)"
  value       = local.alb_subnet_cidrs
}

output "push_role_arn" {
  description = "Role Backstage CI assumes from main to push images and deploy bundles"
  value       = aws_iam_role.push.arn
}

output "deploy_role_arn" {
  description = "Role the deploy-backstage workflow assumes (GitHub environment backstage)"
  value       = aws_iam_role.deploy.arn
}

output "downloads_host" {
  description = "Desktop downloads hostname (DNS-only Cloudflare CNAME to downloads_distribution_domain)"
  value       = local.downloads_host
}

output "downloads_distribution_domain" {
  description = "CloudFront domain for the downloads CNAME"
  value       = aws_cloudfront_distribution.downloads.domain_name
}

output "downloads_bucket" {
  description = "DESKTOP_DOWNLOADS_BUCKET for the desktop-release environment"
  value       = aws_s3_bucket.downloads.bucket
}

output "downloads_upload_role_arn" {
  description = "DESKTOP_DOWNLOADS_ROLE_ARN for the desktop-release environment"
  value       = aws_iam_role.downloads_upload.arn
}
