output "oidc_provider_arn" {
  description = "GitHub OIDC provider ARN"
  value       = local.oidc_provider_arn
}

output "overcast_terraform_role_arn" {
  description = "Overcast Terraform deploy role ARN"
  value       = aws_iam_role.overcast_terraform.arn
}

output "ecr_push_role_arns" {
  description = "Map of service name to ECR push role ARN"
  value       = { for k, v in aws_iam_role.ecr_push : k => v.arn }
}
